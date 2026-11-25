import Foundation
import os

/// LLM cleanup pass over the raw transcript, ported from the prototype
/// (duper-disper src/refinement/mod.rs). The prompt's anti-hallucination
/// rules and identifier-casing behavior are the proven part — change with
/// care. Falls back to the raw transcript on refusal-style output; callers
/// fall back on thrown errors.
struct Refiner {
    enum RefinerError: LocalizedError {
        case badResponse(Int, String)
        case emptyResponse
        case noEndpoint

        var errorDescription: String? {
            switch self {
            case .badResponse(let status, let body):
                "Refinement API error (\(status)): \(body.prefix(200))"
            case .emptyResponse:
                "Refinement returned no choices."
            case .noEndpoint:
                "The selected provider has no HTTP endpoint."
            }
        }
    }

    /// What to tell the user when refinement failed in a way that repeats on
    /// every dictation until they act (bad key, unavailable model). Nil for
    /// timeouts and server errors — the next try may succeed, so those stay
    /// silent and the raw transcript is inserted as usual.
    static func failureNotice(for error: Error, provider: RefinementProvider) -> String? {
        guard case RefinerError.badResponse(let status, _) = error else { return nil }
        switch status {
        case 401:
            return "Polish skipped: \(provider.label) rejected the API key"
        case 403, 404:
            return "Polish skipped: \(provider.label) can't use this model; check Settings"
        default:
            return nil
        }
    }

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "refine")
    private static let timeout: TimeInterval = 12

    private let appleRefiner = AppleRefiner()

    /// Establishes the TLS connection (cloud) or loads model resources
    /// (on-device) while the user is still speaking, so none of that cost
    /// lands inside the visible "Polishing…" window. Fire-and-forget.
    func prewarm(provider: RefinementProvider) {
        if provider == .appleOnDevice {
            Task { await appleRefiner.prewarm() }
            return
        }
        guard let endpoint = provider.endpoint, let host = endpoint.host,
              let url = URL(string: "https://\(host)/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        Task {
            // Response content is irrelevant — the pooled connection is the point.
            _ = try? await URLSession.shared.data(for: request)
            Self.log.debug("prewarmed \(host, privacy: .public)")
        }
    }

    func refine(
        transcript: String,
        context: FocusContext,
        profile: DictationProfile,
        apiKey: String
    ) async throws -> String {
        let provider = profile.refinementProvider
        let model = profile.refinementModel
        let strength = profile.refinementStrength
        // Screen text is garnish, never worth crowding out the transcript:
        // the on-device model has a hard 4096-token context window (measured),
        // and cloud calls shouldn't balloon on a text-dense window either.
        var context = context
        let screenTextCap = provider == .appleOnDevice ? 1_200 : 4_000
        if context.screenText.count > screenTextCap {
            context.screenText = String(context.screenText.prefix(screenTextCap))
        }

        let prompt = Self.buildPrompt(
            transcript: transcript, context: context, language: profile.language,
            strength: strength, tone: profile.rewriteTone
        )

        if provider == .appleOnDevice {
            Self.log.notice("refining chars=\(transcript.count) provider=apple context=\(context.hasSurroundingText)")
            let refined = try await appleRefiner.refine(
                system: prompt.system, user: prompt.user, fallback: transcript
            )
            return Self.acceptingRefinement(refined, raw: transcript, strength: strength)
        }

        guard let endpoint = provider.endpoint else {
            throw RefinerError.noEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .anthropic {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try Self.requestBody(
            provider: provider, model: model, system: prompt.system, user: prompt.user
        )

        Self.log.notice(
            "refining chars=\(transcript.count) provider=\(provider.rawValue, privacy: .public) model=\(model, privacy: .public)"
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(decoding: data, as: UTF8.self)
            Self.log.error("refine failed status=\(status)")
            throw RefinerError.badResponse(status, body)
        }

        guard let content = Self.responseText(data, provider: provider) else {
            throw RefinerError.emptyResponse
        }

        let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.acceptingRefinement(refined, raw: transcript, strength: strength)
    }

    /// Final quality gate on any provider's output: refusals, emptiness,
    /// truncation, and translation all mean the raw transcript is the safer
    /// result. A long dictation must never come back as just its last
    /// phrase, and a mixed-language dictation must never come back unified
    /// into one language.
    /// Whichever text wins also loses its dashes: the speech engine writes
    /// them as well as the model.
    static func acceptingRefinement(_ refined: String, raw: String, strength: RefinementStrength = .light) -> String {
        removingDashes(chosenText(refined, raw: raw, strength: strength))
    }

    private static func chosenText(_ refined: String, raw: String, strength: RefinementStrength) -> String {
        if refined.isEmpty || isRefusal(refined) {
            log.warning("refine returned refusal/empty; using raw transcript")
            return raw
        }
        if looksTruncated(refined: refined, raw: raw, strength: strength) {
            log.warning("refine output looks truncated (\(refined.count)/\(raw.count) chars); using raw transcript")
            return raw
        }
        if looksTranslated(refined: refined, raw: raw) {
            log.warning("refine output dropped a script present in the raw transcript (translation); using raw transcript")
            return raw
        }
        log.notice("refined chars=\(refined.count)")
        return refined
    }

    /// Em and en dashes used as punctuation read as AI-written, and models
    /// keep them on long dictations whatever the prompt says (measured: an
    /// em dash from the speech engine survived 4 of 4 gpt-5-mini runs). A
    /// dash between two digits is a range and becomes a hyphen; every other
    /// one becomes a comma, or disappears next to other punctuation or at a
    /// line's edge. Internal for tests.
    static func removingDashes(_ text: String) -> String {
        guard text.contains(where: { $0 == "\u{2014}" || $0 == "\u{2013}" }) else { return text }
        var result = text.replacingOccurrences(of: #"(?<=\d)[–—](?=\d)"#, with: "-", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[ \t]*[–—]+[ \t]*"#, with: ", ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^, |, $"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"([.,;:!?…]), "#, with: "$1 ", options: .regularExpression)
        result = result.replacingOccurrences(of: #", (?=[.,;:!?…])"#, with: "", options: .regularExpression)
        return result
    }

    /// Deterministic translation detector: prompt rules ask models to
    /// preserve languages, but small models drift on long inputs. Compare
    /// per-script letter shares — any script that carries a meaningful part
    /// of the raw transcript must survive into the refined text.
    static func looksTranslated(refined: String, raw: String) -> Bool {
        let rawShares = scriptShares(of: raw)
        guard rawShares.totalLetters >= 24 else { return false }
        let refinedShares = scriptShares(of: refined)

        for (script, rawShare) in rawShares.shares {
            guard rawShare >= 0.12,
                  Double(rawShares.totalLetters) * rawShare >= 12 else { continue }
            let refinedShare = refinedShares.shares[script] ?? 0
            if refinedShare < rawShare * 0.35 {
                return true
            }
        }
        return false
    }

    enum Script: Hashable {
        case latin, cyrillic, greek, arabic, hebrew, cjk, hangul, devanagari, other
    }

    /// Letter counts by writing system; digits, punctuation, and whitespace
    /// are ignored. Internal for tests.
    static func scriptShares(of text: String) -> (shares: [Script: Double], totalLetters: Int) {
        var counts: [Script: Int] = [:]
        var total = 0

        for scalar in text.unicodeScalars {
            guard scalar.properties.isAlphabetic else { continue }
            let script: Script
            switch scalar.value {
            case 0x0041...0x024F, 0x1E00...0x1EFF: script = .latin
            case 0x0400...0x052F: script = .cyrillic
            case 0x0370...0x03FF: script = .greek
            case 0x0600...0x06FF, 0x0750...0x077F: script = .arabic
            case 0x0590...0x05FF: script = .hebrew
            case 0x4E00...0x9FFF, 0x3040...0x30FF, 0x3400...0x4DBF: script = .cjk
            case 0xAC00...0xD7AF, 0x1100...0x11FF: script = .hangul
            case 0x0900...0x097F: script = .devanagari
            default: script = .other
            }
            counts[script, default: 0] += 1
            total += 1
        }

        guard total > 0 else { return ([:], 0) }
        return (counts.mapValues { Double($0) / Double(total) }, total)
    }

    /// Cleanup legitimately shortens text (fillers, repairs), but a long
    /// transcript collapsing past ~half its size means the model lost the
    /// text, not polished it. Short inputs are exempt — "um, yeah, okay" →
    /// "Okay." is a valid 4x shrink. A rewrite may condense a rambling
    /// dictation much further, so it only fails below a quarter.
    static func looksTruncated(refined: String, raw: String, strength: RefinementStrength = .light) -> Bool {
        guard raw.count >= 160 else { return false }
        let floor = strength == .rewrite ? 0.25 : 0.45
        return Double(refined.count) < Double(raw.count) * floor
    }

    // MARK: Pure builders (tested)

    /// The rules and the data as two channels: `system` carries the stable
    /// instructions, `user` carries the fenced transcript and its context.
    struct RefinerPrompt: Equatable {
        let system: String
        let user: String
    }

    static func buildPrompt(
        transcript: String,
        context: FocusContext,
        language: String,
        strength: RefinementStrength = .light,
        tone: RewriteTone = .natural
    ) -> RefinerPrompt {
        // Segment-preserving by design: a singular "write in THE language"
        // framing makes models normalize mixed-language dictations into one
        // language (translating the minority segments). Never imply there is
        // exactly one language.
        // swiftlint:disable line_length
        let languageRule: String
        if let name = DictationLanguages.englishName(for: language) {
            languageRule = """
            - The dictation is primarily \(name); keep it in \(name) where the speaker used \(name). If the speaker switches to another language for a word, phrase, or sentence, keep that part in its original language, exactly where the switch happened. NEVER translate any part into another language. Fix grammar and punctuation within each language separately.
            """
        } else {
            languageRule = """
            - The dictation may contain several languages. Write every part in the language the speaker used at that point, preserving mid-dictation switches exactly where they happened. NEVER translate any part, and never unify the text into a single language. Fix grammar and punctuation within each language separately.
              Example: input "so basically мы хотим сделать это правильно okay", output "So basically, мы хотим сделать это правильно. Okay." (the Russian stays Russian, the English stays English.)
            """
        }
        // swiftlint:enable line_length
        return buildPromptBody(
            transcript: transcript, context: context, languageRule: languageRule,
            strengthRule: strengthRule(strength, tone: tone)
        )
    }

    private static func buildPromptBody(
        transcript: String, context: FocusContext, languageRule: String, strengthRule: String
    ) -> RefinerPrompt {
        var surroundingSection = ""
        if context.hasSurroundingText {
            var parts: [String] = []
            if !context.textBeforeCursor.isEmpty {
                parts.append("Text before the cursor:\n\(context.textBeforeCursor)")
            }
            if !context.selectedText.isEmpty {
                parts.append("Currently selected text (will be replaced):\n\(context.selectedText)")
            }
            if !context.textAfterCursor.isEmpty {
                parts.append("Text after the cursor:\n\(context.textAfterCursor)")
            }
            surroundingSection = "Surrounding text (visible near cursor):\n" + parts.joined(separator: "\n") + "\n"
        }

        // Same contract as the surrounding text: spelling/casing authority
        // only, never a source of new words. OCR provenance is stated so the
        // model treats mangled fragments as recognition noise, not content.
        var screenSection = ""
        if !context.screenVocabulary.isEmpty {
            screenSection = "Exact spellings visible in the active window (use only for terms the speaker said):\n"
                + context.screenVocabulary.joined(separator: ", ") + "\n"
        } else if !context.screenText.isEmpty {
            screenSection = "Text recognized on screen in the active window (may contain OCR errors; use only to match spelling/casing):\n"
                + context.screenText + "\n"
        }

        let system = Self.systemTemplate
            .replacingOccurrences(of: "{strength_rule}", with: strengthRule)
            .replacingOccurrences(of: "{language_rule}", with: languageRule)
        let user = Self.userTemplate
            .replacingOccurrences(of: "{app_name}", with: context.appName)
            .replacingOccurrences(of: "{window_title}", with: context.windowTitle)
            .replacingOccurrences(of: "{surrounding_text_section}", with: surroundingSection)
            .replacingOccurrences(of: "{screen_context_section}", with: screenSection)
            .replacingOccurrences(of: "{transcript}", with: transcript)
        return RefinerPrompt(system: system, user: user)
    }

    static func requestBody(provider: RefinementProvider, model: String, system: String, user: String) throws -> Data {
        if provider == .anthropic {
            return try anthropicRequestBody(model: model, system: system, user: user)
        }
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]

        switch provider {
        case .openAI:
            // GPT-5-family models are reasoning models; without this they
            // burn seconds "thinking" before a one-sentence cleanup.
            payload["reasoning_effort"] = "minimal"
            payload["max_completion_tokens"] = 1500
        case .groq, .cerebras:
            // Deterministic decoding: cleanup must not paraphrase or vary run
            // to run, so no sampling temperature.
            payload["temperature"] = 0
            payload["max_tokens"] = 1500
            // gpt-oss reasons before answering; low effort keeps a one-line
            // cleanup fast. Other models on these providers reject the param.
            if model.contains("gpt-oss") {
                payload["reasoning_effort"] = "low"
            }
        case .anthropic, .appleOnDevice:
            break
        }

        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Meta-commentary means the model ignored the rules — the raw transcript
    /// is safer than its output.
    ///
    /// The hard problem is that speakers dictate the same words a refusal uses
    /// ("Sorry I'm late", "I can't make it tonight", "the project is
    /// incomplete"). Matching those as substrings — the old behavior —
    /// silently discarded valid cleanup. So detection is two-tier:
    ///   - `metaPhrases`: phrases that essentially only occur when the model
    ///     narrates the transcript or itself; safe to match anywhere.
    ///   - a generic refusal must BOTH open with an apology/inability AND
    ///     reference declining the task. Requiring both lets ordinary
    ///     dictations that merely start with "Sorry" or "I can't" through.
    static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()

        let metaPhrases = [
            "the transcription", "the transcript", "as an ai", "i'm an ai",
            "i am an ai", "language model", "not enough context",
            "unintelligible", "no transcript", "empty transcript",
        ]
        if metaPhrases.contains(where: { lower.contains($0) }) { return true }

        let opensWithRefusal = [
            "i'm sorry", "i am sorry", "sorry,", "i apologize",
            "i cannot", "i can't", "i'm unable", "i am unable", "unfortunately",
        ].contains { lower.hasPrefix($0) }
        guard opensWithRefusal else { return false }

        let refusalObject = [
            "help with", "assist", "process", "comply", "fulfill",
            "that request", "your request", "with that",
        ]
        return refusalObject.contains { lower.contains($0) }
    }
}
