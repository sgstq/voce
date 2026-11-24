import XCTest
@testable import Voce

final class FocusContextWindowTests: XCTestCase {
    func testDictationAfterTextGetsOneSpace() {
        func typed(_ text: String, after before: String) -> String {
            var context = FocusContext()
            context.textBeforeCursor = before
            return context.spacedForInsertion(text)
        }
        XCTAssertEqual(typed("The level is light.", after: "long hyphens."), " The level is light.")
        XCTAssertEqual(typed("the store", after: "I went to"), " the store")
        XCTAssertEqual(typed("Next.", after: "Is it done?"), " Next.")
        XCTAssertEqual(typed("Next.", after: "Done. "), "Next.")
        XCTAssertEqual(typed("Next.", after: "Done.\n"), "Next.")
        XCTAssertEqual(typed("Next.", after: ""), "Next.")
        XCTAssertEqual(typed("aside", after: "an ("), "aside")
        XCTAssertEqual(typed("quoted", after: "say \""), "quoted")
        XCTAssertEqual(typed(", then more", after: "first"), ", then more")
        // Never two spaces in a row: inside the dictation or at the seam.
        XCTAssertEqual(typed("Can  we   import", after: ""), "Can we import")
        XCTAssertEqual(typed("Can  we", after: "Hi."), " Can we")
        XCTAssertEqual(typed(" we import", after: "Can "), "we import")
        XCTAssertEqual(typed("line one\n\nline two", after: ""), "line one\n\nline two")
    }

    func testWindowsAroundCursor() {
        let text = String(repeating: "a", count: 1000) + "CURSOR" + String(repeating: "b", count: 1000)
        // Selection covering "CURSOR" (location 1000, length 6).
        let window = FocusContextCapture.window(
            text: text, selectionLocation: 1000, selectionLength: 6, before: 100, after: 50
        )
        XCTAssertEqual(window.before, String(repeating: "a", count: 100))
        XCTAssertEqual(window.after, String(repeating: "b", count: 50))
    }

    func testWindowClampsAtDocumentEdges() {
        let window = FocusContextCapture.window(
            text: "short", selectionLocation: 2, selectionLength: 0, before: 600, after: 300
        )
        XCTAssertEqual(window.before, "sh")
        XCTAssertEqual(window.after, "ort")
    }

    func testWindowHandlesOutOfRangeSelection() {
        let window = FocusContextCapture.window(
            text: "abc", selectionLocation: 99, selectionLength: 5, before: 10, after: 10
        )
        XCTAssertEqual(window.before, "abc")
        XCTAssertEqual(window.after, "")
    }

    func testWindowDoesNotSplitEmoji() {
        // "👨‍👩‍👧‍👦" is 11 UTF-16 units; cut points inside it must snap out.
        let text = "abc👨‍👩‍👧‍👦def"
        let window = FocusContextCapture.window(
            text: text, selectionLocation: 5, selectionLength: 0, before: 1, after: 2
        )
        // Whatever the exact snap, results must be valid strings that
        // round-trip through UTF-16 (no lone surrogates).
        for part in [window.before, window.after] {
            let units = Array(part.utf16)
            XCTAssertEqual(String(utf16CodeUnits: units, count: units.count), part)
        }
    }

    func testEmptyText() {
        let window = FocusContextCapture.window(
            text: "", selectionLocation: 0, selectionLength: 0, before: 100, after: 100
        )
        XCTAssertEqual(window.before, "")
        XCTAssertEqual(window.after, "")
    }
}
