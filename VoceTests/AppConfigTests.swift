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
        XCTAssertFalse(config.captureScreenshots)
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
        config.captureScreenshots = true

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
        // Fields added after that config was written fall back to defaults.
        XCTAssertEqual(config.refinementModel, "gpt-5-mini")
        XCTAssertEqual(config.refinementProvider, .openAI)
    }

    func testDecodingToleratesMissingKeys() throws {
        let minimal = #"{"language": "fi"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(minimal.utf8))
        XCTAssertEqual(config.language, "fi")
        XCTAssertEqual(config.hotkey, .defaultPushToTalk)
        XCTAssertTrue(config.refinementEnabled)
    }

    func testConfigSerializationDoesNotContainAPIKeyFields() throws {
        let data = try JSONEncoder().encode(AppConfig())
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("openAIAPIKey"))
        XCTAssertFalse(json.contains("secret"))
    }
}
