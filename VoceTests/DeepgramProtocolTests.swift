import XCTest
@testable import Voce

final class DeepgramProtocolTests: XCTestCase {
    func testEndpointCarriesSessionConfig() throws {
        let url = DeepgramProtocol.endpoint(model: "nova-3", language: "en")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "api.deepgram.com")
        XCTAssertEqual(components.path, "/v1/listen")

        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(query["model"], "nova-3")
        XCTAssertEqual(query["encoding"], "linear16")
        XCTAssertEqual(query["sample_rate"], "24000")
        XCTAssertEqual(query["channels"], "1")
        XCTAssertEqual(query["interim_results"], "true")
        XCTAssertEqual(query["smart_format"], "true")
        XCTAssertEqual(query["language"], "en")
    }

    func testLanguageMapping() {
        // "Auto" rides nova-3's multilingual code-switching.
        XCTAssertEqual(DeepgramProtocol.mappedLanguage("auto"), "multi")
        XCTAssertEqual(DeepgramProtocol.mappedLanguage("Auto"), "multi")
        XCTAssertEqual(DeepgramProtocol.mappedLanguage(""), "multi")
        XCTAssertEqual(DeepgramProtocol.mappedLanguage(" ru "), "ru")
        XCTAssertEqual(DeepgramProtocol.mappedLanguage("en-US"), "en-US")
    }

    func testCloseStreamMessage() throws {
        let object = try JSONSerialization.jsonObject(
            with: Data(DeepgramProtocol.closeStreamJSON.utf8)
        )
        let event = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(event["type"] as? String, "CloseStream")
    }

    func testParsesServerEvents() {
        XCTAssertEqual(
            DeepgramProtocol.parseServerEvent(
                #"{"type":"Results","is_final":false,"channel":{"alternatives":[{"transcript":"hello wor"}]}}"#
            ),
            .results(transcript: "hello wor", isFinal: false)
        )
        XCTAssertEqual(
            DeepgramProtocol.parseServerEvent(
                #"{"type":"Results","is_final":true,"speech_final":true,"channel":{"alternatives":[{"transcript":"hello world"}]}}"#
            ),
            .results(transcript: "hello world", isFinal: true)
        )
        XCTAssertEqual(
            DeepgramProtocol.parseServerEvent(#"{"type":"Results","is_final":true,"channel":{"alternatives":[]}}"#),
            .results(transcript: "", isFinal: true)
        )
        XCTAssertEqual(
            DeepgramProtocol.parseServerEvent(#"{"type":"Metadata","request_id":"abc","duration":1.5}"#),
            .metadata
        )
        XCTAssertEqual(
            DeepgramProtocol.parseServerEvent(#"{"type":"SpeechStarted","timestamp":0.2}"#),
            .ignored
        )
        XCTAssertEqual(
            DeepgramProtocol.parseServerEvent(#"{"type":"UtteranceEnd","last_word_end":1.2}"#),
            .ignored
        )
        XCTAssertEqual(DeepgramProtocol.parseServerEvent("not json"), .ignored)
    }
}
