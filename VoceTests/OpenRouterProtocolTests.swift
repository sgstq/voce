import XCTest
@testable import Voce

final class OpenRouterProtocolTests: XCTestCase {
    private let samples = Data([0x01, 0x00, 0xFF, 0x7F, 0x00, 0x80])

    func testRequestShape() throws {
        let request = try OpenRouterProtocol.transcriptionRequest(
            apiKey: "sk-or-test",
            model: "microsoft/mai-transcribe-2",
            language: "en",
            pcm16: samples
        )

        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "microsoft/mai-transcribe-2")
        XCTAssertEqual(payload["language"] as? String, "en")

        let input = try XCTUnwrap(payload["input_audio"] as? [String: Any])
        XCTAssertEqual(input["format"] as? String, "wav")
        let encoded = try XCTUnwrap(input["data"] as? String)
        XCTAssertFalse(encoded.hasPrefix("data:"))
        XCTAssertEqual(Data(base64Encoded: encoded), OpenRouterProtocol.wav(pcm16: samples))
    }

    func testAutomaticLanguageIsOmitted() throws {
        for language in ["auto", "Auto", " "] {
            let body = try OpenRouterProtocol.requestBody(model: "m", language: language, pcm16: samples)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(payload["language"], "language \"\(language)\" should be omitted")
        }

        let body = try OpenRouterProtocol.requestBody(model: "m", language: " ru ", pcm16: samples)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["language"] as? String, "ru")
    }

    func testWAVHeader() {
        let wav = OpenRouterProtocol.wav(pcm16: samples)
        let header: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            0x2A, 0x00, 0x00, 0x00, // 36 + 6 data bytes
            0x57, 0x41, 0x56, 0x45, // "WAVE"
            0x66, 0x6D, 0x74, 0x20, // "fmt "
            0x10, 0x00, 0x00, 0x00, // fmt chunk size 16
            0x01, 0x00, // PCM
            0x01, 0x00, // mono
            0xC0, 0x5D, 0x00, 0x00, // 24 000 Hz
            0x80, 0xBB, 0x00, 0x00, // 48 000 bytes/s
            0x02, 0x00, // block align
            0x10, 0x00, // 16 bits
            0x64, 0x61, 0x74, 0x61, // "data"
            0x06, 0x00, 0x00, 0x00, // 6 data bytes
        ]

        XCTAssertEqual(wav.count, 44 + samples.count)
        XCTAssertEqual(Array(wav.prefix(44)), header)
        XCTAssertEqual(wav.suffix(samples.count), samples)
    }

    func testParsesResponses() {
        XCTAssertEqual(
            OpenRouterProtocol.parseResponse(
                Data(#"{"text":"Hello world.","usage":{"seconds":1.2,"cost":0.00003}}"#.utf8),
                statusCode: 200
            ),
            .transcript("Hello world.")
        )
        XCTAssertEqual(
            OpenRouterProtocol.parseResponse(Data(#"{"text":""}"#.utf8), statusCode: 200),
            .transcript("")
        )
        XCTAssertEqual(
            OpenRouterProtocol.parseResponse(
                Data(#"{"error":{"code":401,"message":"No auth credentials found"}}"#.utf8),
                statusCode: 401
            ),
            .error("OpenRouter: No auth credentials found")
        )
        XCTAssertEqual(
            OpenRouterProtocol.parseResponse(Data("<html>Bad gateway</html>".utf8), statusCode: 502),
            .error("OpenRouter returned HTTP 502")
        )
        XCTAssertEqual(
            OpenRouterProtocol.parseResponse(Data(#"{"usage":{}}"#.utf8), statusCode: 200),
            .error("OpenRouter returned no transcript")
        )
    }
}
