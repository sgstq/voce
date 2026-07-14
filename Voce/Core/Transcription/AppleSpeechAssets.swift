import Foundation
import Speech

/// On-device speech model assets for the Apple transcription backend.
/// SpeechTranscriber models are downloaded and managed by the system through
/// `AssetInventory`; one asset serves a whole locale.
enum AppleSpeechAssets {
    enum ModelState: Equatable {
        case unsupported
        case notDownloaded
        case downloading
        case installed
        case failed(String)

        var label: String {
            switch self {
            case .unsupported: "Not supported for this language"
            case .notDownloaded: "Not downloaded"
            case .downloading: "Downloading…"
            case .installed: "Installed"
            case .failed(let message): message
            }
        }

        var offersDownload: Bool {
            switch self {
            case .notDownloaded, .failed: true
            case .unsupported, .downloading, .installed: false
            }
        }
    }

    /// The locale dictation should use, before checking device support.
    /// "Automatic" means the Mac's current locale — on-device recognition
    /// cannot detect the spoken language.
    static func preferredLocale(for language: String) -> Locale {
        if DictationLanguages.isAutomatic(language) {
            return Locale.current
        }
        return Locale(identifier: language.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Maps the configured language onto a locale SpeechTranscriber actually
    /// supports (e.g. "en" → "en-US"), or nil when unsupported.
    static func resolveLocale(for language: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: preferredLocale(for: language))
    }

    static func state(for language: String) async -> ModelState {
        guard let locale = await resolveLocale(for: language) else {
            return .unsupported
        }
        switch await AssetInventory.status(forModules: [transcriber(for: locale)]) {
        case .unsupported: return .unsupported
        case .supported: return .notDownloaded
        case .downloading: return .downloading
        case .installed: return .installed
        @unknown default: return .notDownloaded
        }
    }

    /// Downloads the model for the language. No-op when already installed
    /// (the framework returns no installation request).
    static func download(for language: String) async throws {
        guard let locale = await resolveLocale(for: language) else { return }
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber(for: locale)]
        ) {
            try await request.downloadAndInstall()
        }
    }

    /// A push-to-talk transcriber: volatile results drive the live preview.
    static func transcriber(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }
}
