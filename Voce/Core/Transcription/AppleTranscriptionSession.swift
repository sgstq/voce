import AVFoundation
import Foundation
import os
import Speech

/// One live transcription session running fully on-device via SpeechAnalyzer.
/// Lifecycle: `start()` → `sendAudio(_:)` while the hotkey is held →
/// `commit()` on release → consume `events` until a terminal event.
actor AppleTranscriptionSession: TranscriptionSession {
    enum SessionError: LocalizedError {
        case bufferAllocationFailed
        case converterUnavailable
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .bufferAllocationFailed: "Could not allocate an audio buffer."
            case .converterUnavailable: "The audio converter could not be created."
            case .conversionFailed: "Audio conversion failed."
            }
        }
    }

    nonisolated let events: AsyncStream<TranscriptionEvent>

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "applespeech")

    /// Format of the chunks AudioCaptureEngine emits (24 kHz mono PCM16).
    static var captureFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(RealtimeProtocol.sampleRate),
            channels: 1,
            interleaved: true
        )!
    }

    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let language: String

    /// Raw PCM16 chunks bridged from `sendAudio` into the analysis task.
    private let audioChunks: AsyncStream<Data>
    private let audioContinuation: AsyncStream<Data>.Continuation

    private var analyzer: SpeechAnalyzer?
    private var runTask: Task<Void, Never>?
    private var finished = false
    /// Concatenation of every final result — becomes the transcript.
    private var finalizedTranscript = ""

    init(language: String) {
        self.language = language
        (self.events, self.continuation) = AsyncStream.makeStream(
            of: TranscriptionEvent.self,
            bufferingPolicy: .unbounded
        )
        (self.audioChunks, self.audioContinuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .unbounded
        )
    }

    func start() {
        runTask = Task { await run() }
    }

    func sendAudio(_ pcm16: Data) {
        guard !finished, !pcm16.isEmpty else { return }
        audioContinuation.yield(pcm16)
    }

    func commit() {
        guard !finished else { return }
        // Ending the audio stream lets `run()` finalize the analysis.
        audioContinuation.finish()
    }

    func abort() {
        finish()
    }

    private func run() async {
        guard let locale = await AppleSpeechAssets.resolveLocale(for: language) else {
            fail("On-device recognition does not support \(DictationLanguages.displayName(for: language))")
            return
        }
        let transcriber = AppleSpeechAssets.transcriber(for: locale)

        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            fail("Download the on-device speech model in Settings first")
            return
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            fail("No compatible audio format for on-device recognition")
            return
        }

        Self.log.notice("starting locale=\(locale.identifier, privacy: .public)")

        // Keep the model loaded between dictations: push-to-talk sessions are
        // short and frequent, and a cold model load would eat into latency.
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )
        self.analyzer = analyzer

        let (inputs, inputContinuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .unbounded
        )

        let resultsTask = Task { await consumeResults(from: transcriber) }

        do {
            try await analyzer.start(inputSequence: inputs)
        } catch {
            inputContinuation.finish()
            resultsTask.cancel()
            fail("On-device recognition failed to start: \(error.localizedDescription)")
            return
        }

        // Pump captured chunks into the analyzer until commit()/abort().
        do {
            let converter = ChunkConverter(format: format)
            for await chunk in audioChunks {
                guard !finished else { break }
                let buffer = try Self.pcm16Buffer(from: chunk)
                inputContinuation.yield(AnalyzerInput(buffer: try converter.convert(buffer)))
            }
            inputContinuation.finish()
            guard !finished else { return }
            // Commit: transcribe everything buffered, finalize the volatile
            // tail, and end the results stream.
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            inputContinuation.finish()
            fail("On-device recognition failed: \(error.localizedDescription)")
        }
    }

    private func consumeResults(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                handle(result)
            }
            guard !finished else { return }
            Self.log.notice("completed chars=\(self.finalizedTranscript.count)")
            continuation.yield(.completed(finalizedTranscript))
            finish(emitClosed: false)
        } catch {
            if !finished {
                fail(error.localizedDescription)
            }
        }
    }

    /// Final results append to the transcript; volatile results only refresh
    /// the live preview because the recognizer may still rewrite them.
    /// Apple's transcripts carry their own leading spacing — append as-is.
    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        guard !text.isEmpty else { return }
        if result.isFinal {
            finalizedTranscript += text
            continuation.yield(.delta(text))
        } else {
            continuation.yield(.preview(finalizedTranscript + text))
        }
    }

    /// Wraps a chunk of interleaved mono PCM16 bytes in an AVAudioPCMBuffer.
    static func pcm16Buffer(from data: Data) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard
            frames > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: frames),
            let channels = buffer.int16ChannelData
        else {
            throw SessionError.bufferAllocationFailed
        }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            UnsafeMutableRawPointer(channels[0]).copyMemory(
                from: raw.baseAddress!,
                byteCount: Int(frames) * MemoryLayout<Int16>.size
            )
        }
        return buffer
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        Self.log.error("failed: \(message, privacy: .public)")
        continuation.yield(.failed(message))
        finish(emitClosed: false)
    }

    /// `.closed` is only emitted when the stream ends WITHOUT a terminal
    /// `.completed`/`.failed` — consumers must see exactly one terminal event.
    private func finish(emitClosed: Bool = true) {
        guard !finished else { return }
        finished = true
        audioContinuation.finish()
        runTask?.cancel()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        if emitClosed {
            continuation.yield(.closed)
        }
        continuation.finish()
    }
}

/// Converts capture-format chunks to the analyzer's format, reusing one
/// converter so resampler state carries over between chunks. Only used
/// serially from the session's pump loop, so access is serial even though
/// the type crosses an isolation boundary.
private final class ChunkConverter: @unchecked Sendable {
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?

    init(format: AVAudioFormat) {
        self.format = format
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == format {
            return buffer
        }
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else {
            throw AppleTranscriptionSession.SessionError.converterUnavailable
        }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AppleTranscriptionSession.SessionError.bufferAllocationFailed
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let conversionError {
            throw conversionError
        }
        guard status != .error else {
            throw AppleTranscriptionSession.SessionError.conversionFailed
        }
        return output
    }
}
