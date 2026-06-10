import Foundation

/// Wire protocol for OpenAI Realtime transcription sessions.
/// GA schema verified 2026-06-09 — see docs/PORTING.md before changing shapes.
enum RealtimeProtocol {
    static let defaultEndpoint = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
    static let sampleRate = 24_000

    static func sessionUpdateJSON(
        model: String,
        language: String,
        delay: RealtimeDelay
    ) throws -> String {
        var transcription: [String: Any] = [
            "model": model,
            "delay": delay.rawValue,
        ]
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLanguage.isEmpty, trimmedLanguage.lowercased() != "auto" {
            transcription["language"] = trimmedLanguage
        }

        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": sampleRate,
                        ],
                        "transcription": transcription,
                        // Push-to-talk commits manually; server VAD stays off.
                        "turn_detection": NSNull(),
                    ],
                ],
            ],
        ]

        return try serialize(payload)
    }

    static func appendEventJSON(pcm16: Data) throws -> String {
        try serialize([
            "type": "input_audio_buffer.append",
            "audio": pcm16.base64EncodedString(),
        ])
    }

    static func commitEventJSON() throws -> String {
        try serialize(["type": "input_audio_buffer.commit"])
    }

    enum ServerEvent: Equatable, Sendable {
        case ready
        case delta(String)
        case completed(String)
        case error(String)
        case ignored
    }

    static func parseServerEvent(_ text: String) -> ServerEvent {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let event = object as? [String: Any],
            let type = event["type"] as? String
        else {
            return .ignored
        }

        switch type {
        case "session.created", "session.updated", "transcription_session.updated":
            return .ready
        case "conversation.item.input_audio_transcription.delta":
            return .delta(event["delta"] as? String ?? "")
        case "conversation.item.input_audio_transcription.completed":
            return .completed(event["transcript"] as? String ?? "")
        case "error":
            let nested = event["error"] as? [String: Any]
            let message = (nested?["message"] as? String)
                ?? (event["message"] as? String)
                ?? "Unknown realtime API error"
            return .error(message)
        default:
            return .ignored
        }
    }

    private static func serialize(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw RealtimeProtocolError.encodingFailed
        }
        return json
    }
}

enum RealtimeProtocolError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "Failed to encode a realtime event as JSON."
    }
}
