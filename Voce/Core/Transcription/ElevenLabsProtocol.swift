import Foundation

/// Wire protocol for ElevenLabs realtime speech-to-text (Scribe).
/// Shape verified 2026-11-25 against elevenlabs.io/docs/api-reference/
/// speech-to-text/v-1-speech-to-text-realtime: session options ride the URL,
/// audio goes up as base64 `input_audio_chunk` messages, and a chunk with
/// `commit: true` makes the server send that segment's `committed_transcript`.
enum ElevenLabsProtocol {
    static let defaultEndpoint = URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
    static let sampleRate = RealtimeProtocol.sampleRate

    /// With manual commits the server still commits on its own after about
    /// 36 s of audio. Committing earlier keeps every segment ours to count;
    /// the docs suggest every 20 to 30 s.
    static let commitInterval: TimeInterval = 25

    /// Force-unwraps are safe by construction: `base` is a valid URL and
    /// `URLQueryItem` percent-encodes its values.
    static func endpoint(
        model: String,
        language: String,
        hints: TranscriptionHints,
        base: URL = defaultEndpoint
    ) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "model_id", value: model),
            URLQueryItem(name: "audio_format", value: "pcm_\(sampleRate)"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
        ]
        // Omitted when automatic: Scribe detects the language itself.
        if !DictationLanguages.isAutomatic(language) {
            items.append(URLQueryItem(name: "language_code", value: language.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        // Repeated, one item per term; a comma-joined value would be one term.
        items += hints.keyterms.map { URLQueryItem(name: "keyterms", value: $0) }
        if hints.removeFillerWords {
            items.append(URLQueryItem(name: "no_verbatim", value: "true"))
        }
        if hints.multilingual {
            items.append(URLQueryItem(name: "multilang_mode", value: "true"))
        }
        components.queryItems = items
        return components.url!
    }

    static func audioChunkJSON(pcm16: Data, commit: Bool) throws -> String {
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": pcm16.base64EncodedString(),
            "commit": commit,
            "sample_rate": sampleRate,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw RealtimeProtocolError.encodingFailed
        }
        return json
    }

    enum ServerEvent: Equatable, Sendable {
        case sessionStarted
        /// Interim text for the open segment; later partials replace it.
        case partial(String)
        /// Final text for one committed segment.
        case committed(String)
        /// The server heard no speech in what it was sent.
        case noSpeech
        case error(String)
        case ignored
    }

    static func parseServerEvent(_ text: String) -> ServerEvent {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let event = object as? [String: Any],
            let type = event["message_type"] as? String
        else {
            return .ignored
        }

        switch type {
        case "session_started":
            return .sessionStarted
        case "partial_transcript":
            return .partial(event["text"] as? String ?? "")
        case "committed_transcript":
            return .committed(event["text"] as? String ?? "")
        case "insufficient_audio_activity":
            return .noSpeech
        default:
            // Every error type (auth_error, quota_exceeded, rate_limited,
            // invalid_request, …) carries its message in `error`; warnings
            // and the other add-on events do not.
            if let message = event["error"] as? String {
                return .error(message)
            }
            return .ignored
        }
    }
}
