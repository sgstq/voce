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
        provider: RefinementProvider,
        model: String,
        apiKey: String,
        language: String
    ) async throws -> String {
        let prompt = Self.buildPrompt(transcript: transcript, context: context, language: language)

        if provider == .appleOnDevice {
            Self.log.notice("refining chars=\(transcript.count) provider=apple context=\(context.hasSurroundingText)")
            let refined = try await appleRefiner.refine(prompt: prompt, fallback: transcript)
            return Self.acceptingRefinement(refined, raw: transcript)
        }

        guard let endpoint = provider.endpoint else {
            throw RefinerError.noEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.requestBody(provider: provider, model: model, prompt: prompt)

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

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw RefinerError.emptyResponse
        }

        let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.acceptingRefinement(refined, raw: transcript)
    }

    /// Final quality gate on any provider's output: refusals, emptiness,
    /// truncation, and translation all mean the raw transcript is the safer
    /// result. A long dictation must never come back as just its last
    /// phrase, and a mixed-language dictation must never come back unified
    /// into one language.
    static func acceptingRefinement(_ refined: String, raw: String) -> String {
        if refined.isEmpty || isRefusal(refined) {
            log.warning("refine returned refusal/empty; using raw transcript")
            return raw
        }
        if looksTruncated(refined: refined, raw: raw) {
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
    /// "Okay." is a valid 4x shrink.
    static func looksTruncated(refined: String, raw: String) -> Bool {
        guard raw.count >= 160 else { return false }
        return Double(refined.count) < Double(raw.count) * 0.45
    }

    // MARK: Pure builders (tested)

    static func buildPrompt(transcript: String, context: FocusContext, language: String) -> String {
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
              Example — input: "so basically мы хотим сделать это правильно okay" → output: "So basically, мы хотим сделать это правильно. Okay." (the Russian stays Russian, the English stays English.)
            """
        }
        // swiftlint:enable line_length
        return buildPromptBody(transcript: transcript, context: context, languageRule: languageRule)
    }

    private static func buildPromptBody(transcript: String, context: FocusContext, languageRule: String) -> String {
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

        return Self.promptTemplate
            .replacingOccurrences(of: "{language_rule}", with: languageRule)
            .replacingOccurrences(of: "{app_name}", with: context.appName)
            .replacingOccurrences(of: "{window_title}", with: context.windowTitle)
            .replacingOccurrences(of: "{surrounding_text_section}", with: surroundingSection)
            .replacingOccurrences(of: "{transcript}", with: transcript)
    }

    static func requestBody(provider: RefinementProvider, model: String, prompt: String) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]

        switch provider {
        case .openAI:
            // GPT-5-family models are reasoning models; without this they
            // burn seconds "thinking" before a one-sentence cleanup.
            payload["reasoning_effort"] = "minimal"
            payload["max_completion_tokens"] = 1500
        case .groq, .cerebras:
            payload["temperature"] = 0.3
            payload["max_tokens"] = 1500
        case .appleOnDevice:
            break
        }

        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Ported guard: meta-commentary means the model ignored the rules —
    /// the raw transcript is safer than its output.
    static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let patterns = [
            "sorry", "i can't", "i cannot", "i'm unable",
            "the transcription", "appears to be", "seems to be",
            "truncated", "incomplete", "unintelligible",
            "not enough context", "please provide", "could you",
            "i apologize", "as an ai", "i'm an ai",
        ]
        return patterns.contains { lower.contains($0) }
    }

    // The prompt is prose; its lines stay natural.
    // swiftlint:disable line_length
    static let promptTemplate = """
    You are a text post-processor for a voice transcription tool. You receive raw speech-to-text output and return cleaned text.

    CRITICAL RULES:
    - Output ONLY the cleaned text. Nothing else. No preamble, no apology, no explanation.
    - NEVER say "sorry", "I can't", "the transcription", "truncated", "incomplete", or comment on the input quality.
    - NEVER complete, extend, or finish partial sentences. If the speaker said "Let's" and stopped, output "Let's" — do NOT guess what they meant to say.
    - NEVER use the context (app name, window title, surrounding text) to invent or infer words the speaker did not say.
    - If the input is very short or a fragment, return it as-is with only minor cleanup. If truly unintelligible, return an empty string.
    - Fix grammar, punctuation, and capitalization.
    - Remove filler words (um, uh, like, you know) unless they add meaning.
    - Maintain the speaker's intent and tone exactly.
    - Do NOT add information that wasn't in the original speech.
    - Do NOT wrap output in quotes or markdown.
    {language_rule}
    - Match the writing STYLE of the surrounding text — if the text before the cursor is mid-sentence, continue it (no leading capital, no opening punctuation); if it ends a sentence, start fresh. The surrounding text NEVER changes the output language: even when it is in a different language than the dictation, keep the dictation's language.
    - When the speaker dictates something that matches a variable name, function name, class name, or other code identifier visible in the context, preserve its exact casing and spelling (e.g. "userDefinedCompanyData", "getElementById", "MyAppConfig"). Use the context to pick the correct form — do NOT split camelCase into separate words or "fix" unconventional casing.
    - Technical terms, file names, and code identifiers should be preserved verbatim, not converted to natural language.

    Context (use ONLY to match correct spelling/casing of identifiers and proper nouns — NEVER to invent words):
    Application: {app_name}
    Window title: {window_title}
    {surrounding_text_section}
    Raw transcript:
    {transcript}
    """
    // swiftlint:enable line_length
}
