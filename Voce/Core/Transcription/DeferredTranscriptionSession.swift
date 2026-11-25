import Foundation
import os

/// Holds a dictation's audio while on-screen terms are read, then opens the
/// real session with them. Providers take keyterms when the connection
/// opens, so the terms must exist first; the wait is capped so a slow
/// screen read only drops the terms, never delays or loses audio.
actor DeferredTranscriptionSession: TranscriptionSession {
    nonisolated let events: AsyncStream<TranscriptionEvent>

    static let termsWait: Duration = .milliseconds(300)

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "dictation")

    private enum Command {
        case audio(Data)
        case commit
    }

    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let commands: AsyncStream<Command>
    private let commandContinuation: AsyncStream<Command>.Continuation
    private let screenText: Task<String?, Never>
    private let makeSession: @Sendable ([String]) -> any TranscriptionSession
    private var inner: (any TranscriptionSession)?
    private var pumpTask: Task<Void, Never>?
    private var aborted = false

    init(
        screenText: Task<String?, Never>,
        makeSession: @escaping @Sendable (_ screenTerms: [String]) -> any TranscriptionSession
    ) {
        self.screenText = screenText
        self.makeSession = makeSession
        (self.events, self.continuation) = AsyncStream.makeStream(of: TranscriptionEvent.self, bufferingPolicy: .unbounded)
        (self.commands, self.commandContinuation) = AsyncStream.makeStream(of: Command.self, bufferingPolicy: .unbounded)
    }

    func start() {
        pumpTask = Task { await pump() }
    }

    func sendAudio(_ pcm16: Data) {
        commandContinuation.yield(.audio(pcm16))
    }

    func commit() {
        commandContinuation.yield(.commit)
    }

    func abort() {
        guard !aborted else { return }
        aborted = true
        commandContinuation.finish()
        if let inner {
            Task { await inner.abort() }
        } else {
            continuation.yield(.closed)
            continuation.finish()
        }
    }

    /// One consumer keeps audio and the commit in their original order.
    private func pump() async {
        let terms = await Self.terms(from: screenText, within: Self.termsWait)
        guard !aborted else { return }
        Self.log.notice("screen terms for transcription: \(terms.count)")

        let session = makeSession(terms)
        inner = session
        let continuation = self.continuation
        Task {
            for await event in session.events {
                continuation.yield(event)
            }
            continuation.finish()
        }
        await session.start()

        for await command in commands {
            switch command {
            case .audio(let chunk):
                await session.sendAudio(chunk)
            case .commit:
                await session.commit()
            }
        }
    }

    /// The distilled terms if the read finishes in time, otherwise none.
    /// Awaiting a task's value ignores cancellation, so this races it
    /// against a timer instead of a task group, which would wait for both.
    private static func terms(from screenText: Task<String?, Never>, within limit: Duration) async -> [String] {
        await withCheckedContinuation { continuation in
            let race = FirstResult(continuation)
            Task {
                let text = await screenText.value
                race.resume(returning: text.map { VocabularyDistiller.distill(from: $0) } ?? [])
            }
            Task {
                try? await Task.sleep(for: limit)
                race.resume(returning: [])
            }
        }
    }
}

/// Resumes its continuation with whichever result arrives first.
private final class FirstResult: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<[String], Never>?>

    init(_ continuation: CheckedContinuation<[String], Never>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func resume(returning terms: [String]) {
        let pending = continuation.withLock { stored in
            defer { stored = nil }
            return stored
        }
        pending?.resume(returning: terms)
    }
}
