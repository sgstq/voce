import XCTest
@testable import Voce

final class SpeechGateTests: XCTestCase {
    /// One ~100 ms capture chunk at 24 kHz with the given normalized RMS.
    private func chunk(rms: Double) -> (sumSquares: Double, sampleCount: Int) {
        let samples = RealtimeProtocol.sampleRate / 10
        return (rms * rms * Double(samples), samples)
    }

    private func gate(_ levels: [Double]) -> SpeechGate {
        var gate = SpeechGate()
        for level in levels {
            gate.add(chunk(rms: level))
        }
        return gate
    }

    func testLiveTextKeepsQuietRecording() {
        // Logged 2026-10-06: 15.09 s at rms 0.0034 was dropped while words
        // were already on screen.
        let quiet = gate(Array(repeating: 0.0034, count: 151))
        XCTAssertEqual(quiet.verdict(heardLiveText: true), .speech)
        XCTAssertEqual(quiet.verdict(heardLiveText: false), .silent)
    }

    func testPausesDoNotDiluteSpeech() {
        // 30% speech, 70% pauses: the whole-hold average lands under the
        // old 0.005 gate, but the voiced chunks still count.
        let levels = (0..<466).map { $0 % 10 < 3 ? 0.008 : 0.001 }
        let pausy = gate(levels)
        XCTAssertLessThan(pausy.averageRMS, 0.005)
        XCTAssertEqual(pausy.verdict(heardLiveText: false), .speech)
    }

    func testQuietHoldIsSilent() {
        // Logged 2026-10-05: 0.69 s at rms 0.0007.
        XCTAssertEqual(gate(Array(repeating: 0.0007, count: 7)).verdict(heardLiveText: false), .silent)
    }

    func testSingleKeyClickIsNotSpeech() {
        var levels = Array(repeating: 0.0005, count: 10)
        levels[9] = 0.05
        XCTAssertEqual(gate(levels).verdict(heardLiveText: false), .silent)
    }

    func testTapShorterThanMinimumIsTooShort() {
        XCTAssertEqual(gate([0.02]).verdict(heardLiveText: false), .tooShort)
        XCTAssertEqual(SpeechGate().verdict(heardLiveText: false), .tooShort)
    }
}
