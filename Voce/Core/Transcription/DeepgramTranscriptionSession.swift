import Foundation
import os

/// One live transcription session over the Deepgram streaming WebSocket.
/// Lifecycle: `start()` → `sendAudio(_:)` while the hotkey is held →
/// `commit()` on release → consume `events` until a terminal event.
actor DeepgramTranscriptionSession: TranscriptionSession {
    nonisolated let events: AsyncStream<TranscriptionEvent>

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "deepgram")

    private let webSocket: URLSessionWebSocketTask
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let model: String
    private var receiveTask: Task<Void, Never>?
    private var finished = false
    /// Concatenation of every `is_final` segment — becomes the transcript.
    private var finalizedTranscript = ""

    init(
        apiKey: String,
        model: String,
        language: String,
        endpoint: URL = DeepgramProtocol.defaultEndpoint
    ) {
        var request = URLRequest(
            url: DeepgramProtocol.endpoint(model: model, language: language, base: endpoint)
        )
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        self.webSocket = URLSession.shared.webSocketTask(with: request)
        self.model = model
        (self.events, self.continuation) = AsyncStream.makeStream(
            of: TranscriptionEvent.self,
            bufferingPolicy: .unbounded
        )
    }

    func start() {
        Self.log.notice("connecting model=\(self.model, privacy: .public)")
        // All session config travels in the URL, so audio can flow as soon as
        // the handshake completes — there is no ready message to wait for.
        // URLSessionWebSocketTask queues sends until the handshake finishes.
        webSocket.resume()
        receiveTask = Task { await receiveLoop() }
    }

    func sendAudio(_ pcm16: Data) {
        guard !finished, !pcm16.isEmpty else { return }
        send(.data(pcm16), failure: "Failed to send audio")
    }

    func commit() {
        guard !finished else { return }
        // CloseStream makes the server transcribe the buffered audio, emit
        // the final Results and a Metadata message, then close the socket.
        send(.string(DeepgramProtocol.closeStreamJSON), failure: "Failed to commit audio")
    }

    func abort() {
        finish()
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

            switch DeepgramProtocol.parseServerEvent(text) {
            case .results(let transcript, let isFinal):
                handleResults(transcript, isFinal: isFinal)
            case .metadata:
                Self.log.notice("completed chars=\(self.finalizedTranscript.count)")
                continuation.yield(.completed(finalizedTranscript))
                finish(emitClosed: false)
                return
            case .ignored:
                continue
            }
        }
    }

    /// Final segments append to the transcript; interim segments only refresh
    /// the live preview because Deepgram may still rewrite them.
    private func handleResults(_ transcript: String, isFinal: Bool) {
        guard !transcript.isEmpty else { return }
        if isFinal {
            let delta = finalizedTranscript.isEmpty ? transcript : " " + transcript
            finalizedTranscript += delta
            continuation.yield(.delta(delta))
        } else if finalizedTranscript.isEmpty {
            continuation.yield(.preview(transcript))
        } else {
            continuation.yield(.preview(finalizedTranscript + " " + transcript))
        }
    }

    /// Callback-based send: enqueues synchronously, preserving invocation
    /// order across the actor (async `send` from separate Tasks would not).
    private func send(_ message: URLSessionWebSocketTask.Message, failure: String) {
        webSocket.send(message) { [weak self] error in
            guard let error else { return }
            Task { await self?.handleSendFailure(failure, error) }
        }
    }

    private func handleSendFailure(_ prefix: String, _ error: Error) {
        guard !finished else { return }
        fail("\(prefix): \(error.localizedDescription)")
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
        webSocket.cancel(with: .goingAway, reason: nil)
        if emitClosed {
            continuation.yield(.closed)
        }
        continuation.finish()
    }
}
