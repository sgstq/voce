import CoreML
import Foundation

/// Answers "did anyone speak in this recording?" with Silero VAD v6 (MIT;
/// CoreML conversion by FluidAudio, see Voce/Resources/SileroVAD/NOTICE.md).
/// Unlike a loudness threshold it separates voice from fan noise and key
/// clicks, and the audio is normalized first so a quiet "yes please" on a
/// low-gain mic still counts.
actor VoiceActivityDetector {
    struct Result: Sendable, Equatable {
        /// Seconds of 32 ms frames scored as speech.
        let speechDuration: TimeInterval
        let maxProbability: Float

        var detected: Bool {
            speechDuration >= Double(VoiceActivityDetector.minimumSpeechFrames) * VoiceActivityDetector.frameDuration
        }
    }

    static let modelName = "silero-vad-unified-v6.0.0"
    static let modelSampleRate = 16_000
    static let frameSize = 512
    static let contextSize = 64
    static let stateSize = 128
    static let frameDuration = Double(frameSize) / Double(modelSampleRate)
    static let speechThreshold: Float = 0.5
    /// Three frames (~96 ms): a short "yes" passes, a lone key click doesn't.
    static let minimumSpeechFrames = 3
    /// Normalization brings the 99.9th-percentile sample to half scale, but
    /// never by more than +40 dB, so near-silence isn't amplified into detail.
    static let normalizedPeak: Float = 0.5
    static let maxGain: Float = 100

    private let modelURL: URL
    private var model: MLModel?

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    init() {
        self.init(modelURL: Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc")
            ?? Bundle.main.bundleURL.appending(path: "Contents/Resources/\(Self.modelName).mlmodelc"))
    }

    /// Loads the model ahead of the first analysis (call while recording).
    func prewarm() throws {
        _ = try loadedModel()
    }

    /// Scores mono PCM16 audio at `sampleRate`.
    func analyze(pcm16: Data, sampleRate: Int) throws -> Result {
        let samples = Self.normalizedSamples(pcm16: pcm16, sampleRate: sampleRate)
        let model = try loadedModel()

        let audio = try MLMultiArray(shape: [1, NSNumber(value: Self.contextSize + Self.frameSize)], dataType: .float32)
        let hidden = try MLMultiArray(shape: [1, NSNumber(value: Self.stateSize)], dataType: .float32)
        let cell = try MLMultiArray(shape: [1, NSNumber(value: Self.stateSize)], dataType: .float32)
        for array in [audio, hidden, cell] {
            array.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in buffer.initialize(repeating: 0) }
        }
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "audio_input": MLFeatureValue(multiArray: audio),
            "hidden_state": MLFeatureValue(multiArray: hidden),
            "cell_state": MLFeatureValue(multiArray: cell),
        ])

        var speechFrames = 0
        var maxProbability: Float = 0
        var start = 0
        while start + Self.frameSize <= samples.count {
            // Input = last 64 samples of the previous frame + this frame.
            audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
                for index in 0..<Self.contextSize {
                    buffer[index] = start == 0 ? 0 : samples[start - Self.contextSize + index]
                }
                for index in 0..<Self.frameSize { buffer[Self.contextSize + index] = samples[start + index] }
            }
            let output = try model.prediction(from: inputs)
            guard let probability = output.featureValue(for: "vad_output")?.multiArrayValue?[0].floatValue,
                  let newHidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue,
                  let newCell = output.featureValue(for: "new_cell_state")?.multiArrayValue else {
                throw DetectorError.unexpectedOutput
            }
            Self.copy(newHidden, into: hidden)
            Self.copy(newCell, into: cell)

            maxProbability = max(maxProbability, probability)
            if probability >= Self.speechThreshold { speechFrames += 1 }
            start += Self.frameSize
        }
        return Result(speechDuration: Double(speechFrames) * Self.frameDuration, maxProbability: maxProbability)
    }

    enum DetectorError: LocalizedError {
        case modelMissing(URL)
        case unexpectedOutput

        var errorDescription: String? {
            switch self {
            case .modelMissing(let url): "Speech detector model not found at \(url.path)."
            case .unexpectedOutput: "Speech detector returned an unexpected output."
            }
        }
    }

    private func loadedModel() throws -> MLModel {
        if let model { return model }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw DetectorError.modelMissing(modelURL)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let loaded = try MLModel(contentsOf: modelURL, configuration: configuration)
        model = loaded
        return loaded
    }

    private static func copy(_ source: MLMultiArray, into destination: MLMultiArray) {
        source.withUnsafeBufferPointer(ofType: Float.self) { from in
            destination.withUnsafeMutableBufferPointer(ofType: Float.self) { to, _ in
                for index in 0..<min(from.count, to.count) { to[index] = from[index] }
            }
        }
    }

    /// PCM16 → Float, normalized (see `normalizedPeak`), linearly resampled
    /// to 16 kHz. Internal for tests.
    static func normalizedSamples(pcm16: Data, sampleRate: Int) -> [Float] {
        let input: [Int16] = pcm16.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        guard !input.isEmpty else { return [] }
        let gain = normalizationGain(input)

        let ratio = Double(sampleRate) / Double(modelSampleRate)
        let outputCount = Int(Double(input.count) / ratio)
        var output = [Float](repeating: 0, count: outputCount)
        for index in 0..<outputCount {
            let position = Double(index) * ratio
            let lower = Int(position)
            let upper = min(lower + 1, input.count - 1)
            let fraction = Float(position - Double(lower))
            let value = (Float(input[lower]) * (1 - fraction) + Float(input[upper]) * fraction) / 32768
            output[index] = min(1, max(-1, value * gain))
        }
        return output
    }

    /// Gain bringing the 99.9th-percentile magnitude to `normalizedPeak`.
    /// A magnitude histogram keeps this O(n) on long recordings.
    static func normalizationGain(_ samples: [Int16]) -> Float {
        var histogram = [Int](repeating: 0, count: 32_769)
        for sample in samples { histogram[Int(sample.magnitude)] += 1 }
        let target = Int(Double(samples.count) * 0.999)
        var cumulative = 0
        for (level, count) in histogram.enumerated() {
            cumulative += count
            if cumulative > target {
                guard level > 0 else { return 1 }
                return min(normalizedPeak / (Float(level) / 32768), maxGain)
            }
        }
        return 1
    }
}
