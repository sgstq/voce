import Foundation

/// Anthropic's Messages API differs from chat-completions in its auth
/// headers, request body and reply shape.
extension Refiner {
    /// The Messages API version Anthropic's current docs use.
    static let anthropicVersion = "2026-10-21"

    /// The reply text: chat-completions puts it in the first choice; the
    /// Messages API returns content blocks, of which only `text` blocks
    /// are the answer (thinking blocks are not).
    static func responseText(_ data: Data, provider: RefinementProvider) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if provider == .anthropic {
            let blocks = object["content"] as? [[String: Any]] ?? []
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        let choices = object["choices"] as? [[String: Any]]
        return (choices?.first?["message"] as? [String: Any])?["content"] as? String
    }

    /// Low effort and as little thinking as each model allows keep a
    /// cleanup fast: Haiku accepts thinking off, Sonnet 5.5 rejects that and
    /// takes `between_tools` (no up-front thinking), and Opus and Fable
    /// always think, so they get only the low effort.
    static func anthropicRequestBody(model: String, system: String, user: String) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": ["effort": "low"],
        ]
        if model.hasPrefix("claude-haiku") {
            payload["thinking"] = ["type": "disabled"]
        } else if model.hasPrefix("claude-sonnet") {
            payload["thinking"] = ["type": "between_tools"]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}
