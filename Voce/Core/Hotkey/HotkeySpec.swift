import Foundation

/// A recorded push-to-talk key. Regular keys are matched on
/// keyDown/keyUp; modifier keys (Fn, ⌥, ⌘, ⇧, ⌃ — either side) on
/// flagsChanged. Decoding accepts the legacy string form ("F5", "Fn")
/// so configs written before key recording keep working.
struct HotkeySpec: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case key
        case modifier
    }

    var keyCode: UInt16
    var kind: Kind
    var displayName: String

    static let defaultPushToTalk = HotkeySpec(keyCode: 96, kind: .key, displayName: "F5")

    init(keyCode: UInt16, kind: Kind, displayName: String) {
        self.keyCode = keyCode
        self.kind = kind
        self.displayName = displayName
    }

    init(capturedKeyCode: UInt16) {
        self.keyCode = capturedKeyCode
        self.kind = KeyCodes.modifierKeyCodes.contains(capturedKeyCode) ? .modifier : .key
        self.displayName = KeyCodes.displayName(for: capturedKeyCode)
    }

    /// Maps a legacy config name. Returns nil for names that were never valid.
    static func legacy(named name: String) -> HotkeySpec? {
        guard let code = KeyCodes.legacyKeyCode(forName: name) else { return nil }
        return HotkeySpec(capturedKeyCode: code)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, kind, displayName
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
        self.keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.displayName = try container.decode(String.self, forKey: .displayName)
    }
}
