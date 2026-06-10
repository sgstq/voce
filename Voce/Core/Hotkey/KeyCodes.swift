import AppKit
import CoreGraphics

/// Key-code tables shared by the hotkey monitor and the settings recorder.
enum KeyCodes {
    /// Modifier keys that can act as push-to-talk (held, not toggled).
    /// Caps Lock is deliberately absent: it toggles instead of holding.
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    static let capsLock: UInt16 = 57
    static let escape: UInt16 = 53

    /// The CGEvent flag that tells press from release for a modifier key.
    static func modifierMask(for keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: .maskCommand
        case 56, 60: .maskShift
        case 58, 61: .maskAlternate
        case 59, 62: .maskControl
        case 63: .maskSecondaryFn
        default: nil
        }
    }

    /// NSEvent equivalent, used by the settings recorder.
    static func nsModifier(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        case 63: .function
        default: nil
        }
    }

    static func displayName(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    /// Lowercased legacy config names ("f5", "fn") → key code.
    static func legacyKeyCode(forName name: String) -> UInt16? {
        legacyNames[name.lowercased()]
    }

    private static let legacyNames: [String: UInt16] = {
        var map: [String: UInt16] = ["fn": 63, "globe": 63]
        for (code, name) in names where name.hasPrefix("F") && UInt16(name.dropFirst()) != nil {
            map[name.lowercased()] = code
        }
        return map
    }()

    private static let names: [UInt16: String] = [
        // Function row
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        // Modifiers
        55: "⌘", 54: "Right ⌘",
        56: "⇧", 60: "Right ⇧",
        58: "⌥", 61: "Right ⌥",
        59: "⌃", 62: "Right ⌃",
        63: "Fn",
        // Common named keys
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        76: "Enter", 114: "Help", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        50: "`", 10: "§",
    ]
}
