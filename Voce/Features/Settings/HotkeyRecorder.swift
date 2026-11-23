import AppKit

/// Captures the next key or key combination inside the settings window and
/// turns it into a `HotkeySpec`. A regular key is taken on press, together
/// with any modifiers held (⌃ + ⌥ + D); modifiers alone are taken when the
/// first of them is released, so Right ⌥ + ⇧ can be pressed one at a time.
/// Local event monitors only see our own app's events, so recording needs
/// no extra permissions. Esc cancels; Caps Lock is rejected because it
/// toggles rather than holds.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var notice: String?

    private var monitor: Any?
    private var validate: ((HotkeySpec) -> String?)?
    private var onCapture: ((HotkeySpec) -> Void)?
    private var heldModifiers: Set<UInt16> = []
    /// Every modifier held since the last capture attempt.
    private var pressedModifiers: Set<UInt16> = []

    // The local-monitor closure cannot capture this @MainActor object
    // directly under strict concurrency, so it reaches the active recorder
    // through a main-actor static.
    private static weak var activeRecorder: HotkeyRecorder?

    /// `validate` returns why keys can't be used (already taken by another
    /// profile); recording then continues so another combination can be tried.
    func begin(validate: @escaping (HotkeySpec) -> String?, onCapture: @escaping (HotkeySpec) -> Void) {
        cancel()
        self.validate = validate
        self.onCapture = onCapture
        self.isRecording = true
        self.notice = nil
        self.heldModifiers = KeyCodes.heldModifiers(rawFlags: UInt64(NSEvent.modifierFlags.rawValue))
        self.pressedModifiers = []
        Self.activeRecorder = self

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Local monitors fire on the main thread.
            let type = event.type
            let keyCode = UInt16(event.keyCode)
            let rawFlags = UInt64(event.modifierFlags.rawValue)
            let characters = type == .keyDown ? event.charactersIgnoringModifiers : nil
            let consumed = MainActor.assumeIsolated {
                HotkeyRecorder.activeRecorder?.handle(
                    type: type,
                    keyCode: keyCode,
                    rawFlags: rawFlags,
                    characters: characters
                ) ?? false
            }
            return consumed ? nil : event
        }
    }

    func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        validate = nil
        onCapture = nil
        isRecording = false
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
    }

    static func cancelActive() {
        activeRecorder?.cancel()
    }

    /// Returns true when the event was consumed by recording.
    private func handle(
        type: NSEvent.EventType,
        keyCode: UInt16,
        rawFlags: UInt64,
        characters: String?
    ) -> Bool {
        guard isRecording else { return false }

        switch type {
        case .keyDown:
            if keyCode == KeyCodes.escape, heldModifiers.isEmpty {
                cancel()
                return true
            }
            // Modifiers come from the tracked state, not this event's flags:
            // arrow and function keys carry the Fn flag on their own.
            let name = KeyCodes.displayName(for: keyCode, characters: characters)
            attempt(HotkeySpec(capturedKeyCodes: heldModifiers.union([keyCode]), keyNames: [keyCode: name]))
            return true

        case .flagsChanged:
            if keyCode == KeyCodes.capsLock {
                cancel()
                notice = "Caps Lock toggles instead of holding, so it can't be a push-to-talk key."
                return true
            }
            let modifiers = KeyCodes.heldModifiers(rawFlags: rawFlags, changedKeyCode: keyCode)
            let released = !heldModifiers.subtracting(modifiers).isEmpty
            heldModifiers = modifiers
            if !released {
                pressedModifiers.formUnion(modifiers)
            } else if !pressedModifiers.isEmpty {
                attempt(HotkeySpec(capturedKeyCodes: pressedModifiers))
            }
            return true

        default:
            return false
        }
    }

    private func attempt(_ spec: HotkeySpec) {
        pressedModifiers = []
        if let problem = validate?(spec) {
            notice = problem
            return
        }
        let callback = onCapture
        cancel()
        notice = nil
        callback?(spec)
    }
}
