import Foundation

/// Everything Voce remembers outside the Keychain: the dictation profiles
/// and the settings every profile shares.
struct AppConfig: Codable, Equatable {
    /// Never empty. The first profile is the one onboarding sets up.
    var profiles: [DictationProfile]
    var insertionMode: InsertionMode
    var theme: AppTheme
    var accent: AccentColor
    var showLiveTranscript: Bool

    init(
        profiles: [DictationProfile] = [DictationProfile()],
        insertionMode: InsertionMode = .auto,
        theme: AppTheme = .system,
        accent: AccentColor = .system,
        showLiveTranscript: Bool = false
    ) {
        self.profiles = profiles.isEmpty ? [DictationProfile()] : profiles
        self.insertionMode = insertionMode
        self.theme = theme
        self.accent = accent
        self.showLiveTranscript = showLiveTranscript
    }

    var primaryProfile: DictationProfile {
        get { profiles[0] }
        set { profiles[0] = newValue }
    }

    func profile(id: UUID) -> DictationProfile? {
        profiles.first { $0.id == id }
    }

    /// Profiles that dictate when their keys are held: switched on, with keys.
    var activeProfiles: [DictationProfile] {
        profiles.filter { $0.isEnabled && $0.hotkey != nil }
    }

    /// What the hotkey monitor listens for.
    var hotkeyBindings: [HotkeyBinding] {
        activeProfiles.compactMap { profile in
            profile.hotkey.map { HotkeyBinding(id: profile.id, keys: $0.keys) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case profiles, insertionMode, theme, accent, showLiveTranscript
    }

    /// Tolerant decoding: every missing key falls back to its default, so
    /// configs written by older versions keep loading as fields are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        if let profiles = try container.decodeIfPresent([DictationProfile].self, forKey: .profiles), !profiles.isEmpty {
            self.profiles = profiles
        } else {
            // Before profiles, one profile's settings sat at the top level
            // under the same keys; they become profile 1.
            var migrated = try DictationProfile(from: decoder)
            migrated.id = DictationProfile.migratedID
            migrated.hotkey = migrated.hotkey ?? .defaultPushToTalk
            self.profiles = [migrated]
        }
        self.insertionMode = try container.decodeIfPresent(InsertionMode.self, forKey: .insertionMode) ?? defaults.insertionMode
        self.theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        self.accent = try container.decodeIfPresent(AccentColor.self, forKey: .accent) ?? defaults.accent
        self.showLiveTranscript = try container.decodeIfPresent(Bool.self, forKey: .showLiveTranscript) ?? defaults.showLiveTranscript
    }
}

/// How much of the active window may inform refinement. The privacy axis is
/// how much screen content leaves the Mac: nothing, ~25 distilled spellings,
/// or the recognized window text. The window image itself never leaves —
/// OCR runs on-device either way.
enum ScreenContextMode: String, Codable, CaseIterable, Identifiable {
    case off
    case termsOnly
    case fullText

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:
            "Off"
        case .termsOnly:
            "Terms only"
        case .fullText:
            "Full window text"
        }
    }

    var caption: String {
        switch self {
        case .off:
            "The screen is never read."
        case .termsOnly:
            "The active window is read and distilled on this Mac into up to 25 exact spellings; only those terms join the refinement prompt."
        case .fullText:
            "The recognized window text joins the refinement prompt — strongest corrections, but on-screen content is sent to your refinement provider."
        }
    }
}

enum InsertionMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case accessibility
    case keystrokes
    case clipboardFallback

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:
            "Auto"
        case .accessibility:
            "Accessibility"
        case .keystrokes:
            "Keystrokes"
        case .clipboardFallback:
            "Clipboard fallback"
        }
    }
}

enum TranscriptionBackend: String, Codable, CaseIterable, Identifiable {
    case openAIRealtime
    case deepgram
    case openRouter
    case appleOnDevice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAIRealtime:
            "OpenAI Realtime"
        case .deepgram:
            "Deepgram"
        case .openRouter:
            "OpenRouter"
        case .appleOnDevice:
            "Apple on-device"
        }
    }

    /// Short provider name for key-related UI ("OpenAI API key").
    var keyLabel: String {
        switch self {
        case .openAIRealtime:
            "OpenAI"
        case .deepgram:
            "Deepgram"
        case .openRouter:
            "OpenRouter"
        case .appleOnDevice:
            "Apple"
        }
    }

    /// Keychain account for the backend's API key, nil when the backend
    /// needs none. OpenAI shares one key between transcription and refinement.
    var keychainAccount: String? {
        switch self {
        case .openAIRealtime:
            "openai-api-key"
        case .deepgram:
            "deepgram-api-key"
        case .openRouter:
            "openrouter-api-key"
        case .appleOnDevice:
            nil
        }
    }

    /// File-based backends upload the whole recording after release, so
    /// finalizing takes longer the longer the user spoke.
    var uploadsOnRelease: Bool {
        self == .openRouter
    }
}

enum RealtimeDelay: String, Codable, CaseIterable, Identifiable {
    case minimal
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal:
            "Minimal"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "X High"
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }
}

enum AccentColor: String, Codable, CaseIterable, Identifiable {
    /// Follows the accent chosen in System Settings.
    case system
    case violet
    case blue
    case green
    case orange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "System"
        case .violet:
            "Violet"
        case .blue:
            "Blue"
        case .green:
            "Green"
        case .orange:
            "Orange"
        }
    }
}
