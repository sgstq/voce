import Foundation

/// Events emitted by a live transcription session. Consumers see exactly one
/// terminal event: `.completed`, `.failed`, or `.closed`.
enum TranscriptionEvent: Equatable, Sendable {
    case ready
    /// Append-only text that is final for the session's transcript.
    case delta(String)
    /// Full replacement for the overlay's live text (finalized + interim).
    /// Preview only — never contributes to the committed transcript.
    case preview(String)
    case completed(String)
    case failed(String)
    case closed
}

/// One live push-to-talk transcription session, independent of provider.
/// Lifecycle: `start()` → `sendAudio(_:)` while the hotkey is held →
/// `commit()` on release → consume `events` until a terminal event.
protocol TranscriptionSession: Actor {
    nonisolated var events: AsyncStream<TranscriptionEvent> { get }
    func start()
    func sendAudio(_ pcm16: Data)
    func commit()
    func abort()
}
