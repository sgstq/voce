import Foundation
import FoundationModels
import os

/// Refinement on Apple's on-device foundation model (macOS 26): no network,
/// no API key, private by construction. Availability depends on Apple
/// Intelligence being enabled and the model downloaded.
actor AppleRefiner {
    enum AppleRefinerError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason):
                "Apple on-device model unavailable: \(reason)"
            }
        }
    }

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "refine.apple")

    /// One session is kept prewarmed; it is replaced after each request so
    /// previous dictations never leak into the next prompt's context.
    private var session: LanguageModelSession?

    static func availabilityDescription() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Available"
        case .unavailable(let reason):
            return Self.describe(reason)
        }
    }

    /// Loads model resources ahead of need — called on hotkey press so the
    /// model is hot by the time the transcript lands.
    func prewarm() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        if session == nil {
            session = LanguageModelSession()
        }
        session?.prewarm()
    }

    func refine(system: String, user: String, fallback transcript: String) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            if case .unavailable(let reason) = SystemLanguageModel.default.availability {
                throw AppleRefinerError.unavailable(Self.describe(reason))
            }
            throw AppleRefinerError.unavailable("unknown reason")
        }

        // A fresh session carries the rules as instructions (the on-device
        // analogue of a system message) and starts with empty context, so no
        // prior dictation can leak in. The prewarmed session only served to
        // load the model; discard it now that the weights are hot.
        self.session = nil
        let session = LanguageModelSession(instructions: system)

        do {
            let response = try await session.respond(to: user)
            let refined = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.log.info("refined on-device chars=\(refined.count)")
            if refined.isEmpty || Refiner.isRefusal(refined) {
                return transcript
            }
            return refined
        } catch {
            // Guardrail refusals and generation errors must never lose the
            // dictation — the raw transcript wins.
            Self.log.warning("on-device generation failed: \(error.localizedDescription, privacy: .public); using raw")
            return transcript
        }
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "this Mac doesn't support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            "enable Apple Intelligence in System Settings"
        case .modelNotReady:
            "the model is still downloading"
        @unknown default:
            "unavailable"
        }
    }
}
