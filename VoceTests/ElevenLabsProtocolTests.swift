import XCTest
@testable import Voce

final class ElevenLabsProtocolTests: XCTestCase {
    private func queryItems(_ url: URL) throws -> [URLQueryItem] {
        try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    func testEndpointCarriesSessionConfigAndRepeatsKeyterms() throws {
        let url = ElevenLabsProtocol.endpoint(
            model: "scribe_v3_live",
            language: " ru ",
            hints: TranscriptionHints(keyterms: ["Voce", "customer service"], removeFillerWords: true, multilingual: true)
        )
        XCTAssertEqual(url.host, "api.elevenlabs.io")
        XCTAssertEqual(url.path, "/v1/speech-to-text/realtime")

        let items = try queryItems(url)
        let single = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(single["model_id"], "scribe_v3_live")
        XCTAssertEqual(single["audio_format"], "pcm_24000")
        XCTAssertEqual(single["commit_strategy"], "manual")
        XCTAssertEqual(single["language_code"], "ru")
        XCTAssertEqual(single["no_verbatim"], "true")
        XCTAssertEqual(single["multilang_mode"], "true")
        XCTAssertEqual(items.filter { $0.name == "keyterms" }.map(\.value), ["Voce", "customer service"])
    }

    func testDefaultsSendNoOptionalParameters() throws {
        let names = try queryItems(
            ElevenLabsProtocol.endpoint(model: "scribe_v3_live", language: "auto", hints: TranscriptionHints())
        ).map(\.name)
        XCTAssertEqual(Set(names), ["model_id", "audio_format", "commit_strategy"])
    }

    func testAudioChunk() throws {
        let json = try ElevenLabsProtocol.audioChunkJSON(pcm16: Data([1, 2, 3, 4]), commit: true)
        let event = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(event["message_type"] as? String, "input_audio_chunk")
        XCTAssertEqual(event["audio_base_64"] as? String, Data([1, 2, 3, 4]).base64EncodedString())
        XCTAssertEqual(event["commit"] as? Bool, true)
        XCTAssertEqual(event["sample_rate"] as? Int, 24_000)
    }

    func testParsesServerEvents() {
        XCTAssertEqual(
            ElevenLabsProtocol.parseServerEvent(#"{"message_type":"session_started","session_id":"s","config":{}}"#),
            .sessionStarted
        )
        XCTAssertEqual(ElevenLabsProtocol.parseServerEvent(#"{"message_type":"partial_transcript","text":"hello wor"}"#), .partial("hello wor"))
        XCTAssertEqual(ElevenLabsProtocol.parseServerEvent(#"{"message_type":"committed_transcript","text":"hello world"}"#), .committed("hello world"))
        XCTAssertEqual(
            ElevenLabsProtocol.parseServerEvent(#"{"message_type":"insufficient_audio_activity","error":"No speech"}"#),
            .noSpeech
        )
        XCTAssertEqual(
            ElevenLabsProtocol.parseServerEvent(#"{"message_type":"quota_exceeded","error":"Out of credits"}"#),
            .error("Out of credits")
        )
        // Warnings are not fatal.
        XCTAssertEqual(ElevenLabsProtocol.parseServerEvent(#"{"message_type":"warning","warning":"logged"}"#), .ignored)
        XCTAssertEqual(ElevenLabsProtocol.parseServerEvent("not json"), .ignored)
    }
}
