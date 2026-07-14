import Foundation

struct AppConfig: Codable, Equatable {
    var hotkey: HotkeySpec
    var language: String
    var insertionMode: InsertionMode
    var transcriptionBackend: TranscriptionBackend
    var realtimeModel: String
    var realtimeDelay: RealtimeDelay
    var deepgramModel: String
    var refinementEnabled: Bool
    var refinementProvider: RefinementProvider
    var refinementModel: String
    var theme: AppTheme
    var accent: AccentColor
    var captureContext: Bool
    var captureScreenshots: Bool

    init(
        hotkey: HotkeySpec = .defaultPushToTalk,
        language: String = "en",
        insertionMode: InsertionMode = .auto,
        transcriptionBackend: TranscriptionBackend = .openAIRealtime,
        realtimeModel: String = "gpt-realtime-whisper",
        realtimeDelay: RealtimeDelay = .low,
        deepgramModel: String = "nova-3",
        refinementEnabled: Bool = true,
        refinementProvider: RefinementProvider = .openAI,
        refinementModel: String = "gpt-5-mini",
        theme: AppTheme = .system,
        accent: AccentColor = .violet,
        captureContext: Bool = true,
        captureScreenshots: Bool = false
    ) {
        self.hotkey = hotkey
        self.language = language
        self.insertionMode = insertionMode
        self.transcriptionBackend = transcriptionBackend
        self.realtimeModel = realtimeModel
        self.realtimeDelay = realtimeDelay
        self.deepgramModel = deepgramModel
        self.refinementEnabled = refinementEnabled
        self.refinementProvider = refinementProvider
        self.refinementModel = refinementModel
        self.theme = theme
        self.accent = accent
        self.captureContext = captureContext
        self.captureScreenshots = captureScreenshots
    }

    private enum CodingKeys: String, CodingKey {
        case hotkey, language, insertionMode, transcriptionBackend
        case realtimeModel, realtimeDelay, deepgramModel, refinementEnabled, refinementProvider, refinementModel
        case theme, accent, captureContext, captureScreenshots
    }

    /// Tolerant decoding: every missing key falls back to its default, so
    /// configs written by older versions keep loading as fields are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        self.hotkey = try container.decodeIfPresent(HotkeySpec.self, forKey: .hotkey) ?? defaults.hotkey
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        self.insertionMode = try container.decodeIfPresent(InsertionMode.self, forKey: .insertionMode) ?? defaults.insertionMode
        self.transcriptionBackend = try container.decodeIfPresent(TranscriptionBackend.self, forKey: .transcriptionBackend) ?? defaults.transcriptionBackend
        self.realtimeModel = try container.decodeIfPresent(String.self, forKey: .realtimeModel) ?? defaults.realtimeModel
        self.realtimeDelay = try container.decodeIfPresent(RealtimeDelay.self, forKey: .realtimeDelay) ?? defaults.realtimeDelay
        self.deepgramModel = try container.decodeIfPresent(String.self, forKey: .deepgramModel) ?? defaults.deepgramModel
        self.refinementEnabled = try container.decodeIfPresent(Bool.self, forKey: .refinementEnabled) ?? defaults.refinementEnabled
        self.refinementProvider = try container.decodeIfPresent(RefinementProvider.self, forKey: .refinementProvider) ?? defaults.refinementProvider
        self.refinementModel = try container.decodeIfPresent(String.self, forKey: .refinementModel) ?? defaults.refinementModel
        self.theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        self.accent = try container.decodeIfPresent(AccentColor.self, forKey: .accent) ?? defaults.accent
        self.captureContext = try container.decodeIfPresent(Bool.self, forKey: .captureContext) ?? defaults.captureContext
        self.captureScreenshots = try container.decodeIfPresent(Bool.self, forKey: .captureScreenshots) ?? defaults.captureScreenshots
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
    case appleOnDevice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAIRealtime:
            "OpenAI Realtime"
        case .deepgram:
            "Deepgram"
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
        case .appleOnDevice:
            nil
        }
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
    case violet
    case blue
    case green
    case orange

    var id: String { rawValue }

    var label: String {
        switch self {
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
