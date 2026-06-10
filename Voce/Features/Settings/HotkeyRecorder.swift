import AppKit

/// Captures the next key press inside the settings window and turns it into
/// a `HotkeySpec`. Local event monitors only see our own app's events, so
/// recording needs no extra permissions. Esc cancels; Caps Lock is rejected
/// because it toggles rather than holds.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var notice: String?

    private var monitor: Any?
    private var onCapture: ((HotkeySpec) -> Void)?

    // The local-monitor closure cannot capture this @MainActor object
    // directly under strict concurrency, so it reaches the active recorder
    // through a main-actor static.
    private static weak var activeRecorder: HotkeyRecorder?

    func begin(onCapture: @escaping (HotkeySpec) -> Void) {
        cancel()
        self.onCapture = onCapture
        self.isRecording = true
        self.notice = nil
        Self.activeRecorder = self

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Local monitors fire on the main thread.
            let type = event.type
            let keyCode = UInt16(event.keyCode)
            let flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                HotkeyRecorder.activeRecorder?.handle(type: type, keyCode: keyCode, flags: flags) ?? false
            }
            return consumed ? nil : event
        }
    }

    func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onCapture = nil
        isRecording = false
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
    }

    /// Returns true when the event was consumed by recording.
    private func handle(
        type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard isRecording else { return false }

        switch type {
        case .keyDown:
            if keyCode == KeyCodes.escape {
                cancel()
            } else {
                capture(HotkeySpec(capturedKeyCode: keyCode))
            }
            return true

        case .flagsChanged:
            if keyCode == KeyCodes.capsLock {
                cancel()
                notice = "Caps Lock toggles instead of holding, so it can't be the push-to-talk key."
                return true
            }
            guard let nsModifier = KeyCodes.nsModifier(for: keyCode),
                  flags.contains(nsModifier) else {
                // Modifier release (or an unusable modifier) — ignore quietly.
                return true
            }
            capture(HotkeySpec(capturedKeyCode: keyCode))
            return true

        default:
            return false
        }
    }

    private func capture(_ spec: HotkeySpec) {
        let callback = onCapture
        cancel()
        callback?(spec)
    }
}
