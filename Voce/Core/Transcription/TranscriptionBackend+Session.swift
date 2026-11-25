import Foundation

extension TranscriptionBackend {
    /// Builds a fresh streaming session for this backend. `apiKey` is
    /// ignored by backends that need none.
    func makeSession(
        profile: DictationProfile,
        apiKey: String,
        hints: TranscriptionHints
    ) -> any TranscriptionSession {
        switch self {
        case .openAIRealtime:
            RealtimeTranscriptionSession(
                apiKey: apiKey,
                model: profile.realtimeModel,
                language: profile.language,
                delay: profile.realtimeDelay,
                keywords: hints.keyterms
            )
        case .deepgram:
            DeepgramTranscriptionSession(
                apiKey: apiKey,
                model: profile.deepgramModel,
                language: profile.language,
                keyterms: hints.keyterms
            )
        case .elevenLabs:
            ElevenLabsTranscriptionSession(
                apiKey: apiKey,
                model: profile.elevenLabsModel,
                language: profile.language,
                hints: hints
            )
        case .openRouter:
            OpenRouterTranscriptionSession(
                apiKey: apiKey,
                model: profile.openRouterModel,
                language: profile.language
            )
        case .appleOnDevice:
            AppleTranscriptionSession(language: profile.language, contextualStrings: hints.keyterms)
        }
    }
}

extension DictationProfile {
    /// The session for one dictation. When on-screen terms are wanted and
    /// the window is being read, the real session opens once they are in.
    func makeTranscriptionSession(
        apiKey: String,
        screenText: Task<String?, Never>?
    ) -> any TranscriptionSession {
        let backend = transcriptionBackend
        guard wantsScreenTerms, let screenText else {
            return backend.makeSession(profile: self, apiKey: apiKey, hints: transcriptionHints())
        }
        return DeferredTranscriptionSession(screenText: screenText) { screenTerms in
            backend.makeSession(profile: self, apiKey: apiKey, hints: transcriptionHints(screenTerms: screenTerms))
        }
    }
}
