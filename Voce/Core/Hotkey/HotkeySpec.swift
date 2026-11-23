import Foundation

/// A recorded push-to-talk key or key combination: every listed key must be
/// held, and no other. Modifiers count per side, so "⌥" and "Right ⌥" are
/// different keys. Decoding accepts the legacy string form ("F5", "Fn") and
/// the earlier single-key form, so older configs keep working.
struct HotkeySpec: Codable, Equatable, Sendable {
    /// Modifiers first in menu order, then at most one other key.
    var keyCodes: [UInt16]
    /// "Right ⌥", "Right ⌥ + ⇧", "⌃ + ⌥ + D". Stored rather than derived
    /// because a letter's name depends on the keyboard layout at recording time.
    var displayName: String

    static let defaultPushToTalk = HotkeySpec(capturedKeyCode: 61)
    static let nameSeparator = " + "

    init(keyCodes: [UInt16], displayName: String) {
        self.keyCodes = keyCodes
        self.displayName = displayName
    }

    init(capturedKeyCode: UInt16) {
        self.init(capturedKeyCodes: [capturedKeyCode])
    }

    /// `keyNames` overrides table names, for keys named by what they type.
    init(capturedKeyCodes: Set<UInt16>, keyNames: [UInt16: String] = [:]) {
        let ordered = KeyCodes.sorted(capturedKeyCodes)
        self.keyCodes = ordered
        self.displayName = ordered
            .map { keyNames[$0] ?? KeyCodes.displayName(for: $0) }
            .joined(separator: Self.nameSeparator)
    }

    var keys: Set<UInt16> { Set(keyCodes) }

    /// One name per key, for drawing each as its own keycap.
    var keyNames: [String] { displayName.components(separatedBy: Self.nameSeparator) }

    var isModifierOnly: Bool { keyCodes.allSatisfy(KeyCodes.isModifier) }

    /// Maps a legacy config name. Returns nil for names that were never valid.
    static func legacy(named name: String) -> HotkeySpec? {
        guard let code = KeyCodes.legacyKeyCode(forName: name) else { return nil }
        return HotkeySpec(capturedKeyCode: code)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCodes, displayName
        /// Single-key form written before combinations existed.
        case keyCode
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let legacyName = try? single.decode(String.self) {
            // Pre-recorder configs stored a plain name; unknown names fall
            // back to the default rather than failing the whole config load.
            self = HotkeySpec.legacy(named: legacyName) ?? .defaultPushToTalk
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let keyCodes = try container.decodeIfPresent([UInt16].self, forKey: .keyCodes) {
            self.keyCodes = keyCodes
        } else {
            self.keyCodes = [try container.decode(UInt16.self, forKey: .keyCode)]
        }
        self.displayName = try container.decode(String.self, forKey: .displayName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCodes, forKey: .keyCodes)
        try container.encode(displayName, forKey: .displayName)
    }
}
