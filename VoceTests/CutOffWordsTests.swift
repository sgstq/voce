import XCTest
@testable import Voce

final class CutOffWordsTests: XCTestCase {
    func testCutOffWordsAreCleaned() {
        let words: Set<String> = ["so", "we", "can", "just", "add", "the", "and", "then", "it", "is", "john"]
        func clean(_ text: String) -> String {
            CutOffWords.removed(from: text) { words.contains($0.lowercased()) }
        }
        // A real word keeps itself, loses the hyphen, and the next word its stray capital.
        XCTAssertEqual(clean("so we- Can just add"), "so we can just add")
        // A fragment that is no word goes, with its hyphen.
        XCTAssertEqual(clean("add ent- Anthropic API"), "add Anthropic API")
        // At the very end: a word stays, a fragment goes.
        XCTAssertEqual(clean("and then we-"), "and then we")
        XCTAssertEqual(clean("add the anthr-"), "add the")
        XCTAssertEqual(clean("and then -"), "and then")
        // Acronyms and "I" keep their capitals; unknown words keep theirs.
        XCTAssertEqual(clean("we- API is"), "we API is")
        XCTAssertEqual(clean("we- I can"), "we I can")
        XCTAssertEqual(clean("we- Oviedo is"), "we Oviedo is")
        // Real hyphens are untouched: inside words, before digits, as ranges.
        for kept in ["a well-known add-on", "gpt-5 and e-mail", "pages 5-6", "it is - and"] {
            XCTAssertEqual(clean(kept), kept)
        }
        // Cyrillic fragments are letters too.
        XCTAssertEqual(clean("так- Вот"), "Вот")
    }
}
