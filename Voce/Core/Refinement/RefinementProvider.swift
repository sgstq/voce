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
        case .groq: "llama-3.3-70b-versatile"
        case .cerebras: "llama-3.3-70b"
        case .appleOnDevice: ""
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
