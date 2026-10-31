import XCTest

/// The 3D shelf over the demo library: the crest named by the shelf must follow the row.
final class ShelfTests: XCTestCase {
    func testDraggingOneBookMovesTheCrestToTheNextBook() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-DemoData", "YES", "-DemoTab", "shelf"]
        app.launch()
        let shelf = app.otherElements["3D shelf"].firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 30), "no 3D shelf")
        Thread.sleep(forTimeInterval: 3)
        let before = shelf.value as? String ?? ""
        XCTAssertFalse(before.isEmpty, "the shelf names no crest")

        // About one slot to the left, released slowly so it snaps to the neighbour.
        let start = shelf.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let end = shelf.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 2)
        let after = shelf.value as? String ?? ""
        XCTAssertNotEqual(after, before, "the crest still names \(before) after the row moved")
        XCTAssertTrue(app.staticTexts[after].exists, "the caption doesn't show the crest \(after)")
    }
}
