import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Voce", systemImage: "waveform")
                .font(.headline)

            Text(appState.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Settings") {
                appState.openSettings()
            }

            Divider()

            PermissionLine(title: "Microphone", value: appState.permissionState.microphone.label)
            PermissionLine(
                title: "Accessibility",
                value: appState.permissionState.accessibilityTrusted ? "Allowed" : "Needs access"
            )

            Button("Request Microphone") {
                appState.requestMicrophoneAccess()
            }

            Button("Open Accessibility Settings") {
                appState.openAccessibilitySettings()
            }

            Button("Refresh Permissions") {
                appState.refreshPermissions()
            }

            if let configError = appState.configError {
                Divider()
                Text(configError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }
}

private struct PermissionLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
