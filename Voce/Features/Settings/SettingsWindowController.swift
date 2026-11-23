import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

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
            window.title = "General"
            window.setContentSize(NSSize(width: 720, height: 540))
            window.contentMinSize = NSSize(width: 640, height: 440)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak appState] _ in
                MainActor.assumeIsolated {
                    // A key recording left open must not keep push-to-talk paused.
                    HotkeyRecorder.cancelActive()
                    appState?.setHotkeysSuspended(false)
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
