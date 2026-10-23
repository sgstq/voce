import CoreGraphics
import XCTest
@testable import Voce

final class HotkeySpecTests: XCTestCase {
    func testLegacyNamesMap() {
        XCTAssertEqual(HotkeySpec.legacy(named: "F5"), HotkeySpec(keyCodes: [96], displayName: "F5"))
        XCTAssertEqual(HotkeySpec.legacy(named: "f12")?.keyCodes, [111])
        XCTAssertEqual(HotkeySpec.legacy(named: "Fn"), HotkeySpec(keyCodes: [63], displayName: "Fn"))
        XCTAssertEqual(HotkeySpec.legacy(named: "globe")?.keyCodes, [63])
        XCTAssertNil(HotkeySpec.legacy(named: "CapsLock"))
        XCTAssertNil(HotkeySpec.legacy(named: ""))
    }

    func testDefaultIsRightOption() {
        XCTAssertEqual(HotkeySpec.defaultPushToTalk, HotkeySpec(keyCodes: [61], displayName: "Right ⌥"))
    }

    func testCapturedKeysKnowWhetherTheyAreModifiersOnly() {
        XCTAssertFalse(HotkeySpec(capturedKeyCode: 96).isModifierOnly)        // F5
        XCTAssertTrue(HotkeySpec(capturedKeyCode: 61).isModifierOnly)         // Right ⌥
        XCTAssertTrue(HotkeySpec(capturedKeyCodes: [56, 61]).isModifierOnly)  // Right ⌥ + ⇧
        XCTAssertFalse(HotkeySpec(capturedKeyCodes: [59, 2]).isModifierOnly)  // ⌃ + D
    }

    func testDisplayNames() {
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 61).displayName, "Right ⌥")
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 96).displayName, "F5")
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 49).displayName, "Space")
        // Unmapped codes still get a stable, readable name.
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 1).displayName, "Key 1")
    }

    func testCombinationsReadInMenuOrder() {
        // However they were pressed: Fn ⌃ ⌥ ⇧ ⌘, then the key.
        let combo = HotkeySpec(capturedKeyCodes: [55, 2, 58, 59], keyNames: [2: "D"])
        XCTAssertEqual(combo.keyCodes, [59, 58, 55, 2])
        XCTAssertEqual(combo.displayName, "⌃ + ⌥ + ⌘ + D")
        XCTAssertEqual(combo.keyNames, ["⌃", "⌥", "⌘", "D"])

        XCTAssertEqual(HotkeySpec(capturedKeyCodes: [61, 56]).displayName, "Right ⌥ + ⇧")
    }

    func testKeyNamesFallBackToTypedCharacters() {
        XCTAssertEqual(KeyCodes.displayName(for: 2, characters: "d"), "D")
        XCTAssertEqual(KeyCodes.displayName(for: 96, characters: "\u{F708}"), "F5")
        XCTAssertEqual(KeyCodes.displayName(for: 2, characters: "\u{1B}"), "Key 2")
        XCTAssertEqual(KeyCodes.displayName(for: 2, characters: nil), "Key 2")
    }

    func testDecodesLegacyStringForm() throws {
        let spec = try JSONDecoder().decode(HotkeySpec.self, from: Data(#""F5""#.utf8))
        XCTAssertEqual(spec, HotkeySpec(keyCodes: [96], displayName: "F5"))

        // Unknown legacy names degrade to the default instead of failing.
        let fallback = try JSONDecoder().decode(HotkeySpec.self, from: Data(#""NotAKey""#.utf8))
        XCTAssertEqual(fallback, .defaultPushToTalk)
    }

    func testDecodesSingleKeyForm() throws {
        // Written before combinations existed.
        let json = #"{"keyCode": 61, "kind": "modifier", "displayName": "Right ⌥"}"#
        let spec = try JSONDecoder().decode(HotkeySpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec, HotkeySpec(keyCodes: [61], displayName: "Right ⌥"))
    }

    func testRoundTripsCombination() throws {
        let original = HotkeySpec(capturedKeyCodes: [56, 61])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(HotkeySpec.self, from: data), original)
    }

    func testModifierMaskTable() {
        XCTAssertEqual(KeyCodes.modifierMask(for: 63), .maskSecondaryFn)
        XCTAssertEqual(KeyCodes.modifierMask(for: 61), .maskAlternate)
        XCTAssertEqual(KeyCodes.modifierMask(for: 54), .maskCommand)
        XCTAssertEqual(KeyCodes.modifierMask(for: 62), .maskControl)
        XCTAssertEqual(KeyCodes.modifierMask(for: 60), .maskShift)
        XCTAssertNil(KeyCodes.modifierMask(for: 96))   // F5 is not a modifier
        XCTAssertNil(KeyCodes.modifierMask(for: KeyCodes.capsLock))
    }

    func testHeldModifiersTellSidesApart() {
        let option = CGEventFlags.maskAlternate.rawValue
        let shift = CGEventFlags.maskShift.rawValue
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: option | 0x40), [61])           // Right ⌥
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: option | 0x20), [58])           // ⌥
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: option | 0x60), [58, 61])       // both
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: option | shift | 0x42), [56, 61])
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: CGEventFlags.maskSecondaryFn.rawValue), [63])
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: 0), [])
    }

    func testHeldModifiersFallBackWithoutSideBits() {
        // Some virtual keyboards set only the generic flag; the key behind
        // the event decides which side is down.
        let option = CGEventFlags.maskAlternate.rawValue
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: option, changedKeyCode: 61), [61])
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: 0, changedKeyCode: 61), [])
        // With side bits present, they win over the event's key.
        XCTAssertEqual(KeyCodes.heldModifiers(rawFlags: option | 0x20, changedKeyCode: 61), [58])
    }
}
