import Foundation

/// Provider options that shape one dictation's transcript, resolved from the
/// profile and the backend's capabilities. Empty `keyterms` means none are
/// sent, so a provider that charges for them charges nothing.
struct TranscriptionHints: Equatable, Sendable {
    var keyterms: [String] = []
    var removeFillerWords = false
    var multilingual = false
}

/// What a backend and model accept beyond audio, with the documented limits
/// and price premiums. Settings shows only the options listed here.
struct TranscriptionCapabilities: Equatable {
    struct Keyterms: Equatable {
        let maxCount: Int
        let maxTotalCharacters: Int
        /// Documented surcharge on the transcription price while terms are
        /// sent, nil when the provider lists none.
        let premiumPercent: Int?
    }

    var keyterms: Keyterms?
    var removesFillerWords = false
    var multilingual = false

    var isEmpty: Bool {
        keyterms == nil && !removesFillerWords && !multilingual
    }
}

extension TranscriptionBackend {
    /// Limits and prices verified 2026-11-25 against each provider's docs:
    /// ElevenLabs realtime keyterms (50 terms, 1,000 characters, +20%);
    /// Deepgram Nova-3 keyterm ($0.0013 on $0.0077 per streamed minute,
    /// about 17%; its 500-token cap is kept under by the character limit);
    /// OpenAI `keywords` on gpt-live-transcribe and gpt-transcribe only,
    /// billed per audio minute with no listed surcharge; Apple's
    /// SpeechAnalyzer contextual strings, on-device and free. OpenRouter is
    /// left out: no listed STT model reports keyterm support.
    func capabilities(model: String) -> TranscriptionCapabilities {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .elevenLabs:
            return TranscriptionCapabilities(
                keyterms: .init(maxCount: 50, maxTotalCharacters: 1_000, premiumPercent: 20),
                removesFillerWords: true,
                multilingual: model.hasPrefix("scribe_v3")
            )
        case .deepgram:
            guard model.hasPrefix("nova-3") else { return TranscriptionCapabilities() }
            return TranscriptionCapabilities(
                keyterms: .init(maxCount: 100, maxTotalCharacters: 1_000, premiumPercent: 17)
            )
        case .openAIRealtime:
            guard model.hasPrefix("gpt-live-transcribe") || model.hasPrefix("gpt-transcribe") else {
                return TranscriptionCapabilities()
            }
            return TranscriptionCapabilities(
                keyterms: .init(maxCount: 50, maxTotalCharacters: 1_000, premiumPercent: nil)
            )
        case .appleOnDevice:
            return TranscriptionCapabilities(
                keyterms: .init(maxCount: 100, maxTotalCharacters: 2_000, premiumPercent: nil)
            )
        case .openRouter:
            return TranscriptionCapabilities()
        }
    }
}

extension DictationProfile {
    /// The model field the selected backend reads.
    var transcriptionModel: String {
        switch transcriptionBackend {
        case .openAIRealtime: realtimeModel
        case .deepgram: deepgramModel
        case .elevenLabs: elevenLabsModel
        case .openRouter: openRouterModel
        case .appleOnDevice: ""
        }
    }

    var transcriptionCapabilities: TranscriptionCapabilities {
        transcriptionBackend.capabilities(model: transcriptionModel)
    }

    /// Typed terms, one per line or comma separated, trimmed.
    var vocabularyTerms: [String] {
        vocabulary
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// True when this dictation should read the window before transcribing.
    var wantsScreenTerms: Bool {
        vocabularyHintsEnabled && screenVocabularyHints && transcriptionCapabilities.keyterms != nil
    }

    /// The options to send for one dictation. Typed terms come first, then
    /// `screenTerms`; duplicates and terms past the provider's count or
    /// character limit are dropped so the request is never rejected.
    func transcriptionHints(screenTerms: [String] = []) -> TranscriptionHints {
        let capabilities = transcriptionCapabilities
        var hints = TranscriptionHints(
            removeFillerWords: capabilities.removesFillerWords && removeFillerWords,
            multilingual: capabilities.multilingual && multilingualMode
        )
        guard vocabularyHintsEnabled, let limits = capabilities.keyterms else { return hints }

        let candidates = vocabularyTerms + (screenVocabularyHints ? screenTerms : [])
        var seen = Set<String>()
        var characters = 0
        for term in candidates {
            // OpenAI rejects a session whose keywords contain angle brackets.
            guard !term.contains("<"), !term.contains(">"), seen.insert(term).inserted else { continue }
            guard hints.keyterms.count < limits.maxCount else { break }
            guard characters + term.count <= limits.maxTotalCharacters else { continue }
            characters += term.count
            hints.keyterms.append(term)
        }
        return hints
    }
}
