import XCTest
@testable import Voce

final class AppConfigTests: XCTestCase {
    func testDefaultConfigMatchesPhaseZeroPlan() {
        let config = AppConfig()

        XCTAssertEqual(config.hotkey, .defaultPushToTalk)
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.insertionMode, .auto)
        XCTAssertEqual(config.transcriptionBackend, .openAIRealtime)
        XCTAssertEqual(config.realtimeModel, "gpt-realtime-whisper")
        XCTAssertEqual(config.realtimeDelay, .low)
        XCTAssertTrue(config.refinementEnabled)
        XCTAssertTrue(config.captureContext)
        XCTAssertEqual(config.screenContext, .off)
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
        config.hotkey = HotkeySpec(capturedKeyCode: 61) // Right ⌥
        config.language = "es"
        config.insertionMode = .keystrokes
        config.realtimeDelay = .medium
        config.screenContext = .termsOnly
        config.showLiveTranscript = true
        config.accent = .green

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
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
        XCTAssertEqual(config.hotkey, HotkeySpec(keyCode: 97, kind: .key, displayName: "F6"))
        // Fields added after that config was written fall back to defaults;
        // the retired "captureScreenshots" key is ignored harmlessly.
        XCTAssertEqual(config.refinementModel, "gpt-5-mini")
        XCTAssertEqual(config.refinementProvider, .openAI)
        XCTAssertEqual(config.deepgramModel, "nova-3")
        XCTAssertEqual(config.openRouterModel, "microsoft/mai-transcribe-2")
        XCTAssertEqual(config.screenContext, .off)
        XCTAssertFalse(config.showLiveTranscript)
        // A stored accent is kept even though the default is now System.
        XCTAssertEqual(config.accent, .violet)
    }

    func testDecodingToleratesMissingKeys() throws {
        let minimal = #"{"language": "fi"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(minimal.utf8))
        XCTAssertEqual(config.language, "fi")
        XCTAssertEqual(config.hotkey, .defaultPushToTalk)
        XCTAssertTrue(config.refinementEnabled)
    }

    func testDecodingReplacesRetiredRefinementModels() throws {
        func decoded(_ provider: String, _ model: String) throws -> String {
            let json = #"{"refinementProvider": "\#(provider)", "refinementModel": "\#(model)"}"#
            return try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).refinementModel
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
    }

    func testConfigSerializationDoesNotContainAPIKeyFields() throws {
        let data = try JSONEncoder().encode(AppConfig())
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("openAIAPIKey"))
        XCTAssertFalse(json.contains("secret"))
    }
}
