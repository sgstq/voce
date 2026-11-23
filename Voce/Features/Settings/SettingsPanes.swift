import SwiftUI

struct GeneralPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            if let configError = appState.configError {
                Section {
                    Label(configError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
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
                Text("Shared by every profile. Auto types the text as keystrokes and never touches your clipboard.")
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
    }
}

/// Everything one profile does: its name and keys, how it transcribes,
/// polishes and reads context. API keys are per provider, so editing one
/// here changes it for every profile on that provider.
struct ProfilePane: View {
    @ObservedObject var appState: AppState
    let profileID: UUID
    @StateObject private var hotkeyRecorder = HotkeyRecorder()
    @State private var confirmingRemoval = false

    var body: some View {
        if let profile = appState.config.profile(id: profileID) {
            Form {
                keysSection(profile)
                TranscriptionSections(appState: appState, profile: profile)
                PolishSection(appState: appState, profile: profile)
                ContextSections(appState: appState, profile: profile)
                if profile.id != appState.config.primaryProfile.id {
                    removeSection(profile)
                }
            }
            .formStyle(.grouped)
            .onAppear(perform: recordKeysIfNew)
            .onDisappear {
                hotkeyRecorder.cancel()
                appState.setHotkeysSuspended(false)
            }
            .onChange(of: hotkeyRecorder.isRecording) { _, isRecording in
                appState.setHotkeysSuspended(isRecording)
            }
        }
    }

    private func keysSection(_ profile: DictationProfile) -> some View {
        Section {
            Toggle("Use this profile", isOn: appState.binding(profile: profileID, \.isEnabled))
            TextField("Name", text: appState.binding(profile: profileID, \.name))
            LabeledContent("Push-to-talk keys") {
                HotkeyField(
                    spec: profile.hotkey,
                    recorder: hotkeyRecorder,
                    validate: { appState.hotkeyConflict(for: $0, profile: profileID) },
                    onCapture: { spec in appState.updateProfile(profileID) { $0.hotkey = spec } }
                )
            }
        } footer: {
            if let notice = hotkeyRecorder.notice {
                Text(notice).foregroundStyle(.orange)
            } else if !profile.isEnabled {
                Text("Off: its keys do nothing until you turn it back on. They stay reserved for this profile.")
            } else {
                Text(
                    "Hold the keys anywhere to dictate and release to insert. Use one key like Right ⌥ or Fn, "
                        + "or a combination like Right ⌥ + ⇧. Letter keys also type while held."
                )
            }
        }
    }

    private func removeSection(_ profile: DictationProfile) -> some View {
        Section {
            Button("Remove Profile…", role: .destructive) {
                confirmingRemoval = true
            }
            .confirmationDialog(
                "Remove “\(profile.displayName ?? "Untitled")”?",
                isPresented: $confirmingRemoval
            ) {
                Button("Remove Profile", role: .destructive) {
                    appState.removeProfile(profileID)
                }
            } message: {
                Text("Its keys stop working. API keys stay in the Keychain for your other profiles.")
            }
        }
    }

    /// A profile added a moment ago asks for its keys right away.
    private func recordKeysIfNew() {
        guard appState.profileAwaitingKeys == profileID else { return }
        appState.profileAwaitingKeys = nil
        hotkeyRecorder.begin(
            validate: { appState.hotkeyConflict(for: $0, profile: profileID) },
            onCapture: { spec in appState.updateProfile(profileID) { $0.hotkey = spec } }
        )
    }
}

private struct TranscriptionSections: View {
    @ObservedObject var appState: AppState
    let profile: DictationProfile

