import Foundation
import os

/// One live transcription session over the OpenAI Realtime WebSocket.
/// Lifecycle: `start()` → `sendAudio(_:)` while the hotkey is held →
/// `commit()` on release → consume `events` until `.completed`/`.failed`/`.closed`.
actor RealtimeTranscriptionSession {
    enum Event: Equatable, Sendable {
        case ready
        case delta(String)
        case completed(String)
        case failed(String)
        case closed
    }

    let events: AsyncStream<Event>

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "realtime")

    private let webSocket: URLSessionWebSocketTask
    private let continuation: AsyncStream<Event>.Continuation
    private let model: String
    private let language: String
    private let delay: RealtimeDelay
    private var receiveTask: Task<Void, Never>?
    private var finished = false

    init(
        apiKey: String,
        model: String,
        language: String,
        delay: RealtimeDelay,
        endpoint: URL = RealtimeProtocol.defaultEndpoint
    ) {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        self.webSocket = URLSession.shared.webSocketTask(with: request)
        self.model = model
        self.language = language
        self.delay = delay
        (self.events, self.continuation) = AsyncStream.makeStream(
            of: Event.self,
            bufferingPolicy: .unbounded
        )
    }

    func start() {
        Self.log.notice("connecting model=\(self.model, privacy: .public)")
        webSocket.resume()

        // URLSessionWebSocketTask queues sends in invocation order until the
        // handshake completes, so configuring first guarantees the session is
        // a transcription session before any audio arrives.
        do {
            try send(RealtimeProtocol.sessionUpdateJSON(model: model, language: language, delay: delay))
        } catch {
            fail("Failed to configure the transcription session: \(error.localizedDescription)")
            return
        }

        receiveTask = Task { await receiveLoop() }
    }

    func sendAudio(_ pcm16: Data) {
        guard !finished, !pcm16.isEmpty else { return }
        do {
            try send(RealtimeProtocol.appendEventJSON(pcm16: pcm16))
        } catch {
            fail("Failed to send audio: \(error.localizedDescription)")
        }
    }

    func commit() {
        guard !finished else { return }
        do {
            try send(RealtimeProtocol.commitEventJSON())
        } catch {
            fail("Failed to commit audio: \(error.localizedDescription)")
        }
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

            switch RealtimeProtocol.parseServerEvent(text) {
            case .ready:
                Self.log.notice("session ready")
                continuation.yield(.ready)
            case .delta(let delta):
                continuation.yield(.delta(delta))
            case .completed(let transcript):
                Self.log.notice("completed chars=\(transcript.count)")
                continuation.yield(.completed(transcript))
                finish(emitClosed: false)
                return
            case .error(let message):
                Self.log.error("server error: \(message, privacy: .public)")
                fail(message)
                return
            case .ignored:
                continue
            }
        }
    }

    /// Callback-based send: enqueues synchronously, preserving invocation
    /// order across the actor (async `send` from separate Tasks would not).
    private func send(_ json: String) {
        webSocket.send(.string(json)) { [weak self] error in
            guard let error else { return }
            Task { await self?.handleSendFailure(error) }
        }
    }

    private func handleSendFailure(_ error: Error) {
        guard !finished else { return }
        fail(error.localizedDescription)
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
