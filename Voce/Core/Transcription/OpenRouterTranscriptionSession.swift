import Foundation
import os

/// One push-to-talk transcription through OpenRouter's file-based
/// speech-to-text endpoint. Audio is buffered while the hotkey is held and
/// uploaded in a single request on `commit()`, so there are no interim
/// results — the session emits `.ready`, then exactly one terminal event.
actor OpenRouterTranscriptionSession: TranscriptionSession {
    nonisolated let events: AsyncStream<TranscriptionEvent>

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "openrouter")

    private let apiKey: String
    private let model: String
    private let language: String
    private let endpoint: URL
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private var audio = Data()
    private var requestTask: Task<Void, Never>?
    private var finished = false

    init(
        apiKey: String,
        model: String,
        language: String,
        endpoint: URL = OpenRouterProtocol.defaultEndpoint
    ) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.endpoint = endpoint
        (self.events, self.continuation) = AsyncStream.makeStream(
            of: TranscriptionEvent.self,
            bufferingPolicy: .unbounded
        )
    }

    func start() {
        Self.log.notice("buffering model=\(self.model, privacy: .public)")
        prewarm()
        continuation.yield(.ready)
    }

    func sendAudio(_ pcm16: Data) {
        guard !finished, requestTask == nil, !pcm16.isEmpty else { return }
        audio.append(pcm16)
    }

    func commit() {
        guard !finished, requestTask == nil else { return }
        let request: URLRequest
        do {
            request = try OpenRouterProtocol.transcriptionRequest(
                apiKey: apiKey,
                model: model,
                language: language,
                pcm16: audio,
                endpoint: endpoint
            )
        } catch {
            fail("Failed to encode the recording: \(error.localizedDescription)")
            return
        }
        Self.log.notice("uploading bytes=\(self.audio.count)")
        audio = Data()
        requestTask = Task { await perform(request) }
    }

    func abort() {
        finish()
    }

    private func perform(_ request: URLRequest) async {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // An abort cancels the request; only report failures nobody asked for.
            if !finished {
                fail(error.localizedDescription)
            }
            return
        }
        guard !finished else { return }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch OpenRouterProtocol.parseResponse(data, statusCode: status) {
        case .transcript(let text):
            Self.log.notice("completed chars=\(text.count)")
            continuation.yield(.completed(text))
            finish(emitClosed: false)
        case .error(let message):
            fail(message)
        }
    }

    /// Opens the TLS connection while the user is still speaking so the
    /// handshake never sits inside the post-release wait. Fire-and-forget:
    /// the pooled connection is the point, not the response.
    private func prewarm() {
        guard let host = endpoint.host, let url = URL(string: "https://\(host)/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        Task.detached {
            _ = try? await URLSession.shared.data(for: request)
        }
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
        requestTask?.cancel()
        audio = Data()
        if emitClosed {
            continuation.yield(.closed)
        }
        continuation.finish()
    }
}
