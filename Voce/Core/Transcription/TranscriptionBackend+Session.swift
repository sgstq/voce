import Foundation

extension TranscriptionBackend {
    /// Builds a fresh streaming session for this backend. `apiKey` is
    /// ignored by backends that need none.
    func makeSession(profile: DictationProfile, apiKey: String) -> any TranscriptionSession {
        switch self {
        case .openAIRealtime:
            RealtimeTranscriptionSession(
                apiKey: apiKey,
                model: profile.realtimeModel,
                language: profile.language,
                delay: profile.realtimeDelay
            )
        case .deepgram:
            DeepgramTranscriptionSession(
                apiKey: apiKey,
                model: profile.deepgramModel,
                language: profile.language
            )
        case .openRouter:
            OpenRouterTranscriptionSession(
                apiKey: apiKey,
                model: profile.openRouterModel,
                language: profile.language
            )
        case .appleOnDevice:
            AppleTranscriptionSession(language: profile.language)
        }
    }
}
