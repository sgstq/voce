import XCTest
@testable import Voce

final class HotkeyMatcherTests: XCTestCase {
    private let leftOption: UInt16 = 58
    private let rightOption: UInt16 = 61
    private let leftShift: UInt16 = 56
    private let control: UInt16 = 59
    private let keyD: UInt16 = 2
    private let keyE: UInt16 = 14
    private let f5: UInt16 = 96

    private let english = UUID()
    private let russian = UUID()

    func testSingleModifierPressesAndReleases() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.pressed(english)])
        XCTAssertEqual(matcher.modifiersChanged(to: []), [.released(english)])
    }

    func testOtherSideOfTheSameModifierNeverMatches() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])

        XCTAssertEqual(matcher.modifiersChanged(to: [leftOption]), [])
        XCTAssertEqual(matcher.modifiersChanged(to: []), [])
    }

    func testReleaseIsSeenWhileTheOtherSideIsStillHeld() {
        let bindings = [
            HotkeyBinding(id: english, keys: [rightOption]),
            HotkeyBinding(id: russian, keys: [leftOption]),
        ]
        var matcher = HotkeyMatcher(bindings: bindings)

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.pressed(english)])
        // Left ⌥ joins mid-dictation: no second dictation starts.
        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption, leftOption]), [])
        XCTAssertEqual(matcher.modifiersChanged(to: [leftOption]), [.released(english)])
        // Letting go of the right key never starts the left key's profile.
        XCTAssertEqual(matcher.modifiersChanged(to: []), [])
    }

    func testCombinationWinsOverItsOwnPart() {
        let bindings = [
            HotkeyBinding(id: english, keys: [rightOption]),
            HotkeyBinding(id: russian, keys: [leftShift, rightOption]),
        ]
        var matcher = HotkeyMatcher(bindings: bindings)

        // Right ⌥ alone might still become Right ⌥ + ⇧: listen, but wait.
        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.armed])
        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption, leftShift]), [.pressed(russian)])
        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.released(russian)])
        // Letting go of ⇧ first must not start the Right ⌥ profile.
        XCTAssertEqual(matcher.modifiersChanged(to: []), [])
    }

    func testPartOfACombinationFiresOnceItSettles() {
        let bindings = [
            HotkeyBinding(id: english, keys: [rightOption]),
            HotkeyBinding(id: russian, keys: [leftShift, rightOption]),
        ]
        var matcher = HotkeyMatcher(bindings: bindings)

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.armed])
        XCTAssertEqual(matcher.settle(), [.pressed(english)])
        // A late ⇧ doesn't switch profiles mid-dictation.
        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption, leftShift]), [])
        XCTAssertEqual(matcher.modifiersChanged(to: [leftShift]), [.released(english)])
    }

    func testTapShorterThanTheSettleDelayIsCancelled() {
        let bindings = [
            HotkeyBinding(id: english, keys: [rightOption]),
            HotkeyBinding(id: russian, keys: [leftShift, rightOption]),
        ]
        var matcher = HotkeyMatcher(bindings: bindings)

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.armed])
        XCTAssertEqual(matcher.modifiersChanged(to: []), [.cancelled])
        XCTAssertEqual(matcher.settle(), [])
    }

    func testShortcutWhileArmedCancels() {
        let bindings = [
            HotkeyBinding(id: english, keys: [rightOption]),
            HotkeyBinding(id: russian, keys: [leftShift, rightOption]),
        ]
        var matcher = HotkeyMatcher(bindings: bindings)

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.armed])
        XCTAssertEqual(matcher.keyDown(keyE), [.cancelled])     // ⌥E types an accent
        XCTAssertEqual(matcher.settle(), [])
    }

    func testShortcutWhileHeldInterruptsButKeepsTheRelease() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.pressed(english)])
        XCTAssertEqual(matcher.keyDown(keyE), [.interrupted(english)])
        XCTAssertEqual(matcher.keyUp(keyE), [])
        XCTAssertEqual(matcher.modifiersChanged(to: []), [.released(english)])
    }

    func testExtraModifierAloneDoesNotInterrupt() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.pressed(english)])
        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption, control]), [])
        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [])
        XCTAssertEqual(matcher.modifiersChanged(to: []), [.released(english)])
    }

    func testClicksInterruptModifierKeysOnly() {
        var modifiers = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])
        XCTAssertEqual(modifiers.modifiersChanged(to: [rightOption]), [.pressed(english)])
        XCTAssertEqual(modifiers.click(), [.interrupted(english)])   // ⌥-click

        var functionKey = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [f5])])
        XCTAssertEqual(functionKey.keyDown(f5), [.pressed(english)])
        XCTAssertEqual(functionKey.click(), [])
        XCTAssertEqual(functionKey.keyUp(f5), [.released(english)])
    }

    func testModifiersPlusKeyCombination() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [control, leftOption, keyD])])

        XCTAssertEqual(matcher.modifiersChanged(to: [control]), [])
        XCTAssertEqual(matcher.modifiersChanged(to: [control, leftOption]), [])
        XCTAssertEqual(matcher.keyDown(keyD), [.pressed(english)])
        XCTAssertEqual(matcher.keyDown(keyD), [])                  // key repeat
        XCTAssertEqual(matcher.keyUp(keyD), [.released(english)])
        // D alone, without the modifiers, is just typing.
        XCTAssertEqual(matcher.modifiersChanged(to: []), [])
        XCTAssertEqual(matcher.keyDown(keyD), [])
    }

    func testExtraKeysMeanNoMatch() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])

        // ⇧ held first: Right ⌥ + ⇧ is not Right ⌥.
        XCTAssertEqual(matcher.modifiersChanged(to: [leftShift]), [])
        XCTAssertEqual(matcher.modifiersChanged(to: [leftShift, rightOption]), [])
    }

    func testResyncReleasesKeysLetGoWhileUnobserved() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.pressed(english)])
        XCTAssertEqual(matcher.resync(modifiers: [rightOption], keys: []), [])
        XCTAssertEqual(matcher.resync(modifiers: [], keys: []), [.released(english)])
    }

    func testUpdatingBindingsKeepsAHeldBinding() {
        var matcher = HotkeyMatcher(bindings: [HotkeyBinding(id: english, keys: [rightOption])])

        XCTAssertEqual(matcher.modifiersChanged(to: [rightOption]), [.pressed(english)])
        matcher.update(bindings: [HotkeyBinding(id: russian, keys: [leftOption])])
        XCTAssertEqual(matcher.modifiersChanged(to: []), [.released(english)])
        XCTAssertEqual(matcher.modifiersChanged(to: [leftOption]), [.pressed(russian)])
    }
}
