import XCTest
@testable import Voce

final class AppConfigTests: XCTestCase {
    func testDefaultConfigMatchesPhaseZeroPlan() {
        let config = AppConfig()
        let profile = config.primaryProfile

        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(profile.hotkey, .defaultPushToTalk)
        XCTAssertEqual(profile.hotkey?.displayName, "Right ⌥")
        XCTAssertEqual(profile.language, "en")
        XCTAssertEqual(profile.transcriptionBackend, .openAIRealtime)
        XCTAssertEqual(profile.realtimeModel, "gpt-realtime-whisper")
        XCTAssertEqual(profile.realtimeDelay, .low)
        XCTAssertTrue(profile.refinementEnabled)
        XCTAssertTrue(profile.captureContext)
        XCTAssertEqual(profile.screenContext, .off)
        XCTAssertEqual(config.insertionMode, .auto)
        XCTAssertFalse(config.showLiveTranscript)
        XCTAssertEqual(config.accent, .system)
    }

    func testConfigStoreRoundTripsJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ConfigStore(directory: directory)
        var config = AppConfig()
        config.primaryProfile.hotkey = HotkeySpec(capturedKeyCode: 96) // F5
        config.primaryProfile.realtimeDelay = .medium
        config.primaryProfile.screenContext = .termsOnly
        config.profiles.append(DictationProfile(
            name: "Russian",
            hotkey: HotkeySpec(capturedKeyCodes: [56, 61]), // Right ⌥ + ⇧
            language: "ru",
            transcriptionBackend: .deepgram
        ))
        config.profiles.append(DictationProfile(name: "No keys yet", hotkey: nil))
        config.profiles.append(DictationProfile(name: "Paused", isEnabled: false, hotkey: HotkeySpec(capturedKeyCode: 63)))
        config.insertionMode = .keystrokes
        config.showLiveTranscript = true
        config.accent = .green

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testPreProfilesConfigBecomesProfileOne() throws {
        // A config.json written before profiles: one profile's settings at the top level.
        let json = """
        {
            "hotkey": { "keyCode": 61, "kind": "modifier", "displayName": "Right ⌥" },
            "language": "es",
            "insertionMode": "keystrokes",
            "transcriptionBackend": "deepgram",
            "realtimeDelay": "high",
            "refinementProvider": "groq",
            "refinementModel": "openai/gpt-oss-20b",
            "screenContext": "fullText",
            "showLiveTranscript": true,
            "theme": "dark",
            "accent": "violet"
        }
        """

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.profiles.count, 1)
        let profile = config.primaryProfile
        XCTAssertEqual(profile.id, DictationProfile.migratedID)
        XCTAssertEqual(profile.name, "Default")
        XCTAssertEqual(profile.hotkey, HotkeySpec(keyCodes: [61], displayName: "Right ⌥"))
        XCTAssertEqual(profile.language, "es")
        XCTAssertEqual(profile.transcriptionBackend, .deepgram)
        XCTAssertEqual(profile.realtimeDelay, .high)
        XCTAssertEqual(profile.refinementProvider, .groq)
        XCTAssertEqual(profile.refinementModel, "openai/gpt-oss-20b")
        XCTAssertEqual(profile.screenContext, .fullText)
        // Settings every profile shares stay at the top level.
        XCTAssertEqual(config.insertionMode, .keystrokes)
        XCTAssertTrue(config.showLiveTranscript)
        XCTAssertEqual(config.theme, .dark)
        XCTAssertEqual(config.accent, .violet)
    }

    func testDecodesLegacyConfigWithStringHotkey() throws {
        // A config.json written before the hotkey recorder existed.
        let legacyJSON = """
        {
            "hotkey": "F6",
            "language": "en",
            "insertionMode": "auto",
            "transcriptionBackend": "openAIRealtime",
            "realtimeModel": "gpt-realtime-whisper",
            "realtimeDelay": "low",
            "refinementEnabled": true,
            "theme": "system",
            "accent": "violet",
            "captureContext": true,
            "captureScreenshots": false
        }
        """

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(legacyJSON.utf8))
        let profile = config.primaryProfile
        // A saved F-key is kept; only new installs get Right ⌥.
        XCTAssertEqual(profile.hotkey, HotkeySpec(keyCodes: [97], displayName: "F6"))
        // Fields added after that config was written fall back to defaults;
        // the retired "captureScreenshots" key is ignored harmlessly.
        XCTAssertEqual(profile.refinementModel, "gpt-5-mini")
        XCTAssertEqual(profile.refinementProvider, .openAI)
        XCTAssertEqual(profile.deepgramModel, "nova-3")
        XCTAssertEqual(profile.openRouterModel, "microsoft/mai-transcribe-2")
        XCTAssertEqual(profile.screenContext, .off)
        XCTAssertFalse(config.showLiveTranscript)
        // A stored accent is kept even though the default is now System.
        XCTAssertEqual(config.accent, .violet)
    }

    func testDecodingToleratesMissingKeys() throws {
        let minimal = #"{"language": "fi"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(minimal.utf8))
        XCTAssertEqual(config.primaryProfile.language, "fi")
        XCTAssertEqual(config.primaryProfile.hotkey, .defaultPushToTalk)
        XCTAssertTrue(config.primaryProfile.refinementEnabled)

        // A profile entry with only an id and a name gets defaults and no keys.
        let sparse = #"{"profiles": [{"id": "6F1C2A70-6B7E-4E0B-9C55-1E4B5C2E9D11", "name": "Notes"}]}"#
        let profile = try JSONDecoder().decode(AppConfig.self, from: Data(sparse.utf8)).primaryProfile
        XCTAssertEqual(profile.name, "Notes")
        XCTAssertTrue(profile.isEnabled)
        XCTAssertNil(profile.hotkey)
        XCTAssertEqual(profile.language, "en")
    }

    func testDecodingReplacesRetiredRefinementModels() throws {
        func decoded(_ provider: String, _ model: String) throws -> String {
            let json = #"{"refinementProvider": "\#(provider)", "refinementModel": "\#(model)"}"#
            return try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).primaryProfile.refinementModel
        }

        // Shut-down ids 404 on every call, so a saved one must not survive load.
        XCTAssertEqual(try decoded("groq", "llama-3.3-70b-versatile"), "openai/gpt-oss-120b")
        XCTAssertEqual(try decoded("groq", "llama-3.1-8b-instant"), "openai/gpt-oss-20b")
        XCTAssertEqual(try decoded("cerebras", "llama-3.3-70b"), "gpt-oss-120b")
        // Retirement is per provider: the same id elsewhere is left alone.
        XCTAssertEqual(try decoded("openAI", "llama-3.3-70b-versatile"), "llama-3.3-70b-versatile")
        // A model the user chose stays untouched.
        XCTAssertEqual(try decoded("groq", "openai/gpt-oss-20b"), "openai/gpt-oss-20b")
        // A migrated id equals the provider default, so switching providers
        // in Settings still swaps it out.
        XCTAssertEqual(try decoded("groq", "llama-3.3-70b-versatile"), RefinementProvider.groq.defaultModel)

        // The same holds inside a saved profile.
        let json = #"{"profiles": [{"refinementProvider": "groq", "refinementModel": "llama-3.3-70b-versatile"}]}"#
        let profile = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).primaryProfile
        XCTAssertEqual(profile.refinementModel, "openai/gpt-oss-120b")
    }

    func testOnlyProfilesThatAreOnWithKeysListen() {
        let english = DictationProfile(name: "English")
        let draft = DictationProfile(name: "Draft", hotkey: nil)
        let paused = DictationProfile(name: "Paused", isEnabled: false, hotkey: HotkeySpec(capturedKeyCode: 63))
        let config = AppConfig(profiles: [english, draft, paused])

        XCTAssertEqual(config.activeProfiles, [english])
        XCTAssertEqual(config.hotkeyBindings, [HotkeyBinding(id: english.id, keys: [61])])
    }

    func testPreProfilesConfigStartsSwitchedOn() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"language": "en"}"#.utf8))
        XCTAssertTrue(config.primaryProfile.isEnabled)
    }

    func testProfilesAreNeverEmpty() throws {
        XCTAssertEqual(AppConfig(profiles: []).profiles.count, 1)
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"profiles": []}"#.utf8))
        XCTAssertEqual(config.profiles.count, 1)
    }

    func testConfigSerializationDoesNotContainAPIKeyFields() throws {
        let data = try JSONEncoder().encode(AppConfig())
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("openAIAPIKey"))
        XCTAssertFalse(json.contains("secret"))
    }
}
