import AppKit
import AVFoundation
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var permissionState: PermissionState
    @Published private(set) var configError: String?
    @Published private(set) var keychainMessage: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginNotice: String?

    let dictation: DictationCoordinator

    private let configStore: ConfigStore
    private let keychainStore: KeychainStore
    private let settingsWindowController = SettingsWindowController()
    private var dictationChanges: AnyCancellable?

    init(
        configStore: ConfigStore = ConfigStore(),
        keychainStore: KeychainStore = KeychainStore()
    ) {
        self.configStore = configStore
        self.keychainStore = keychainStore
        self.permissionState = PermissionState.current()

        var loadedConfig: AppConfig
        var loadError: String?
        do {
            loadedConfig = try configStore.load()
        } catch {
            loadedConfig = AppConfig()
            loadError = error.localizedDescription
        }
        self.config = loadedConfig
        self.configError = loadError

        let configBox = ConfigBox(loadedConfig)
        self.configBox = configBox
        self.dictation = DictationCoordinator(
            configProvider: { configBox.value },
            apiKeyProvider: { backend in
                guard let account = backend.keychainAccount else { return nil }
                return try keychainStore.read(account: account)
            },
            refinementKeyProvider: { provider in
                guard let account = provider.keychainAccount else { return nil }
                return try keychainStore.read(account: account)
            }
        )

        // Surface dictation phase changes (menu-bar icon) through this object.
        dictationChanges = dictation.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        dictation.startHotkey()
    }

    /// Latest config, readable from the coordinator's escaping provider.
    private let configBox: ConfigBox

    var menuBarSystemImage: String {
        switch dictation.phase {
        case .recording:
            return "record.circle.fill"
        case .finalizing, .refining:
            return "ellipsis.circle"
        case .idle:
            return permissionState.isReadyForPhaseZero ? "waveform.circle" : "waveform.circle.fill"
        }
    }

    var statusLine: String {
        if let hotkeyError = dictation.hotkeyError {
            return hotkeyError
        }
        switch dictation.phase {
        case .idle:
            return "Hold \(config.hotkey.displayName) to dictate"
        case .recording:
            return "Listening…"
        case .finalizing:
            return "Finalizing…"
        case .refining:
            return "Polishing…"
        }
    }

    func openSettings() {
        settingsWindowController.show(appState: self)
    }

    func updateConfig(_ update: (inout AppConfig) -> Void) {
        let previousHotkey = config.hotkey
        update(&config)
        configBox.value = config
        saveConfig()
        if config.hotkey != previousHotkey {
            dictation.restartHotkeyIfNeeded()
        }
    }

    func saveConfig() {
        do {
            try configStore.save(config)
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
    }

    func refreshPermissions() {
        permissionState = PermissionState.current()
        if permissionState.accessibilityTrusted, !dictation.isHotkeyRunning {
            dictation.restartHotkeyIfNeeded()
        }
    }

    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
            }
        }
    }

    func requestAccessibilityAccess() {
        PermissionState.requestAccessibilityPrompt()
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        PermissionState.openAccessibilitySettings()
        refreshPermissions()
    }

    func loadTranscriptionKey(for backend: TranscriptionBackend) -> String {
        guard let account = backend.keychainAccount else { return "" }
        do {
            keychainMessage = nil
            return try keychainStore.read(account: account) ?? ""
        } catch {
            keychainMessage = error.localizedDescription
            return ""
        }
    }

    func saveTranscriptionKey(_ value: String, for backend: TranscriptionBackend) {
        guard let account = backend.keychainAccount else { return }
        do {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            try keychainStore.save(trimmed, account: account)
            keychainMessage = trimmed.isEmpty ? "API key removed." : "API key saved in Keychain."
        } catch {
            keychainMessage = error.localizedDescription
        }
    }

    /// State of the on-device speech model for the configured language.
    /// Nil while a refresh is in flight ("Checking…" in Settings).
    @Published private(set) var appleSpeechModelState: AppleSpeechAssets.ModelState?
    private var appleSpeechTask: Task<Void, Never>?

    func refreshAppleSpeechModel() {
        appleSpeechTask?.cancel()
        appleSpeechModelState = nil
        let language = config.language
        appleSpeechTask = Task { [weak self] in
            let state = await AppleSpeechAssets.state(for: language)
            guard !Task.isCancelled else { return }
            self?.appleSpeechModelState = state
        }
    }

    func downloadAppleSpeechModel() {
        appleSpeechTask?.cancel()
        appleSpeechModelState = .downloading
        let language = config.language
        appleSpeechTask = Task { [weak self] in
            do {
                try await AppleSpeechAssets.download(for: language)
            } catch {
                guard !Task.isCancelled else { return }
                self?.appleSpeechModelState = .failed(error.localizedDescription)
                return
            }
            let state = await AppleSpeechAssets.state(for: language)
            guard !Task.isCancelled else { return }
            self?.appleSpeechModelState = state
        }
    }

    /// Login-item state lives in macOS (System Settings → Login Items), not
    /// in our config — reading the live status keeps the toggle honest even
    /// when the user changes it behind our back.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginNotice = nil
        } catch {
            launchAtLoginNotice = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginNotice = "Approve Voce under System Settings → General → Login Items."
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func loadRefinementKey(for provider: RefinementProvider) -> String {
        guard let account = provider.keychainAccount else { return "" }
        do {
            keychainMessage = nil
            return try keychainStore.read(account: account) ?? ""
        } catch {
            keychainMessage = error.localizedDescription
            return ""
        }
    }

    func saveRefinementKey(_ value: String, for provider: RefinementProvider) {
        guard let account = provider.keychainAccount else { return }
        do {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            try keychainStore.save(trimmed, account: account)
            keychainMessage = trimmed.isEmpty
                ? "\(provider.label) key removed."
                : "\(provider.label) key saved in Keychain."
        } catch {
            keychainMessage = error.localizedDescription
        }
    }
}

/// Reference box so escaping providers always read the latest config without
/// retaining AppState.
@MainActor
private final class ConfigBox {
    var value: AppConfig

    init(_ value: AppConfig) {
        self.value = value
    }
}
