import Foundation

/// One push-to-talk setup: the keys that start it and everything that shapes
/// the dictation they produce. Every profile's keys work at the same time.
/// API keys are not part of a profile: there is one per provider, in the
/// Keychain, shared by every profile that uses that provider.
struct DictationProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    /// Off keeps the profile and its keys but stops them from dictating.
    var isEnabled: Bool
    /// Nil until the user records keys for a new profile; it can't dictate until then.
    var hotkey: HotkeySpec?
    var language: String
    var transcriptionBackend: TranscriptionBackend
    var realtimeModel: String
    var realtimeDelay: RealtimeDelay
    var deepgramModel: String
    var openRouterModel: String
    var refinementEnabled: Bool
    var refinementProvider: RefinementProvider
    var refinementModel: String
    var captureContext: Bool
    var screenContext: ScreenContextMode

    /// The profile a pre-profiles config becomes. A fixed id keeps it stable
    /// across launches until the config is next saved.
    static let migratedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isEnabled: Bool = true,
        hotkey: HotkeySpec? = .defaultPushToTalk,
        language: String = "en",
        transcriptionBackend: TranscriptionBackend = .openAIRealtime,
        realtimeModel: String = "gpt-realtime-whisper",
        realtimeDelay: RealtimeDelay = .low,
        deepgramModel: String = "nova-3",
        openRouterModel: String = "microsoft/mai-transcribe-2",
        refinementEnabled: Bool = true,
        refinementProvider: RefinementProvider = .openAI,
        refinementModel: String = "gpt-5-mini",
        captureContext: Bool = true,
        screenContext: ScreenContextMode = .off
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.hotkey = hotkey
        self.language = language
        self.transcriptionBackend = transcriptionBackend
        self.realtimeModel = realtimeModel
        self.realtimeDelay = realtimeDelay
        self.deepgramModel = deepgramModel
        self.openRouterModel = openRouterModel
        self.refinementEnabled = refinementEnabled
        self.refinementProvider = refinementProvider
        self.refinementModel = refinementModel
        self.captureContext = captureContext
        self.screenContext = screenContext
    }

    /// The name to show, or nil when the user left it blank.
    var displayName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, hotkey, language, transcriptionBackend
        case realtimeModel, realtimeDelay, deepgramModel, openRouterModel
        case refinementEnabled, refinementProvider, refinementModel
        case captureContext, screenContext
    }

    /// Tolerant decoding: every missing key falls back to its default, so
    /// configs written by older versions keep loading as fields are added.
    /// The keys match the pre-profiles top-level config, which decodes
    /// through here too.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DictationProfile()
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? defaults.name
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        self.hotkey = try container.decodeIfPresent(HotkeySpec.self, forKey: .hotkey)
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        self.transcriptionBackend = try container.decodeIfPresent(TranscriptionBackend.self, forKey: .transcriptionBackend) ?? defaults.transcriptionBackend
        self.realtimeModel = try container.decodeIfPresent(String.self, forKey: .realtimeModel) ?? defaults.realtimeModel
        self.realtimeDelay = try container.decodeIfPresent(RealtimeDelay.self, forKey: .realtimeDelay) ?? defaults.realtimeDelay
        self.deepgramModel = try container.decodeIfPresent(String.self, forKey: .deepgramModel) ?? defaults.deepgramModel
        self.openRouterModel = try container.decodeIfPresent(String.self, forKey: .openRouterModel) ?? defaults.openRouterModel
        self.refinementEnabled = try container.decodeIfPresent(Bool.self, forKey: .refinementEnabled) ?? defaults.refinementEnabled
        self.refinementProvider = try container.decodeIfPresent(RefinementProvider.self, forKey: .refinementProvider) ?? defaults.refinementProvider
        let refinementModel = try container.decodeIfPresent(String.self, forKey: .refinementModel) ?? defaults.refinementModel
        self.refinementModel = refinementProvider.replacement(forRetiredModel: refinementModel) ?? refinementModel
        self.captureContext = try container.decodeIfPresent(Bool.self, forKey: .captureContext) ?? defaults.captureContext
        self.screenContext = try container.decodeIfPresent(ScreenContextMode.self, forKey: .screenContext) ?? defaults.screenContext
    }
}
