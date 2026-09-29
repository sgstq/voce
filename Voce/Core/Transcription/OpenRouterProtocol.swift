import Foundation

/// Wire protocol for OpenRouter speech-to-text: one JSON POST carrying the
/// whole recording as base64 WAV, answered with the full transcript.
/// Shape per openrouter.ai/docs/guides/overview/multimodal/stt (2026-09-29).
enum OpenRouterProtocol {
    static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!
    static let sampleRate = RealtimeProtocol.sampleRate

    static func transcriptionRequest(
        apiKey: String,
        model: String,
        language: String,
        pcm16: Data,
        endpoint: URL = defaultEndpoint
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try requestBody(model: model, language: language, pcm16: pcm16)
        return request
    }

    static func requestBody(model: String, language: String, pcm16: Data) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "input_audio": [
                "data": wav(pcm16: pcm16).base64EncodedString(),
                "format": "wav",
            ],
        ]
        // Omitted when automatic: the model detects the language itself.
        if !DictationLanguages.isAutomatic(language) {
            payload["language"] = language.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Wraps mono little-endian PCM16 in a canonical 44-byte RIFF header.
    static func wav(pcm16: Data) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(pcm16.count)

        var wav = Data(capacity: 44 + pcm16.count)
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.appendLittleEndian(36 + dataSize)
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1)) // PCM
        wav.appendLittleEndian(channels)
        wav.appendLittleEndian(UInt32(sampleRate))
        wav.appendLittleEndian(byteRate)
        wav.appendLittleEndian(blockAlign)
        wav.appendLittleEndian(bitsPerSample)
        wav.append(contentsOf: Array("data".utf8))
        wav.appendLittleEndian(dataSize)
        wav.append(pcm16)
        return wav
    }

    enum Response: Equatable, Sendable {
        case transcript(String)
        case error(String)
    }

    static func parseResponse(_ data: Data, statusCode: Int) -> Response {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if (200..<300).contains(statusCode), let text = object?["text"] as? String {
            return .transcript(text)
        }

        let nested = object?["error"] as? [String: Any]
        if let message = (nested?["message"] as? String) ?? (object?["message"] as? String) {
            return .error("OpenRouter: \(message)")
        }
        if (200..<300).contains(statusCode) {
            return .error("OpenRouter returned no transcript")
        }
        return .error("OpenRouter returned HTTP \(statusCode)")
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
