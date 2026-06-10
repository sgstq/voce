import XCTest
@testable import Voce

final class TextInserterTests: XCTestCase {
    @MainActor
    func testChunksRespectUTF16Limit() {
        let text = String(repeating: "abcde", count: 20) // 100 units
        let chunks = TextInserter.utf16Chunks(of: text, maxUnits: 16)

        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 16 })
        XCTAssertEqual(chunks.joined(), text)
    }

    @MainActor
    func testChunksDoNotSplitSurrogatePairsOrClusters() {
        // Each flag emoji is 4 UTF-16 units; family emoji is 11.
        let text = "🇺🇸🇮🇹👨‍👩‍👧‍👦 ciao 🇫🇮 hello"
        let chunks = TextInserter.utf16Chunks(of: text, maxUnits: 16)

        XCTAssertEqual(chunks.joined(), text)
        for chunk in chunks {
            XCTAssertTrue(chunk.utf16.count <= 16)
            // Round-tripping through UTF-16 must not lose anything,
            // which fails if a surrogate pair was split.
            let units = Array(chunk.utf16)
            XCTAssertEqual(String(utf16CodeUnits: units, count: units.count), chunk)
        }
    }

    @MainActor
    func testEmptyTextProducesNoChunks() {
        XCTAssertTrue(TextInserter.utf16Chunks(of: "", maxUnits: 16).isEmpty)
    }
}
