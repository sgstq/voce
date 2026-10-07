import XCTest
@testable import Voce

final class SpeechGateTests: XCTestCase {
    /// A hold of `seconds` at 24 kHz; loudness doesn't matter to the verdict.
    private func gate(seconds: Double) -> SpeechGate {
        var gate = SpeechGate()
        let samples = Int(seconds * Double(RealtimeProtocol.sampleRate))
        gate.add((sumSquares: 0.0001 * Double(samples), sampleCount: samples))
        return gate
    }

    func testLiveTextKeepsHoldTheDetectorMissed() {
        XCTAssertEqual(gate(seconds: 1.0).verdict(heardLiveText: true, voiceDetected: false), .speech)
    }

    func testDetectedVoiceKeepsHoldWithoutLiveText() {
        // A one-second "yes please" ends before any live text arrives.
        XCTAssertEqual(gate(seconds: 1.0).verdict(heardLiveText: false, voiceDetected: true), .speech)
    }

    func testHoldWithoutVoiceOrLiveTextIsSilent() {
        XCTAssertEqual(gate(seconds: 2.0).verdict(heardLiveText: false, voiceDetected: false), .silent)
    }

    func testTapShorterThanMinimumIsTooShort() {
        XCTAssertEqual(gate(seconds: 0.1).verdict(heardLiveText: true, voiceDetected: true), .tooShort)
        XCTAssertEqual(SpeechGate().verdict(heardLiveText: false, voiceDetected: false), .tooShort)
    }

    func testSilenceHallucinationsMatchWholeTranscriptOnly() {
        XCTAssertTrue(SpeechGate.isSilenceHallucination("Thank you."))
        XCTAssertTrue(SpeechGate.isSilenceHallucination("  Thanks for watching!  "))
        XCTAssertTrue(SpeechGate.isSilenceHallucination("Продолжение следует..."))
        XCTAssertTrue(SpeechGate.isSilenceHallucination("..."))
        XCTAssertFalse(SpeechGate.isSilenceHallucination("Thank you for the review"))
        XCTAssertFalse(SpeechGate.isSilenceHallucination("Yes please."))
    }
}
