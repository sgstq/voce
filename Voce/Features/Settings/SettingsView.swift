import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @StateObject private var hotkeyRecorder = HotkeyRecorder()
    @State private var apiKey = ""
    @State private var refinementKey = ""

    var body: some View {
        Form {
            Section("Activation") {
                LabeledContent("Push-to-talk key") {
                    HStack(spacing: 10) {
                        Text(appState.config.hotkey.displayName)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.15))
                            )

                        Button(hotkeyRecorder.isRecording ? "Press a key… (Esc cancels)" : "Record Key") {
                            if hotkeyRecorder.isRecording {
                                hotkeyRecorder.cancel()
                            } else {
                                hotkeyRecorder.begin { spec in
                                    appState.updateConfig { $0.hotkey = spec }
                                }
                            }
                        }
                    }
                }

                if let notice = hotkeyRecorder.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Hold the key to dictate. Function keys and modifiers (Fn, ⌥, ⌘…) work best — ordinary typing keys also type while held.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Insertion mode", selection: binding(\.insertionMode)) {
                    ForEach(InsertionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Transcription") {
                Picker("Backend", selection: binding(\.transcriptionBackend)) {
                    ForEach(TranscriptionBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }

                Picker("Dictation language", selection: binding(\.language)) {
                    ForEach(DictationLanguages.pickerOptions(including: appState.config.language), id: \.self) { code in
                        Text(DictationLanguages.displayName(for: code)).tag(code)
                    }
                }
                Text("Used by both recognition and refinement. Automatic detects the spoken language — including switching mid-dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Realtime model",
                    text: binding(\.realtimeModel)
                )

                Picker("Realtime delay", selection: binding(\.realtimeDelay)) {
                    ForEach(RealtimeDelay.allCases) { delay in
                        Text(delay.label).tag(delay)
                    }
                }

                SecureField("OpenAI API key", text: $apiKey)

                HStack {
                    Button("Save Key") {
                        appState.saveAPIKey(apiKey)
                    }

                    Button("Clear Key") {
                        apiKey = ""
                        appState.saveAPIKey("")
                    }

                    if let keychainMessage = appState.keychainMessage {
                        Text(keychainMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Refinement") {
                Toggle(
                    "Enable refinement",
                    isOn: binding(\.refinementEnabled)
                )

                Picker("Provider", selection: providerBinding) {
                    ForEach(RefinementProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }

                if appState.config.refinementProvider.isCloud {
                    TextField(
                        "Refinement model",
                        text: binding(\.refinementModel)
                    )

                    if appState.config.refinementProvider == .openAI {
                        Text("Uses the same OpenAI key as transcription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField(
                            "\(appState.config.refinementProvider.label) API key",
                            text: $refinementKey
                        )
                        HStack {
                            Button("Save Key") {
                                appState.saveRefinementKey(refinementKey, for: appState.config.refinementProvider)
                            }
                            Button("Clear Key") {
                                refinementKey = ""
                                appState.saveRefinementKey("", for: appState.config.refinementProvider)
                            }
                        }
                    }
                } else {
                    LabeledContent("On-device model", value: AppleRefiner.availabilityDescription())
                }
            }

            Section("Context") {
                Toggle(
                    "Capture text context",
                    isOn: binding(\.captureContext)
                )

                Toggle(
                    "Capture screenshots",
                    isOn: binding(\.captureScreenshots)
                )
            }

            Section("Appearance") {
                Picker("Theme", selection: binding(\.theme)) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }

                Picker("Accent", selection: binding(\.accent)) {
                    ForEach(AccentColor.allCases) { accent in
                        Text(accent.label).tag(accent)
                    }
                }
            }

            Section("General") {
                Toggle(
                    "Start Voce at login",
                    isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )
                )

                if let notice = appState.launchAtLoginNotice {
                    HStack {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Login Items") {
                            appState.openLoginItemsSettings()
                        }
                    }
                }
            }

            Section("Permissions") {
                LabeledContent("Microphone", value: appState.permissionState.microphone.label)
                LabeledContent(
                    "Accessibility",
                    value: appState.permissionState.accessibilityTrusted ? "Allowed" : "Needs access"
                )

                HStack {
                    Button("Request Microphone") {
                        appState.requestMicrophoneAccess()
                    }

                    Button("Request Accessibility") {
                        appState.requestAccessibilityAccess()
                    }

                    Button("Open Accessibility Settings") {
                        appState.openAccessibilitySettings()
                    }
                }
            }

            if let configError = appState.configError {
                Section("Config") {
                    Text(configError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            apiKey = appState.loadAPIKey()
            refinementKey = appState.loadRefinementKey(for: appState.config.refinementProvider)
            appState.refreshPermissions()
            appState.refreshLaunchAtLogin()
        }
    }

    /// Switching provider also swaps the model field to the new provider's
    /// default (unless the user customized it), and loads that provider's key.
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
                refinementKey = appState.loadRefinementKey(for: newProvider)
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppConfig, Value>) -> Binding<Value> {
        Binding(
            get: { appState.config[keyPath: keyPath] },
            set: { value in
                appState.updateConfig { config in
                    config[keyPath: keyPath] = value
                }
            }
        )
    }
}
