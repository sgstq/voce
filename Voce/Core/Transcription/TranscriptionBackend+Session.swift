import Foundation

extension TranscriptionBackend {
    /// Builds a fresh streaming session for this backend. `apiKey` is
    /// ignored by backends that need none.
    func makeSession(config: AppConfig, apiKey: String) -> any TranscriptionSession {
        switch self {
        case .openAIRealtime:
            RealtimeTranscriptionSession(
                apiKey: apiKey,
                model: config.realtimeModel,
                language: config.language,
                delay: config.realtimeDelay
            )
        case .deepgram:
            DeepgramTranscriptionSession(
                apiKey: apiKey,
                model: config.deepgramModel,
                language: config.language
            )
        case .appleOnDevice:
            AppleTranscriptionSession(language: config.language)
        }
    }
}
