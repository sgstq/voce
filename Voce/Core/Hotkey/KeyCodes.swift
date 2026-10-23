import AppKit
import CoreGraphics

/// Key-code tables shared by the hotkey monitor and the settings recorder.
enum KeyCodes {
    /// Modifier keys that can act as push-to-talk (held, not toggled).
    /// Caps Lock is deliberately absent: it toggles instead of holding.
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    static let capsLock: UInt16 = 57
    static let escape: UInt16 = 53
    static let function: UInt16 = 63

    /// Menu order for modifiers (Fn ⌃ ⌥ ⇧ ⌘, left before right), so a
    /// combination always reads the same however it was pressed.
    private static let modifierOrder: [UInt16] = [63, 59, 62, 58, 61, 56, 60, 55, 54]

    /// Device-dependent flag bit for each side of each modifier
    /// (NX_DEVICE…KEYMASK in IOLLEvent.h). The generic flags are set for
    /// either side, so they can't tell a Right ⌥ release while Left ⌥ is
    /// still down. Fn has a single key and uses `.maskSecondaryFn`.
    private static let sideMasks: [UInt16: UInt64] = [
        59: 0x0000_0001, // ⌃
        56: 0x0000_0002, // ⇧
        60: 0x0000_0004, // Right ⇧
        55: 0x0000_0008, // ⌘
        54: 0x0000_0010, // Right ⌘
        58: 0x0000_0020, // ⌥
        61: 0x0000_0040, // Right ⌥
        62: 0x0000_2000, // Right ⌃
    ]

    static func isModifier(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

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

    /// The modifier keys physically down, per side, read from a raw CGEvent
    /// or NSEvent flags word. `changedKeyCode` is the modifier behind a
    /// flags-changed event: a keyboard that reports no side bits for it
    /// (some virtual keyboards do) falls back to the generic flag.
    static func heldModifiers(rawFlags: UInt64, changedKeyCode: UInt16? = nil) -> Set<UInt16> {
        var held = Set<UInt16>()
        for (keyCode, bit) in sideMasks where rawFlags & bit != 0 {
            held.insert(keyCode)
        }
        if rawFlags & CGEventFlags.maskSecondaryFn.rawValue != 0 {
            held.insert(function)
        }
        if let changedKeyCode, changedKeyCode != function,
           let generic = modifierMask(for: changedKeyCode) {
            let familyBits = sideMasks
                .filter { modifierMask(for: $0.key) == generic }
                .values
                .reduce(0, |)
            if rawFlags & familyBits == 0, rawFlags & generic.rawValue != 0 {
                held.insert(changedKeyCode)
            }
        }
        return held
    }

    /// Modifiers first in menu order, then any other key.
    static func sorted(_ keyCodes: Set<UInt16>) -> [UInt16] {
        let modifiers = modifierOrder.filter(keyCodes.contains)
        let others = keyCodes.subtracting(modifierKeyCodes).sorted()
        return modifiers + others
    }

    static func displayName(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    /// Prefers the table; otherwise the character the key types on the
    /// current layout ("D", "7"), which the table can't know.
    static func displayName(for keyCode: UInt16, characters: String?) -> String {
        if let name = names[keyCode] { return name }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !typed.isEmpty, typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return typed
        }
        return displayName(for: keyCode)
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
