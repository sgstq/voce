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
    /// Profile 1's backend needs an API key and none is stored.
    @Published private(set) var transcriptionKeyMissing = false
    /// A just-added profile whose page should start recording its keys.
    @Published var profileAwaitingKeys: UUID?

    let dictation: DictationCoordinator

    private let configStore: ConfigStore
    private let keychainStore: KeychainStore
    private let settingsWindowController = SettingsWindowController()
    private let onboardingWindowController = OnboardingWindowController()
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
        refreshKeyState()

        // NSApp is only safe to touch once the app has finished launching.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyAppearance()
            if self.needsSetup {
                self.openOnboarding()
            }
        }
    }

    /// Latest config, readable from the coordinator's escaping provider.
    private let configBox: ConfigBox

    /// Permissions or the transcription key still stand between the user
    /// and a first dictation.
    var needsSetup: Bool {
        !permissionState.isReadyForPhaseZero || transcriptionKeyMissing
    }

    var menuBarSystemImage: String {
        switch dictation.phase {
        case .recording:
            return "waveform.circle.fill"
        case .finalizing, .refining:
            return "ellipsis.circle"
        case .idle:
            return needsSetup ? "waveform.badge.exclamationmark" : "waveform"
        }
    }

    var statusLine: String {
        if let hotkeyError = dictation.hotkeyError {
            return hotkeyError
        }
        switch dictation.phase {
        case .idle:
            if needsSetup { return "Voce needs a few things to start" }
            let active = config.activeProfiles
            if active.count > 1 { return "Hold a profile's keys to dictate" }
            if let hotkey = active.first?.hotkey { return "Hold \(hotkey.displayName) to dictate" }
            if config.profiles.allSatisfy({ !$0.isEnabled }) { return "Every profile is off" }
            return "Set push-to-talk keys in Settings"
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

    func openOnboarding() {
        onboardingWindowController.show(appState: self)
    }

    func updateConfig(_ update: (inout AppConfig) -> Void) {
        let previous = config
        update(&config)
        configBox.value = config
        saveConfig()
        if config.hotkeyBindings != previous.hotkeyBindings {
            dictation.updateHotkeyBindings()
        }
        if config.primaryProfile.transcriptionBackend != previous.primaryProfile.transcriptionBackend {
            refreshKeyState()
        }
        if config.theme != previous.theme {
            applyAppearance()
        }
    }

    /// Settings and onboarding follow the theme; the dictation overlay is
    /// always dark, like a HUD.
    private func applyAppearance() {
        switch config.theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Profiles

    func updateProfile(_ id: UUID, _ update: (inout DictationProfile) -> Void) {
        guard let index = config.profiles.firstIndex(where: { $0.id == id }) else { return }
        updateConfig { update(&$0.profiles[index]) }
    }

    /// Adds a copy of profile 1 with no keys, so its engine and API keys
    /// already work; its page then asks for keys straight away.
    @discardableResult
    func addProfile() -> UUID {
        var profile = config.primaryProfile
        profile.id = UUID()
        profile.name = "Profile \(config.profiles.count + 1)"
        profile.isEnabled = true
        profile.hotkey = nil
        updateConfig { $0.profiles.append(profile) }
        profileAwaitingKeys = profile.id
        return profile.id
    }

    /// Profile 1 stays: onboarding and the setup badge rely on it.
    func removeProfile(_ id: UUID) {
        guard config.profiles.first?.id != id else { return }
        updateConfig { $0.profiles.removeAll { $0.id == id } }
    }

    /// Why `spec` can't be used by profile `id`, or nil when it can. A
    /// profile that is off keeps its keys, so turning it back on never clashes.
    func hotkeyConflict(for spec: HotkeySpec, profile id: UUID) -> String? {
        guard let owner = config.profiles.first(where: { $0.id != id && $0.hotkey?.keys == spec.keys }) else {
            return nil
        }
        let ownerName = owner.displayName.map { "“\($0)”" } ?? "another profile"
        let state = owner.isEnabled ? "" : ", which is off"
        return "\(spec.displayName) is already used by \(ownerName)\(state)."
    }

    /// Settings pauses push-to-talk while it records new keys.
    func setHotkeysSuspended(_ suspended: Bool) {
        dictation.setHotkeysSuspended(suspended)
    }

    private func refreshKeyState() {
        guard let account = config.primaryProfile.transcriptionBackend.keychainAccount else {
            transcriptionKeyMissing = false
            return
        }
        let stored = (try? keychainStore.read(account: account)) ?? nil
        transcriptionKeyMissing = stored?.isEmpty ?? true
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
        let current = PermissionState.current()
        if current != permissionState {
            permissionState = current
        }
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

    func openMicrophoneSettings() {
        PermissionState.openMicrophoneSettings()
    }

    func requestAccessibilityAccess() {
        PermissionState.requestAccessibilityPrompt()
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        PermissionState.openAccessibilitySettings()
        refreshPermissions()
    }

    func requestScreenRecordingAccess() {
        PermissionState.requestScreenRecordingPrompt()
        refreshPermissions()
    }

    func openScreenRecordingSettings() {
        PermissionState.openScreenRecordingSettings()
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
        refreshKeyState()
    }

    /// State of the on-device speech model per language, since profiles can
    /// dictate in different ones. Missing while a refresh is in flight
    /// ("Checking…" in Settings).
    @Published private(set) var appleSpeechModelStates: [String: AppleSpeechAssets.ModelState] = [:]
    private var appleSpeechTasks: [String: Task<Void, Never>] = [:]

    func refreshAppleSpeechModel(language: String) {
        appleSpeechTasks[language]?.cancel()
        appleSpeechModelStates[language] = nil
        appleSpeechTasks[language] = Task { [weak self] in
            let state = await AppleSpeechAssets.state(for: language)
            guard !Task.isCancelled else { return }
            self?.appleSpeechModelStates[language] = state
        }
    }

    func downloadAppleSpeechModel(language: String) {
        appleSpeechTasks[language]?.cancel()
        appleSpeechModelStates[language] = .downloading
        appleSpeechTasks[language] = Task { [weak self] in
            do {
                try await AppleSpeechAssets.download(for: language)
            } catch {
                guard !Task.isCancelled else { return }
                self?.appleSpeechModelStates[language] = .failed(error.localizedDescription)
                return
            }
            let state = await AppleSpeechAssets.state(for: language)
            guard !Task.isCancelled else { return }
            self?.appleSpeechModelStates[language] = state
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
