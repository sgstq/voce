import XCTest
@testable import Voce

final class RealtimeProtocolTests: XCTestCase {
    func testSessionUpdateMatchesGASchema() throws {
        let json = try RealtimeProtocol.sessionUpdateJSON(
            model: "gpt-realtime-whisper",
            language: "en",
            delay: .low
        )
        let event = try decode(json)

        XCTAssertEqual(event["type"] as? String, "session.update")

        let session = try XCTUnwrap(event["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")

        let input = try XCTUnwrap(
            (session["audio"] as? [String: Any])?["input"] as? [String: Any]
        )

        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)

        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-realtime-whisper")
        XCTAssertEqual(transcription["language"] as? String, "en")
        XCTAssertEqual(transcription["delay"] as? String, "low")

        // Push-to-talk requires server VAD off via an explicit null.
        XCTAssertTrue(input.keys.contains("turn_detection"))
        XCTAssertTrue(input["turn_detection"] is NSNull)
    }

    func testSessionUpdateOmitsAutoLanguage() throws {
        let json = try RealtimeProtocol.sessionUpdateJSON(
            model: "gpt-realtime-whisper",
            language: "auto",
            delay: .minimal
        )
        let event = try decode(json)
        let transcription = try XCTUnwrap(
            ((((event["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"]
                as? [String: Any])?["transcription"]) as? [String: Any]
        )

        XCTAssertNil(transcription["language"])
        XCTAssertEqual(transcription["delay"] as? String, "minimal")
    }

    func testAppendEventRoundTripsAudio() throws {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let json = try RealtimeProtocol.appendEventJSON(pcm16: pcm)
        let event = try decode(json)

        XCTAssertEqual(event["type"] as? String, "input_audio_buffer.append")
        let base64 = try XCTUnwrap(event["audio"] as? String)
        XCTAssertEqual(Data(base64Encoded: base64), pcm)
    }

    func testCommitEvent() throws {
        let event = try decode(RealtimeProtocol.commitEventJSON())
        XCTAssertEqual(event["type"] as? String, "input_audio_buffer.commit")
    }

    func testParsesServerEvents() {
        XCTAssertEqual(
            RealtimeProtocol.parseServerEvent(#"{"type":"session.updated"}"#),
            .ready
        )
        XCTAssertEqual(
            RealtimeProtocol.parseServerEvent(
                #"{"type":"conversation.item.input_audio_transcription.delta","delta":"hel"}"#
            ),
            .delta("hel")
        )
        XCTAssertEqual(
            RealtimeProtocol.parseServerEvent(
                #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"hello"}"#
            ),
            .completed("hello")
        )
        XCTAssertEqual(
            RealtimeProtocol.parseServerEvent(
                #"{"type":"error","error":{"message":"bad key"}}"#
            ),
            .error("bad key")
        )
        XCTAssertEqual(
            RealtimeProtocol.parseServerEvent(#"{"type":"rate_limits.updated"}"#),
            .ignored
        )
        XCTAssertEqual(RealtimeProtocol.parseServerEvent("not json"), .ignored)
    }

    private func decode(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }
}
