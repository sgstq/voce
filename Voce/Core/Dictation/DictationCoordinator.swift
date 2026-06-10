import AppKit
import Foundation
import os

/// Owns the push-to-talk dictation loop:
/// hotkey down → mic + realtime session + overlay → hotkey up → commit →
/// final transcript → clipboard-free insertion. Everything runs off the main
/// actor except UI state; nothing ever blocks.
@MainActor
final class DictationCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case finalizing
        case refining
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hotkeyError: String?

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "dictation")

    /// Mirrors the prototype's guards: ignore blips shorter than this or
    /// quieter than the silence threshold (normalized RMS).
    private static let minimumDuration: TimeInterval = 0.15
    private static let silenceRMSThreshold = 0.005
    private static let completionTimeout: Duration = .seconds(10)
    private static let errorDisplayTime: Duration = .seconds(3)

    private let audio = AudioCaptureEngine()
    private let overlay = OverlayController()
    private let inserter = TextInserter()
    private let refiner = Refiner()
    private let configProvider: @MainActor () -> AppConfig
    private let apiKeyProvider: @MainActor () throws -> String?
    private let refinementKeyProvider: @MainActor (RefinementProvider) throws -> String?

    private var hotkey: HotkeyMonitor?
    private var session: RealtimeTranscriptionSession?
    private var eventTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?

    private var transcript = ""
    private var sampleCount = 0
    private var sumSquares = 0.0
    private var releaseContext: FocusContext?

    init(
        configProvider: @escaping @MainActor () -> AppConfig,
        apiKeyProvider: @escaping @MainActor () throws -> String?,
        refinementKeyProvider: @escaping @MainActor (RefinementProvider) throws -> String?
    ) {
        self.configProvider = configProvider
        self.apiKeyProvider = apiKeyProvider
        self.refinementKeyProvider = refinementKeyProvider
    }

    var isHotkeyRunning: Bool { hotkey?.isRunning ?? false }

    // MARK: Hotkey lifecycle

    func startHotkey() {
        stopHotkey()
        let monitor = HotkeyMonitor(
            spec: configProvider().hotkey,
            onPress: { [weak self] in self?.beginDictation() },
            onRelease: { [weak self] in self?.endDictation() }
        )
        do {
            try monitor.start()
            hotkey = monitor
            hotkeyError = nil
        } catch {
            hotkeyError = error.localizedDescription
        }
    }

    func stopHotkey() {
        hotkey?.stop()
        hotkey = nil
    }

    /// Re-registers the tap after a config change or once Accessibility is granted.
    func restartHotkeyIfNeeded() {
        startHotkey()
    }

    // MARK: Dictation loop

    private func beginDictation() {
        guard phase == .idle else { return }

        let config = configProvider()
        let apiKey = (try? apiKeyProvider()) ?? nil
        guard let apiKey, !apiKey.isEmpty else {
            Self.log.warning("begin: no API key configured")
            showTransientError("Add your OpenAI API key in Settings")
            return
        }
        Self.log.notice("begin: model=\(config.realtimeModel, privacy: .public) insertion=\(config.insertionMode.rawValue, privacy: .public)")

        transcript = ""
        sampleCount = 0
        sumSquares = 0
        releaseContext = nil
        errorDismissTask?.cancel()

        let session = RealtimeTranscriptionSession(
            apiKey: apiKey,
            model: config.realtimeModel,
            language: config.language,
            delay: config.realtimeDelay
        )
        self.session = session

        let chunks: AsyncStream<Data>
        do {
            chunks = try audio.start()
        } catch {
            self.session = nil
            Self.log.error("begin: audio start failed: \(error.localizedDescription, privacy: .public)")
            showTransientError("Microphone failed: \(error.localizedDescription)")
            return
        }

        phase = .recording
        overlay.model.phase = .listening
        overlay.model.updateLiveText("")
        overlay.model.resetLevels()
        overlay.show()

        // Warm the refinement path while the user is still speaking so TLS
        // handshakes / model loading never sit inside the "Polishing…" wait.
        if config.refinementEnabled {
            refiner.prewarm(provider: config.refinementProvider)
        }

        Task { await session.start() }

        // Single consumer keeps audio chunks ordered end-to-end.
        audioTask = Task { [weak self] in
            for await chunk in chunks {
                guard let self else { return }
                let stats = AudioMath.rmsEnergy(pcm16: chunk)
                self.accumulate(stats)
                // Drive the overlay waveform with this chunk's level. Speech
                // RMS tops out around 0.25; the 0.6 exponent lifts quiet talk.
                if stats.sampleCount > 0 {
                    let rms = (stats.sumSquares / Double(stats.sampleCount)).squareRoot()
                    self.overlay.model.pushLevel(pow(min(1.0, rms / 0.25), 0.6))
                }
                await session.sendAudio(chunk)
            }
        }

        eventTask = Task { [weak self] in
            for await event in session.events {
                self?.handle(event)
            }
        }
    }

    private func endDictation() {
        guard phase == .recording, let session else {
            return
        }

        audio.stop()

        let duration = Double(sampleCount) / Double(RealtimeProtocol.sampleRate)
        let rms = sampleCount > 0 ? (sumSquares / Double(sampleCount)).squareRoot() : 0
        Self.log.notice("end: duration=\(String(format: "%.2f", duration), privacy: .public)s rms=\(String(format: "%.4f", rms), privacy: .public)")
        guard duration >= Self.minimumDuration, rms >= Self.silenceRMSThreshold else {
            Self.log.notice("end: discarded (too short or silent)")
            Task { await session.abort() }
            reset()
            return
        }

        phase = .finalizing
        overlay.model.phase = .finalizing

        // Snapshot what we're dictating into at the moment of release — the
        // refiner uses the surrounding text; the insertion guard uses the
        // app identity.
        releaseContext = FocusContextCapture.capture(includeText: configProvider().captureContext)

        Task { await session.commit() }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.completionTimeout)
            guard !Task.isCancelled else { return }
            self?.finishFromTimeout()
        }
    }

    private func accumulate(_ stats: (sumSquares: Double, sampleCount: Int)) {
        sumSquares += stats.sumSquares
        sampleCount += stats.sampleCount
    }

    private func handle(_ event: RealtimeTranscriptionSession.Event) {
        switch event {
        case .ready:
            break

        case .delta(let delta):
            transcript += delta
            overlay.model.updateLiveText(transcript)

        case .completed(let finalTranscript):
            Self.log.notice("event: completed chars=\(finalTranscript.count) accumulated=\(self.transcript.count)")
            // The completed payload is authoritative for a single item, but if
            // the server ever segments long audio into multiple items, the
            // accumulated deltas hold the full text — prefer them when they
            // are substantially longer.
            let accumulated = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            var text = finalTranscript.isEmpty ? accumulated : finalTranscript
            if Double(accumulated.count) > Double(text.count) * 1.25 {
                Self.log.warning("completed shorter than accumulated deltas; using accumulated")
                text = accumulated
            }
            finishDictation(with: text)

        case .failed(let message):
            Self.log.error("event: failed: \(message, privacy: .public)")
            if phase == .finalizing, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Partial preview beats losing the dictation outright.
                finishDictation(with: transcript)
            } else if phase == .recording || phase == .finalizing {
                showTransientError(message)
                cancelDictation()
            }

        case .closed:
            if phase == .finalizing {
                let pending = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if pending.isEmpty {
                    showTransientError("The session closed without a transcript")
                    cancelDictation()
                } else {
                    finishDictation(with: pending)
                }
            }
        }
    }

    private func finishFromTimeout() {
        guard phase == .finalizing else { return }
        let pending = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if pending.isEmpty {
            showTransientError("Timed out waiting for the transcript")
            cancelDictation()
        } else {
            finishDictation(with: pending)
        }
    }

    private func finishDictation(with text: String) {
        // Single-delivery gate: a transcript can be delivered by .completed,
        // a trailing .closed, .failed-with-partial, or the timeout — only the
        // first one may insert. .refining marks "already delivered".
        guard phase == .recording || phase == .finalizing else { return }
        phase = .refining
        audio.stop()

        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = configProvider()
        let context = releaseContext ?? FocusContext()

        cleanupSession()

        guard !rawText.isEmpty else {
            overlay.hide()
            phase = .idle
            return
        }

        let provider = config.refinementProvider
        let refinementKey = ((try? refinementKeyProvider(provider)) ?? nil) ?? ""
        let cloudKeyMissing = provider.isCloud && refinementKey.isEmpty
        guard config.refinementEnabled, !cloudKeyMissing else {
            if config.refinementEnabled, cloudKeyMissing {
                Self.log.warning("refinement skipped: no API key for \(provider.rawValue, privacy: .public)")
            }
            insertAfterGuard(rawText, mode: config.insertionMode, context: context)
            return
        }

        overlay.model.phase = .refining
        let refiner = self.refiner
        Task { [weak self] in
            var finalText = rawText
            do {
                finalText = try await refiner.refine(
                    transcript: rawText,
                    context: context,
                    provider: provider,
                    model: config.refinementModel,
                    apiKey: refinementKey,
                    language: config.language
                )
            } catch {
                Self.log.error("refinement failed, using raw: \(error.localizedDescription, privacy: .public)")
            }
            self?.insertAfterGuard(finalText, mode: config.insertionMode, context: context)
        }
    }

    /// Refuses to type into a different app than the one the user dictated
    /// into — focus can move during transcription/refinement.
    private func insertAfterGuard(_ text: String, mode: InsertionMode, context: FocusContext) {
        overlay.hide()
        phase = .idle

        if !context.bundleIdentifier.isEmpty,
           let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           current != context.bundleIdentifier {
            Self.log.warning("insert skipped: focus moved \(context.bundleIdentifier, privacy: .public) -> \(current, privacy: .public)")
            showTransientError("Focus moved to another app; insertion skipped")
            return
        }

        let inserter = self.inserter
        Task { [weak self] in
            do {
                try await inserter.insert(text, mode: mode)
            } catch {
                Self.log.error("insertion failed: \(error.localizedDescription, privacy: .public)")
                self?.showTransientError("Insertion failed: \(error.localizedDescription)")
            }
        }
    }

    /// Tears down a session that did NOT produce a deliverable transcript.
    private func cancelDictation() {
        audio.stop()
        if let session {
            Task { await session.abort() }
        }
        cleanupSession()
        phase = .idle
    }

    private func reset() {
        cleanupSession()
        overlay.hide()
        phase = .idle
    }

    private func cleanupSession() {
        timeoutTask?.cancel()
        timeoutTask = nil
        audioTask?.cancel()
        audioTask = nil
        eventTask?.cancel()
        eventTask = nil
        session = nil
    }

    private func showTransientError(_ message: String) {
        overlay.model.phase = .error(message)
        overlay.model.text = ""
        overlay.show()

        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.errorDisplayTime)
            guard !Task.isCancelled, let self, self.phase == .idle else { return }
            self.overlay.hide()
        }
    }
}
