import Foundation

/// Where the refinement pass runs. Cloud providers speak the
/// OpenAI-compatible chat-completions protocol with per-provider tuning;
/// Apple on-device uses the FoundationModels framework (no key, no network).
enum RefinementProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case groq
    case cerebras
    case appleOnDevice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .groq: "Groq"
        case .cerebras: "Cerebras"
        case .appleOnDevice: "Apple on-device"
        }
    }

    var isCloud: Bool { self != .appleOnDevice }

    var endpoint: URL? {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")
        case .groq: URL(string: "https://api.groq.com/openai/v1/chat/completions")
        case .cerebras: URL(string: "https://api.cerebras.ai/v1/chat/completions")
        case .appleOnDevice: nil
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .groq: "openai/gpt-oss-120b"
        case .cerebras: "gpt-oss-120b"
        case .appleOnDevice: ""
        }
    }

    /// Model ids the provider has shut down, mapped to its recommended
    /// replacement. Saved configs keep a model id forever, so a retired id
    /// must be rewritten on load or refinement 404s on every dictation.
    /// Groq: https://console.groq.com/docs/deprecations (Llama shut down
    /// 2026-08-16 for non-enterprise tiers). Cerebras dropped Llama 3.3 70B
    /// from its catalog.
    func replacement(forRetiredModel model: String) -> String? {
        switch self {
        case .groq:
            switch model {
            case "llama-3.3-70b-versatile": "openai/gpt-oss-120b"
            case "llama-3.1-8b-instant": "openai/gpt-oss-20b"
            default: nil
            }
        case .cerebras:
            model == "llama-3.3-70b" ? "gpt-oss-120b" : nil
        case .openAI, .appleOnDevice:
            nil
        }
    }

    /// Keychain account for the provider's API key. OpenAI shares the
    /// transcription key — one key for both, entered once.
    var keychainAccount: String? {
        switch self {
        case .openAI: "openai-api-key"
        case .groq: "groq-api-key"
        case .cerebras: "cerebras-api-key"
        case .appleOnDevice: nil
        }
    }
}
