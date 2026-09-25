import SwiftUI

struct GeneralPane: View {
    @ObservedObject var appState: AppState
    @StateObject private var hotkeyRecorder = HotkeyRecorder()

    var body: some View {
        Form {
            if let configError = appState.configError {
                Section {
                    Label(configError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Push-to-talk key") {
                    HotkeyField(appState: appState, recorder: hotkeyRecorder)
                }
            } footer: {
                if let notice = hotkeyRecorder.notice {
                    Text(notice).foregroundStyle(.orange)
                } else {
                    Text("Hold the key anywhere to dictate and release to insert. Fn, ⌥ or a spare function key work best — letter keys also type while held.")
                }
            }

            Section {
                Toggle("Show live transcript", isOn: appState.binding(\.showLiveTranscript))
                Picker("Insert text with", selection: appState.binding(\.insertionMode)) {
                    ForEach(InsertionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } footer: {
                Text("Auto types the text as keystrokes and never touches your clipboard.")
            }

            Section {
                Picker("Appearance", selection: appState.binding(\.theme)) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent colour") {
                    AccentPicker(selection: appState.binding(\.accent))
                }
            }

            Section {
                Toggle("Open Voce at login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                if let notice = appState.launchAtLoginNotice {
                    LabeledContent {
                        Button("Open Login Items…") { appState.openLoginItemsSettings() }
                    } label: {
                        Text(notice).foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { hotkeyRecorder.cancel() }
    }
}

struct TranscriptionPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: backendBinding) {
                    ForEach(TranscriptionBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
                Picker("Language", selection: appState.binding(\.language)) {
                    ForEach(DictationLanguages.pickerOptions(including: appState.config.language), id: \.self) { code in
                        Text(DictationLanguages.displayName(for: code)).tag(code)
                    }
                }
            } footer: {
                Text("Automatic detects the spoken language, including switches mid-sentence. The same setting guides Polish.")
            }

            engineSection

            Section("Advanced") {
                switch appState.config.transcriptionBackend {
                case .openAIRealtime:
                    TextField("Model", text: appState.binding(\.realtimeModel))
                    Picker("Latency", selection: appState.binding(\.realtimeDelay)) {
                        ForEach(RealtimeDelay.allCases) { delay in
                            Text(delay.label).tag(delay)
                        }
                    }
                case .deepgram:
                    TextField("Model", text: appState.binding(\.deepgramModel))
                case .appleOnDevice:
                    LabeledContent("Model", value: "Apple SpeechAnalyzer")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshModelIfNeeded() }
        .onChange(of: appState.config.language) {
            // The on-device model is per-language; re-check when it changes.
            refreshModelIfNeeded()
        }
    }

    @ViewBuilder
    private var engineSection: some View {
        let backend = appState.config.transcriptionBackend
        if let account = backend.keychainAccount {
            Section {
                APIKeyField(
                    title: "\(backend.keyLabel) API key",
                    account: account,
                    load: { appState.loadTranscriptionKey(for: backend) },
                    save: { appState.saveTranscriptionKey($0, for: backend) }
                )
            } footer: {
                Text(appState.keychainMessage ?? "Stored in the macOS Keychain, never in a file.")
            }
        } else {
            Section {
                LabeledContent("On-device model") {
                    HStack(spacing: 10) {
                        Text(appState.appleSpeechModelState?.label ?? "Checking…")
                            .foregroundStyle(.secondary)
                        if appState.appleSpeechModelState?.offersDownload == true {
                            Button("Download") { appState.downloadAppleSpeechModel() }
                        }
                    }
                }
            } footer: {
                Text("Runs entirely on this Mac — no key, and audio never leaves your computer.")
            }
        }
    }

    private func refreshModelIfNeeded() {
        if appState.config.transcriptionBackend == .appleOnDevice {
            appState.refreshAppleSpeechModel()
        }
    }

    /// Switching to Apple re-checks the on-device model.
    private var backendBinding: Binding<TranscriptionBackend> {
        Binding(
            get: { appState.config.transcriptionBackend },
            set: { newBackend in
                appState.updateConfig { $0.transcriptionBackend = newBackend }
                refreshModelIfNeeded()
            }
        )
    }
}

struct PolishPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Polish text before inserting", isOn: appState.binding(\.refinementEnabled))
            } footer: {
                Text("Fixes punctuation, drops filler words and matches the style of the text around your cursor.")
            }

            Section {
                Picker("Provider", selection: providerBinding) {
                    ForEach(RefinementProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                providerDetail
            }
            .disabled(!appState.config.refinementEnabled)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var providerDetail: some View {
        let provider = appState.config.refinementProvider
        if provider.isCloud {
            TextField("Model", text: appState.binding(\.refinementModel))
            if provider == .openAI, appState.config.transcriptionBackend == .openAIRealtime {
                LabeledContent("API key", value: "Shared with Transcription")
            } else if let account = provider.keychainAccount {
                APIKeyField(
                    title: "\(provider.label) API key",
                    account: account,
                    load: { appState.loadRefinementKey(for: provider) },
                    save: { appState.saveRefinementKey($0, for: provider) }
                )
            }
        } else {
            LabeledContent("On-device model", value: AppleRefiner.availabilityDescription())
        }
    }

    /// Switching provider also swaps the model field to the new provider's
    /// default, unless the user customized it.
    private var providerBinding: Binding<RefinementProvider> {
        Binding(
            get: { appState.config.refinementProvider },
            set: { newProvider in
                appState.updateConfig { config in
                    let wasDefaultModel = config.refinementModel == config.refinementProvider.defaultModel
                        || config.refinementModel.isEmpty
                    config.refinementProvider = newProvider
                    if wasDefaultModel {
                        config.refinementModel = newProvider.defaultModel
                    }
                }
            }
        )
    }
}

struct ContextPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Use the text around your cursor", isOn: appState.binding(\.captureContext))
            } footer: {
                Text("Helps Polish match tone, names and formatting. Read through Accessibility at the moment you release the key.")
            }

            Section {
                Picker("Read the active window", selection: appState.binding(\.screenContext)) {
                    ForEach(ScreenContextMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if appState.config.screenContext != .off,
                   !appState.permissionState.screenRecordingGranted {
                    PermissionRow(
                        title: "Screen Recording",
                        detail: "Needed to read the active window.",
                        isGranted: false,
                        actionTitle: "Allow…"
                    ) {
                        appState.requestScreenRecordingAccess()
                        appState.openScreenRecordingSettings()
                    }
                }
            } footer: {
                Text(appState.config.screenContext.caption)
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionsPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Microphone",
                    detail: "Records only while you hold your push-to-talk key.",
                    isGranted: appState.permissionState.microphone == .authorized,
                    actionTitle: appState.permissionState.microphone == .notDetermined ? "Allow" : "Open Settings…"
                ) {
                    if appState.permissionState.microphone == .notDetermined {
                        appState.requestMicrophoneAccess()
                    } else {
                        appState.openMicrophoneSettings()
                    }
                }
                PermissionRow(
                    title: "Accessibility",
                    detail: "Detects your key anywhere, types the text and reads the text around your cursor.",
                    isGranted: appState.permissionState.accessibilityTrusted,
                    actionTitle: "Allow…"
                ) {
                    appState.requestAccessibilityAccess()
                }
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Optional. Only used when Context reads the active window.",
                    isGranted: appState.permissionState.screenRecordingGranted,
                    actionTitle: "Allow…"
                ) {
                    appState.requestScreenRecordingAccess()
                    appState.openScreenRecordingSettings()
                }
            }
        }
        .formStyle(.grouped)
        .task { await appState.watchPermissions() }
    }
}
