import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        if window == nil {
            let contentView = SettingsView(appState: appState)
            let hostingController = NSHostingController(rootView: contentView)
            // Let SwiftUI drive the title and the unified toolbar, so the
            // sidebar extends under the title bar like System Settings.
            hostingController.sceneBridgingOptions = [.title, .toolbars]
            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            // The bridged title only arrives on a pane change; seed the first.
            window.title = SettingsPane.general.title
            window.setContentSize(NSSize(width: 720, height: 540))
            window.contentMinSize = NSSize(width: 640, height: 440)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
