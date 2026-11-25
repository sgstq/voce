import AppKit
import Foundation

/// Speech engines in verbatim mode write a word the speaker broke off with
/// a trailing hyphen ("ent- Anthropic", "so we- Can"), and a dictation that
/// ends mid-word ends on one. A hyphen with a space or the end after it is
/// never part of a word, so these are cleaned before Polish sees the text
/// and when Polish is off: a real word just loses its hyphen, and the next
/// word its stray capital; a fragment that is not a word goes away.
enum CutOffWords {
    /// A run of letters ending in a hyphen that a space or the end follows.
    private static let pattern = #"(?<![\p{L}\p{N}\-‐])(\p{L}+)[\-‐](?=\s|$)\s*"#

    @MainActor
    static func removed(from text: String, language: String) -> String {
        removed(from: text) { isWord($0, language: language) }
    }

    /// Internal for tests, which pass their own dictionary.
    static func removed(from text: String, isWord: (String) -> Bool) -> String {
        var result = text as NSString
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: result.length)) ?? []
        // Back to front, so earlier ranges stay valid.
        for match in matches.reversed() {
            let word = match.range(at: 1)
            let fragment = result.substring(with: word)
            if isWord(fragment) {
                // Only the hyphen goes; the spacing after it stays as spoken.
                result = result.replacingCharacters(in: NSRange(location: NSMaxRange(word), length: 1), with: "") as NSString
                let nextStart = NSMaxRange(match.range) - 1
                if nextStart < result.length { result = lowercasingWord(at: nextStart, in: result, isWord: isWord) }
            } else {
                result = result.replacingCharacters(in: match.range, with: "") as NSString
            }
        }
        // A lone hyphen at the very end ("and then -").
        let cleaned = (result as String).replacingOccurrences(of: #"\s+[\-‐]\s*$"#, with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// The engine starts the words after a break with a capital as if a new
    /// sentence began. Acronyms, "I", and words only known capitalized
    /// (names) keep theirs.
    private static func lowercasingWord(at location: Int, in text: NSString, isWord: (String) -> Bool) -> NSString {
        let range = text.rangeOfCharacter(from: CharacterSet.letters.inverted, options: [], range: NSRange(location: location, length: text.length - location))
        let end = range.location == NSNotFound ? text.length : range.location
        guard end > location else { return text }
        let word = text.substring(with: NSRange(location: location, length: end - location))
        guard word.count > 1, let first = word.first, first.isUppercase,
              word.dropFirst().allSatisfy({ !$0.isUppercase }) else { return text }
        let lowered = word.prefix(1).lowercased() + word.dropFirst()
        guard isWord(lowered) else { return text }
        return text.replacingCharacters(in: NSRange(location: location, length: end - location), with: lowered) as NSString
    }

    /// The Mac's own dictionary for the dictation language, or the user's
    /// language choice when it is automatic or has no dictionary.
    @MainActor
    private static func isWord(_ candidate: String, language: String) -> Bool {
        let checker = NSSpellChecker.shared
        let code = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dictionary = checker.availableLanguages.first { $0.lowercased() == code || $0.lowercased().hasPrefix(code + "_") }
        let miss = checker.checkSpelling(
            of: candidate, startingAt: 0,
            language: DictationLanguages.isAutomatic(language) ? nil : dictionary,
            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        return miss.location == NSNotFound
    }
}
