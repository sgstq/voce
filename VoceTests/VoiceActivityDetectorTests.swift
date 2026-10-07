import XCTest
@testable import Voce

final class VoiceActivityDetectorTests: XCTestCase {
    private let sampleRate = RealtimeProtocol.sampleRate

    /// Deterministic noise so the no-voice cases can't flake.
    private struct Noise {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    private func pcm16(_ samples: [Double]) -> Data {
        let ints = samples.map { Int16(max(-1, min(1, $0)) * 32767) }
        return ints.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func floor(seconds: Double, noise: inout Noise) -> [Double] {
        (0..<Int(seconds * Double(sampleRate))).map { _ in noise.next() * 0.001 }
    }

    func testNormalizationRaisesQuietAudioAndCapsNearSilence() {
        XCTAssertEqual(VoiceActivityDetector.normalizationGain(Array(repeating: 1638, count: 1000)), 10, accuracy: 0.01)
        XCTAssertEqual(VoiceActivityDetector.normalizationGain(Array(repeating: 3, count: 1000)), 100)
        XCTAssertEqual(VoiceActivityDetector.normalizationGain([]), 1)
    }

    func testResamplesToModelRate() {
        let oneSecond = pcm16(Array(repeating: 0.1, count: sampleRate))
        XCTAssertEqual(VoiceActivityDetector.normalizedSamples(pcm16: oneSecond, sampleRate: sampleRate).count, 16_000)
    }

    func testDetectsQuietYesPlease() async throws {
        // Synthetic "yes please" at RMS 0.002 — quieter than the real one
        // the old loudness gate dropped (0.0010 speech in a 1.7 s hold).
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "yes-please-quiet", withExtension: "wav"))
        let pcm = try Data(contentsOf: url).dropFirst(44)
        let result = try await VoiceActivityDetector().analyze(pcm16: Data(pcm), sampleRate: sampleRate)
        XCTAssertTrue(result.detected, "speech \(result.speechDuration)s max \(result.maxProbability)")
    }

    func testIgnoresSilenceClicksAndFanNoise() async throws {
        var noise = Noise()
        let silence = floor(seconds: 2, noise: &noise)

        var clicks = floor(seconds: 1, noise: &noise)
        for at in [0.1, 0.5, 0.9] {
            let start = Int(at * Double(sampleRate))
            for offset in 0..<120 { clicks[start + offset] += noise.next() * 0.3 }
        }

        // Brown noise with its slow drift removed: a broadband fan-like hum.
        var level = 0.0
        let brown = (0..<(3 * sampleRate)).map { _ in level += noise.next(); return level }
        var fan = [Double](repeating: 0, count: brown.count)
        var window = 0.0
        for index in brown.indices {
            window += brown[index] - (index >= 400 ? brown[index - 400] : 0)
            fan[index] = (brown[index] - window / Double(min(index + 1, 400))) * 0.001
        }

        let detector = VoiceActivityDetector()
        for (name, samples) in [("silence", silence), ("clicks", clicks), ("fan", fan)] {
            let result = try await detector.analyze(pcm16: pcm16(samples), sampleRate: sampleRate)
            XCTAssertFalse(result.detected, "\(name): speech \(result.speechDuration)s max \(result.maxProbability)")
        }
    }
}
