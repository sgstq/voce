import AVFoundation
import Foundation

/// Captures microphone audio with `AVAudioEngine` and emits 24 kHz mono
/// PCM16 chunks, ready for `input_audio_buffer.append`. The engine only runs
/// while push-to-talk is held, so the mic indicator stays off when idle.
@MainActor
final class AudioCaptureEngine {
    enum CaptureError: LocalizedError {
        case noInputDevice
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .noInputDevice:
                "No microphone input device is available."
            case .converterUnavailable:
                "The microphone format could not be converted for transcription."
            }
        }
    }

    private var engine: AVAudioEngine?

    /// Starts capture and returns an ordered stream of PCM16 chunks.
    /// The stream finishes when `stop()` is called.
    func start() throws -> AsyncStream<Data> {
        stop()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(RealtimeProtocol.sampleRate),
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw CaptureError.converterUnavailable
        }

        let (stream, continuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .unbounded
        )
        let context = TapContext(converter: converter, outputFormat: outputFormat, continuation: continuation)
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate

        // ~100 ms buffers at the device rate keep preview latency low without
        // flooding the websocket.
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate / 10)
        // @Sendable: the tap fires on AVFAudio's realtime queue. Without it
        // the closure inherits @MainActor isolation from this method and the
        // Swift 6 runtime isolation check crashes on the first buffer.
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { @Sendable buffer, _ in
            context.process(buffer: buffer, ratio: ratio)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            throw error
        }

        self.engine = engine
        return stream
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}

/// State owned by the audio tap. The tap fires on a single render thread, so
/// access is serial even though the type crosses an isolation boundary.
private final class TapContext: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<Data>.Continuation

    init(
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        continuation: AsyncStream<Data>.Continuation
    ) {
        self.converter = converter
        self.outputFormat = outputFormat
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func process(buffer: AVAudioPCMBuffer, ratio: Double) {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil, output.frameLength > 0,
              let channel = output.int16ChannelData else {
            return
        }

        let data = Data(bytes: channel[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
        continuation.yield(data)
    }
}

enum AudioMath {
    /// Normalized RMS energy of PCM16 samples, in [0, 1]. Mirrors the
    /// prototype's silence gate (`RMS < 0.005` ⇒ silence).
    static func rmsEnergy(pcm16 data: Data) -> (sumSquares: Double, sampleCount: Int) {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return (0, 0) }

        var sumSquares = 0.0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Double(sample) / 32768.0
                sumSquares += normalized * normalized
            }
        }
        return (sumSquares, sampleCount)
    }
}
