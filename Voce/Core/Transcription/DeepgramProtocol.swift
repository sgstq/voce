import Foundation

/// Wire protocol for Deepgram live streaming transcription.
/// API shape verified 2026-07-14 against developers.deepgram.com: the session
/// is configured entirely through URL query parameters, audio is sent as
/// binary frames, and `CloseStream` flushes the remaining transcript before
/// the server closes the socket.
enum DeepgramProtocol {
    static let defaultEndpoint = URL(string: "wss://api.deepgram.com/v1/listen")!
    /// Both backends consume the same 24 kHz mono PCM16 stream that
    /// `AudioCaptureEngine` produces.
    static let sampleRate = RealtimeProtocol.sampleRate

    /// Deepgram reads all session config from the URL — there is no
    /// `session.update` equivalent. Force-unwraps are safe by construction:
    /// `base` is a valid URL and `URLQueryItem` percent-encodes its values.
    static func endpoint(model: String, language: String, base: URL = defaultEndpoint) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "language", value: mappedLanguage(language)),
        ]
        return components.url!
    }

    /// nova-3 code-switches between languages when `language=multi` — the
    /// closest match for the app's "auto" language setting.
    static func mappedLanguage(_ language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "auto" {
            return "multi"
        }
        return trimmed
    }

    static let closeStreamJSON = #"{"type":"CloseStream"}"#

    enum ServerEvent: Equatable, Sendable {
        /// Transcript for the current audio window. `isFinal` marks the
        /// segment as stable — later Results never revise it.
        case results(transcript: String, isFinal: Bool)
        /// Sent after `CloseStream` once every Result has been flushed.
        case metadata
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
        case "Results":
            let alternatives = (event["channel"] as? [String: Any])?["alternatives"] as? [[String: Any]]
            return .results(
                transcript: alternatives?.first?["transcript"] as? String ?? "",
                isFinal: event["is_final"] as? Bool ?? false
            )
        case "Metadata":
            return .metadata
        default:
            return .ignored
        }
    }
}
