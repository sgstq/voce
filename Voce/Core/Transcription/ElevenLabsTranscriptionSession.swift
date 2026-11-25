import Foundation
import os

/// One live transcription session over the ElevenLabs realtime WebSocket.
/// Lifecycle: `start()` → `sendAudio(_:)` while the hotkey is held →
/// `commit()` on release → consume `events` until a terminal event.
actor ElevenLabsTranscriptionSession: TranscriptionSession {
    nonisolated let events: AsyncStream<TranscriptionEvent>

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "elevenlabs")

    private let webSocket: URLSessionWebSocketTask
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let model: String
    private var receiveTask: Task<Void, Never>?
    private var finished = false

    /// The newest chunk is held back one step so a commit always rides on
    /// real audio: the docs only show `commit: true` on a chunk with audio.
    private var heldChunk: Data?
    /// Seconds of audio sent since the last commit.
    private var uncommittedSeconds: TimeInterval = 0
    /// Commits sent whose `committed_transcript` has not arrived yet.
    private var pendingCommits = 0
    private var releaseRequested = false
    /// Concatenation of every committed segment — becomes the transcript.
    private var finalizedTranscript = ""

    init(
        apiKey: String,
        model: String,
        language: String,
        hints: TranscriptionHints,
        endpoint: URL = ElevenLabsProtocol.defaultEndpoint
    ) {
        var request = URLRequest(
            url: ElevenLabsProtocol.endpoint(model: model, language: language, hints: hints, base: endpoint)
        )
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        self.webSocket = URLSession.shared.webSocketTask(with: request)
        self.model = model
        (self.events, self.continuation) = AsyncStream.makeStream(
            of: TranscriptionEvent.self,
            bufferingPolicy: .unbounded
        )
    }

    func start() {
        Self.log.notice("connecting model=\(self.model, privacy: .public)")
        // Session options travel in the URL; URLSessionWebSocketTask queues
        // sends until the handshake finishes, so audio can flow right away.
        webSocket.resume()
        receiveTask = Task { await receiveLoop() }
    }

    func sendAudio(_ pcm16: Data) {
        guard !finished, !releaseRequested, !pcm16.isEmpty else { return }
        if let previous = heldChunk {
            uncommittedSeconds += Self.duration(of: previous)
            // Long dictations commit every ~25 s so the server never
            // commits a segment on its own that we would not count.
            let commit = uncommittedSeconds >= ElevenLabsProtocol.commitInterval
            sendChunk(previous, commit: commit)
        }
        heldChunk = pcm16
    }

    func commit() {
        guard !finished, !releaseRequested else { return }
        releaseRequested = true
        if let last = heldChunk {
            heldChunk = nil
            sendChunk(last, commit: true)
        } else if pendingCommits == 0 {
            // Nothing was recorded at all.
            complete()
        }
    }

    func abort() {
        finish()
    }

    private func sendChunk(_ pcm16: Data, commit: Bool) {
        let json: String
        do {
            json = try ElevenLabsProtocol.audioChunkJSON(pcm16: pcm16, commit: commit)
        } catch {
            fail("Failed to encode audio: \(error.localizedDescription)")
            return
        }
        if commit {
            pendingCommits += 1
            uncommittedSeconds = 0
        }
        // Callback-based send: enqueues synchronously, preserving order.
        webSocket.send(.string(json)) { [weak self] error in
            guard let error else { return }
            Task { await self?.handleSendFailure(error) }
        }
    }

    private func receiveLoop() async {
        while !finished {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await webSocket.receive()
            } catch {
                if !finished {
                    fail(error.localizedDescription)
                }
                return
            }

            guard case .string(let text) = message else { continue }

            switch ElevenLabsProtocol.parseServerEvent(text) {
            case .sessionStarted:
                continuation.yield(.ready)
            case .partial(let partial):
                handlePartial(partial)
            case .committed(let segment):
                handleCommitted(segment)
            case .noSpeech:
                handleCommitted("")
            case .error(let message):
                fail(message)
                return
            case .ignored:
                continue
            }
        }
    }

    private func handlePartial(_ partial: String) {
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        continuation.yield(.preview(finalizedTranscript.isEmpty ? trimmed : finalizedTranscript + " " + trimmed))
    }

    private func handleCommitted(_ segment: String) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let delta = finalizedTranscript.isEmpty ? trimmed : " " + trimmed
            finalizedTranscript += delta
            continuation.yield(.delta(delta))
        }
        pendingCommits = max(0, pendingCommits - 1)
        if releaseRequested, pendingCommits == 0 {
            complete()
        }
    }

    private func complete() {
        guard !finished else { return }
        Self.log.notice("completed chars=\(self.finalizedTranscript.count)")
        continuation.yield(.completed(finalizedTranscript))
        finish(emitClosed: false)
    }

    private func handleSendFailure(_ error: Error) {
        guard !finished else { return }
        fail("Failed to send audio: \(error.localizedDescription)")
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
        receiveTask?.cancel()
        webSocket.cancel(with: .normalClosure, reason: nil)
        if emitClosed {
            continuation.yield(.closed)
        }
        continuation.finish()
    }

    private static func duration(of pcm16: Data) -> TimeInterval {
        TimeInterval(pcm16.count / 2) / TimeInterval(ElevenLabsProtocol.sampleRate)
    }
}
