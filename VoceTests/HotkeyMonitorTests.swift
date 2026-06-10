import XCTest
@testable import Voce

final class HotkeySpecTests: XCTestCase {
    func testLegacyNamesMap() {
        XCTAssertEqual(HotkeySpec.legacy(named: "F5"), HotkeySpec(keyCode: 96, kind: .key, displayName: "F5"))
        XCTAssertEqual(HotkeySpec.legacy(named: "f12")?.keyCode, 111)
        XCTAssertEqual(HotkeySpec.legacy(named: "Fn"), HotkeySpec(keyCode: 63, kind: .modifier, displayName: "Fn"))
        XCTAssertEqual(HotkeySpec.legacy(named: "globe")?.keyCode, 63)
        XCTAssertNil(HotkeySpec.legacy(named: "CapsLock"))
        XCTAssertNil(HotkeySpec.legacy(named: ""))
    }

    func testCapturedKeyCodeInfersKind() {
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 96).kind, .key)        // F5
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 61).kind, .modifier)   // Right ⌥
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 63).kind, .modifier)   // Fn
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 49).kind, .key)        // Space
    }

    func testDisplayNames() {
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 61).displayName, "Right ⌥")
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 96).displayName, "F5")
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 49).displayName, "Space")
        // Unmapped codes still get a stable, readable name.
        XCTAssertEqual(HotkeySpec(capturedKeyCode: 1).displayName, "Key 1")
    }

    func testDecodesLegacyStringForm() throws {
        let spec = try JSONDecoder().decode(HotkeySpec.self, from: Data(#""F5""#.utf8))
        XCTAssertEqual(spec, HotkeySpec(keyCode: 96, kind: .key, displayName: "F5"))

        // Unknown legacy names degrade to the default instead of failing.
        let fallback = try JSONDecoder().decode(HotkeySpec.self, from: Data(#""NotAKey""#.utf8))
        XCTAssertEqual(fallback, .defaultPushToTalk)
    }

    func testRoundTripsStructuredForm() throws {
        let original = HotkeySpec(capturedKeyCode: 61)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeySpec.self, from: data)
        XCTAssertEqual(decoded, original)
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
}
