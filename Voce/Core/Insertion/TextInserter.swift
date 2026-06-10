import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Inserts text into the focused field of the frontmost app without touching
/// the clipboard. Synthesized Unicode keystrokes are the default path — the
/// Accessibility `kAXSelectedText` write reports success without inserting
/// anything in too many apps (Chromium/Electron fields especially), so it is
/// an explicit opt-in mode instead. A history-safe clipboard paste exists
/// only as an opt-in fallback (see docs/REQUIREMENTS.md → Text insertion).
@MainActor
struct TextInserter {
    enum InsertionError: LocalizedError {
        case accessibilityInsertionFailed
        case eventSourceUnavailable
        case accessibilityNotGranted

        var errorDescription: String? {
            switch self {
            case .accessibilityInsertionFailed:
                "The focused field does not accept Accessibility insertion."
            case .eventSourceUnavailable:
                "Could not create a keyboard event source."
            case .accessibilityNotGranted:
                "Enable Voce in System Settings → Privacy & Security → Accessibility to insert text."
            }
        }
    }

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "insertion")

    func insert(_ text: String, mode: InsertionMode) async throws {
        guard !text.isEmpty else { return }
        Self.log.notice("insert mode=\(mode.rawValue, privacy: .public) chars=\(text.count)")

        // Posting CGEvents (and AX writes) silently no-op without the
        // Accessibility grant — fail loudly instead of typing into the void.
        // (A listen-only hotkey tap can work on Input Monitoring alone, so a
        // firing hotkey does NOT imply this permission.)
        guard AXIsProcessTrusted() else {
            Self.log.error("insert blocked: Accessibility not granted")
            throw InsertionError.accessibilityNotGranted
        }

        switch mode {
        case .auto, .keystrokes:
            try await typeUnicodeKeystrokes(text)
        case .accessibility:
            guard insertViaAccessibility(text) else {
                throw InsertionError.accessibilityInsertionFailed
            }
        case .clipboardFallback:
            try await pasteViaTransientClipboard(text)
        }
    }

    // MARK: Synthesized Unicode keystrokes (no clipboard — default)

    private func typeUnicodeKeystrokes(_ text: String) async throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Self.log.error("keystrokes: no event source")
            throw InsertionError.eventSourceUnavailable
        }

        await waitForQuietKeyboard()

        let chunks = Self.utf16Chunks(of: text, maxUnits: 16)
        Self.log.notice("keystrokes: typing \(chunks.count) chunks")
        for chunk in chunks {
            var units = Array(chunk.utf16)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            // Never inherit live modifier state (e.g. a modifier held as the
            // push-to-talk key) — flags would turn text into shortcuts.
            down?.flags = []
            up?.flags = []
            down?.post(tap: .cgSessionEventTap)
            up?.post(tap: .cgSessionEventTap)
            // A short gap keeps slow event queues (Electron, web views) in order.
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Waits (bounded) until no modifier key is physically held. The final
    /// transcript often arrives while the push-to-talk modifier is still
    /// going up; typing at that instant would apply it to our events.
    private func waitForQuietKeyboard() async {
        let modifiers: CGEventFlags = [
            .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
        ]
        let start = ContinuousClock.now
        let deadline = start + .seconds(2)

        while ContinuousClock.now < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.isDisjoint(with: modifiers) {
                let waited = start.duration(to: .now)
                if waited > .milliseconds(30) {
                    Self.log.info("keystrokes: waited \(waited.description, privacy: .public) for modifier release")
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        Self.log.warning("keystrokes: modifiers still down after 2s; typing anyway")
    }

    /// Splits text into chunks of at most `maxUnits` UTF-16 code units without
    /// splitting grapheme clusters (so surrogate pairs and emoji stay intact).
    /// Internal for tests.
    static func utf16Chunks(of text: String, maxUnits: Int) -> [String] {
        precondition(maxUnits >= 2, "A chunk must fit at least one surrogate pair")
        var chunks: [String] = []
        var current = ""
        var currentUnits = 0

        for character in text {
            let units = character.utf16.count
            if currentUnits + units > maxUnits, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentUnits = 0
            }
            current.append(character)
            currentUnits += units
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: Accessibility (kAXSelectedText — explicit opt-in mode)

    private func insertViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedStatus == .success, let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            Self.log.warning("ax: no focused element (status \(focusedStatus.rawValue))")
            return false
        }
        let element = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)

        var settable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard settableStatus == .success, settable.boolValue else {
            Self.log.warning("ax: selectedText not settable (status \(settableStatus.rawValue))")
            return false
        }

        let setStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        Self.log.info("ax: set status \(setStatus.rawValue)")
        return setStatus == .success
    }

    // MARK: History-safe clipboard fallback (explicit opt-in only)

    private func pasteViaTransientClipboard(_ text: String) async throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw InsertionError.eventSourceUnavailable
        }

        await waitForQuietKeyboard()

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        // Transient + concealed markers keep clipboard-history managers
        // (Maccy, Raycast, Paste, Alfred…) from recording the write.
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: .voceTransient)
        pasteboard.setString("", forType: .voceConcealed)
        Self.log.info("clipboard: transient write, posting ⌘V")

        postCommandV(source: source)

        try? await Task.sleep(for: .milliseconds(400))
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
            pasteboard.setString("", forType: .voceRestored)
        }
        Self.log.info("clipboard: previous contents restored")
    }

    private func postCommandV(source: CGEventSource) {
        let vKeyCode: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}

extension NSPasteboard.PasteboardType {
    /// nspasteboard.org conventions for clipboard-history managers.
    static let voceTransient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let voceConcealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let voceRestored = NSPasteboard.PasteboardType("org.nspasteboard.RestoredType")
}
