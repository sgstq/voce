import XCTest
@testable import Voce

final class AppleSpeechTests: XCTestCase {
    func testPreferredLocale() {
        // Automatic falls back to the system language — on-device
        // recognition cannot detect the spoken language.
        XCTAssertEqual(
            AppleSpeechAssets.preferredLocale(for: "auto").identifier,
            Locale.current.identifier
        )
        XCTAssertEqual(
            AppleSpeechAssets.preferredLocale(for: "").identifier,
            Locale.current.identifier
        )
        XCTAssertEqual(AppleSpeechAssets.preferredLocale(for: " ru ").identifier, "ru")
        XCTAssertEqual(AppleSpeechAssets.preferredLocale(for: "en").identifier, "en")
    }

    func testPCM16BufferRoundTrip() throws {
        let samples: [Int16] = [0, 1, -1, .max, .min]
        let data = samples.withUnsafeBytes { Data($0) }

        let buffer = try AppleTranscriptionSession.pcm16Buffer(from: data)

        XCTAssertEqual(buffer.frameLength, 5)
        XCTAssertEqual(buffer.format.sampleRate, 24_000)
        XCTAssertEqual(buffer.format.channelCount, 1)
        let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: channel, count: 5)), samples)
    }

    func testPCM16BufferRejectsEmptyData() {
        XCTAssertThrowsError(try AppleTranscriptionSession.pcm16Buffer(from: Data()))
    }

    func testBackendKeychainAccounts() {
        XCTAssertEqual(TranscriptionBackend.openAIRealtime.keychainAccount, "openai-api-key")
        XCTAssertEqual(TranscriptionBackend.deepgram.keychainAccount, "deepgram-api-key")
        XCTAssertNil(TranscriptionBackend.appleOnDevice.keychainAccount)
    }
}
