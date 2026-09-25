import Foundation

/// Distills raw window text (from OCR) into the short list of exact
/// spellings the refiner may use as spelling authority. Pure structural
/// heuristics — no dictionary, no model — so behavior stays deterministic,
/// testable, and free of the context-window and latency costs an LLM
/// distiller would add.
enum VocabularyDistiller {
    /// Keyword-sized prompts steer best (OpenAI and Deepgram both recommend
    /// short term lists over long context), and a small cap bounds what can
    /// leave the Mac in terms-only mode.
    static let termLimit = 25

    /// Tokens longer than this are OCR artifacts or secrets, never vocabulary.
    private static let maxTokenLength = 60

    /// Identifier-shaped tokens only: camelCase, snake_case, dotted names
    /// (CLAUDE.md, buffer.append), and digit-bearing ids (gpt-4o-transcribe).
    /// Plain Capitalized words are deliberately excluded — without sentence
    /// context "Cerebras" and "The" are indistinguishable, and false positives
    /// would teach the refiner wrong spellings. The full-text mode covers
    /// proper nouns instead.
    static func distill(from text: String, limit: Int = termLimit) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []

        for token in tokens(in: text) {
            guard terms.count < limit else { break }
            guard isIdentifierShaped(token), !looksLikeSecret(token), seen.insert(token).inserted else { continue }
            terms.append(token)
        }
        return terms
    }

    /// Replaces secret-shaped tokens with a placeholder so full-text mode
    /// never ships a visible API key or token to a cloud provider. Heuristics
    /// are magnetically attracted to secrets — a key in a terminal is the
    /// most "unusual token" on screen — so this runs on everything outbound.
    static func redactSecrets(in text: String) -> String {
        var result = ""
        var word = ""

        func flush() {
            guard !word.isEmpty else { return }
            let core = trimPunctuation(word)
            result += looksLikeSecret(core) ? word.replacingOccurrences(of: core, with: "•••") : word
            word = ""
        }

        for character in text {
            if character.isWhitespace || character.isNewline {
                flush()
                result.append(character)
            } else {
                word.append(character)
            }
        }
        flush()
        return result
    }

    /// A token is secret-shaped when it carries a known credential prefix, or
    /// is long AND mixes lower case, upper case, AND digits — the signature
    /// of keys and tokens. Punctuation deliberately doesn't count as a class:
    /// dotted mixed-case identifiers (RealtimeProtocol.swift) are exactly the
    /// vocabulary this feature exists to protect.
    static func looksLikeSecret(_ token: String) -> Bool {
        let secretPrefixes = [
            "sk-", "pk-", "rk-", "ghp_", "gho_", "ghs_", "github_pat_",
            "xoxb-", "xoxp-", "xapp-", "AKIA", "AIza", "eyJ", "-----BEGIN",
        ]
        if secretPrefixes.contains(where: { token.hasPrefix($0) }) { return true }

        guard token.count >= 20 else { return false }
        return token.contains(where: { $0.isLowercase })
            && token.contains(where: { $0.isUppercase })
            && token.contains(where: { $0.isNumber })
    }

    // MARK: Token shape

    private static func tokens(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { trimPunctuation(String($0)) }
            .filter { !$0.isEmpty && $0.count <= maxTokenLength }
    }

    /// Strips the punctuation that clings to tokens in prose and OCR output
    /// ("(RealtimeProtocol.swift)," → "RealtimeProtocol.swift") while keeping
    /// interior structure intact.
    private static func trimPunctuation(_ token: String) -> String {
        let clinging = CharacterSet(charactersIn: "()[]{}<>\"'`“”‘’,;:!?…")
        var trimmed = token.trimmingCharacters(in: clinging)
        // A trailing period is sentence punctuation unless it forms an
        // extension-like tail (CLAUDE.md keeps its dot, "session." loses it).
        while trimmed.hasSuffix(".") {
            trimmed = String(trimmed.dropLast())
        }
        return trimmed
    }

    private static func isIdentifierShaped(_ token: String) -> Bool {
        guard token.count >= 3, token.contains(where: { $0.isLetter }) else { return false }
        // URLs are noise, not vocabulary.
        guard !token.contains("://"), !token.hasPrefix("www.") else { return false }
        // Only identifier-legal interior characters; anything else means the
        // token is prose or OCR debris.
        guard token.allSatisfy({ $0.isLetter || $0.isNumber || "._-/".contains($0) }) else { return false }

        let hasCamelBoundary = zip(token, token.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
        let hasSnake = token.contains("_")
        let hasInteriorDot = token.dropFirst().dropLast().contains(".")
        let hasDigitWithSeparator = token.contains(where: { $0.isNumber })
            && token.contains(where: { "-._".contains($0) })
        return hasCamelBoundary || hasSnake || hasInteriorDot || hasDigitWithSeparator
    }
}