    var body: some View {
        Section {
            Picker("Engine", selection: appState.binding(profile: profile.id, \.transcriptionBackend)) {
                ForEach(TranscriptionBackend.allCases) { backend in
                    Text(backend.label).tag(backend)
                }
            }
            Picker("Language", selection: appState.binding(profile: profile.id, \.language)) {
                ForEach(DictationLanguages.pickerOptions(including: profile.language), id: \.self) { code in
                    Text(DictationLanguages.displayName(for: code)).tag(code)
                }
            }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Automatic detects the spoken language, including switches mid-sentence. The same setting guides Polish.")
        }

        engineSection

        Section("Advanced") {
            switch profile.transcriptionBackend {
            case .openAIRealtime:
                TextField("Model", text: appState.binding(profile: profile.id, \.realtimeModel))
                Picker("Latency", selection: appState.binding(profile: profile.id, \.realtimeDelay)) {
                    ForEach(RealtimeDelay.allCases) { delay in
                        Text(delay.label).tag(delay)
                    }
                }
            case .deepgram:
                TextField("Model", text: appState.binding(profile: profile.id, \.deepgramModel))
            case .openRouter:
                TextField("Model", text: appState.binding(profile: profile.id, \.openRouterModel))
            case .appleOnDevice:
                LabeledContent("Model", value: "Apple SpeechAnalyzer")
            }
        }
    }

    @ViewBuilder
    private var engineSection: some View {
        let backend = profile.transcriptionBackend
        if let account = backend.keychainAccount {
            Section {
                APIKeyField(
                    title: "\(backend.keyLabel) API key",
                    account: account,
                    load: { appState.loadTranscriptionKey(for: backend) },
                    save: { appState.saveTranscriptionKey($0, for: backend) }
                )
            } footer: {
                Text(appState.keychainMessage ?? "Stored in the macOS Keychain, never in a file, and shared by every profile that uses \(backend.keyLabel).")
            }
        } else {
            let state = appState.appleSpeechModelStates[profile.language]
            Section {
                LabeledContent("On-device model") {
                    HStack(spacing: 10) {
                        Text(state?.label ?? "Checking…")
                            .foregroundStyle(.secondary)
                        if state?.offersDownload == true {
                            Button("Download") { appState.downloadAppleSpeechModel(language: profile.language) }
                        }
                    }
                }
            } footer: {
                Text("Runs entirely on this Mac — no key, and audio never leaves your computer.")
            }
            // The on-device model is per language; re-check when either changes.
            .task(id: profile.language) {
                appState.refreshAppleSpeechModel(language: profile.language)
            }
        }
    }
}

private struct PolishSection: View {
    @ObservedObject var appState: AppState
    let profile: DictationProfile

    var body: some View {
        Section {
            Toggle("Polish text before inserting", isOn: appState.binding(profile: profile.id, \.refinementEnabled))
            Group {
                Picker("Provider", selection: providerBinding) {
                    ForEach(RefinementProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                providerDetail
            }
            .disabled(!profile.refinementEnabled)
        } header: {
            Text("Polish")
        } footer: {
            Text("Fixes punctuation, drops filler words and matches the style of the text around your cursor.")
        }
    }

    @ViewBuilder
    private var providerDetail: some View {
        let provider = profile.refinementProvider
        if provider.isCloud {
            TextField("Model", text: appState.binding(profile: profile.id, \.refinementModel))
            if provider == .openAI, profile.transcriptionBackend == .openAIRealtime {
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
            get: { profile.refinementProvider },
            set: { newProvider in
                appState.updateProfile(profile.id) { profile in
                    let wasDefaultModel = profile.refinementModel == profile.refinementProvider.defaultModel
                        || profile.refinementModel.isEmpty
                    profile.refinementProvider = newProvider
                    if wasDefaultModel {
                        profile.refinementModel = newProvider.defaultModel
                    }
                }
            }
        )
    }
}

private struct ContextSections: View {
    @ObservedObject var appState: AppState
    let profile: DictationProfile

    var body: some View {
        Section {
            Toggle("Use the text around your cursor", isOn: appState.binding(profile: profile.id, \.captureContext))
        } header: {
            Text("Context")
        } footer: {
            Text("Helps Polish match tone, names and formatting. Read through Accessibility at the moment you release the keys.")
        }

        Section {
            Picker("Read the active window", selection: appState.binding(profile: profile.id, \.screenContext)) {
                ForEach(ScreenContextMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            if profile.screenContext != .off,
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
            Text(profile.screenContext.caption)
        }
    }
}

struct PermissionsPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Microphone",
                    detail: "Records only while you hold a profile's push-to-talk keys.",
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
