import Foundation

/// The dictation language is a single setting driving BOTH engines: the
/// realtime transcriber (as the ISO hint, omitted when automatic) and the
/// refiner (as an output-language contract in the prompt).
enum DictationLanguages {
    static let automatic = "auto"

    /// Curated ISO-639-1 codes shown in Settings. Stored config values
    /// outside this list still work — the picker just adds them as an
    /// extra option.
    static let curated: [String] = [
        automatic,
        "en", "ru", "uk", "de", "fr", "es", "it", "pt", "nl", "pl",
        "cs", "fi", "sv", "no", "da", "tr", "ja", "zh", "ko", "ar", "hi",
    ]

    static func isAutomatic(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == automatic
    }

    /// Display name for the picker ("Automatic", "Russian", …).
    static func displayName(for code: String) -> String {
        if isAutomatic(code) { return "Automatic" }
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    /// English name for the refiner prompt (the prompt itself is English).
    static func englishName(for code: String) -> String? {
        guard !isAutomatic(code) else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }

    /// Options for the settings picker, including a non-curated stored value.
    static func pickerOptions(including current: String) -> [String] {
        let normalized = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || curated.contains(normalized) {
            return curated
        }
        return curated + [normalized]
    }
}
