import XCTest
@testable import Voce

@MainActor
final class OverlayModelTests: XCTestCase {
    func testLevelsRestAtZero() {
        let model = OverlayModel()
        XCTAssertEqual(model.levels, OverlayModel.restingLevels)
        XCTAssertEqual(model.levels.count, OverlayModel.barCount)
    }

    func testNewestLevelLandsInTheCentreAndRipplesOutward() {
        let model = OverlayModel()
        let centre = OverlayModel.barCount / 2

        model.pushLevel(1)
        XCTAssertEqual(model.levels[centre], 1, accuracy: 0.0001)
        XCTAssertEqual(model.levels[centre - 1], 0, accuracy: 0.0001)

        // A second loud chunk: the first one has moved one bar outward on
        // both sides, slightly lower because of the centre-weighted envelope.
        model.pushLevel(1)
        XCTAssertEqual(model.levels[centre], 1, accuracy: 0.0001)
        XCTAssertGreaterThan(model.levels[centre - 1], 0.9)
        XCTAssertLessThan(model.levels[centre - 1], 1)
    }

    func testBarsAreSymmetric() {
        let model = OverlayModel()
        for level in [0.2, 0.9, 0.4, 0.7] {
            model.pushLevel(level)
        }
        XCTAssertEqual(model.levels, model.levels.reversed())
    }

    func testLevelsFallSoftlyAndClamp() {
        let model = OverlayModel()
        let centre = OverlayModel.barCount / 2

        model.pushLevel(5)
        XCTAssertEqual(model.levels[centre], 1, accuracy: 0.0001)

        model.pushLevel(0)
        XCTAssertGreaterThan(model.levels[centre], 0.5)

        model.resetLevels()
        XCTAssertEqual(model.levels, OverlayModel.restingLevels)
    }
}
