import SwiftUI

@main
struct VoceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Voce", systemImage: appState.menuBarSystemImage) {
            MenuBarContentView(appState: appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
