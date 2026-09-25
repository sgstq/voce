import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        if window == nil {
            let hostingController = NSHostingController(rootView: OnboardingView(appState: appState) { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Welcome to Voce"
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 600))
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// First run: microphone, Accessibility, a way to transcribe, then a first
/// dictation. Each step ticks itself off as the system reports the grant.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    let onDone: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 36)
                .padding(.bottom, 8)

            Form {
                Section {
                    PermissionRow(
                        title: "Microphone",
                        detail: "Voce listens only while you hold your key.",
                        isGranted: appState.permissionState.microphone == .authorized,
                        actionTitle: microphoneActionTitle,
                        action: microphoneAction
                    )
                    PermissionRow(
                        title: "Accessibility",
                        detail: "Lets Voce type into other apps and read the text around your cursor.",
                        isGranted: appState.permissionState.accessibilityTrusted,
                        actionTitle: "Allow…",
                        action: { appState.requestAccessibilityAccess() }
                    )
                }

                Section {
                    Picker("Transcribe with", selection: appState.binding(\.transcriptionBackend)) {
                        ForEach(TranscriptionBackend.allCases) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    if let account = appState.config.transcriptionBackend.keychainAccount {
                        APIKeyField(
                            title: "\(appState.config.transcriptionBackend.keyLabel) API key",
                            account: account,
                            load: { appState.loadTranscriptionKey(for: appState.config.transcriptionBackend) },
                            save: { appState.saveTranscriptionKey($0, for: appState.config.transcriptionBackend) }
                        )
                    }
                } footer: {
                    Text(transcriptionFooter)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .frame(width: 520, height: 600)
        .tint(appState.config.accent.color)
        .task { await appState.watchPermissions() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Welcome to Voce")
                .font(.system(size: 26, weight: .semibold))
            Text("Hold a key, speak, and your words appear wherever you type.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if appState.needsSetup {
            HStack {
                Text("You can finish this later from the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Later") { onDone() }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("You're set. Hold")
                KeyCap(label: appState.config.hotkey.displayName)
                Text("anywhere and speak.")
                Spacer()
                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var microphoneActionTitle: String {
        appState.permissionState.microphone == .notDetermined ? "Allow" : "Open Settings…"
    }

    /// The system prompt appears only once; after a denial the switch
    /// lives in System Settings.
    private func microphoneAction() {
        if appState.permissionState.microphone == .notDetermined {
            appState.requestMicrophoneAccess()
        } else {
            appState.openMicrophoneSettings()
        }
    }

    private var transcriptionFooter: String {
        switch appState.config.transcriptionBackend {
        case .openAIRealtime:
            "Fastest and most accurate. Your key stays in the macOS Keychain."
        case .deepgram:
            "Streaming transcription from Deepgram. Your key stays in the macOS Keychain."
        case .appleOnDevice:
            "Runs entirely on this Mac — no account, nothing leaves your computer."
        }
    }
}
