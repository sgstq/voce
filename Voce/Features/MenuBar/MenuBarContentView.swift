import AppKit
import SwiftUI

/// A short native menu: what Voce is doing, the one next step if setup is
/// unfinished, Settings and Quit. Permission details live in Settings.
struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Text(appState.statusLine)

        if appState.needsSetup {
            Button("Finish Setting Up…") {
                appState.openOnboarding()
            }
        }

        if let configError = appState.configError {
            Text(configError)
        }

        Divider()

        Button("Settings…") {
            appState.openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Voce") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
