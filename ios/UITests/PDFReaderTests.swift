import XCTest

/// The PDF reader over the generated 12-page demo PDF (DemoPDF): the page it's left on is the
/// page it reopens on.
final class PDFReaderTests: XCTestCase {
    func testReopensOnSamePage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A fresh library, so the PDF has no saved page yet.
        app.launchArguments = ["-DemoData", "YES", "-DemoTab", "shelf", "-DemoPDF", "YES"]
        app.launch()
        XCTAssertEqual(pageLabel(in: app), "1 / 12", "the demo PDF didn't open on its first page")

        let next = app.buttons["pdf.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "no Next page button")
        next.tap()
        next.tap()
        let label = app.staticTexts["pdf.page"]
        let onThree = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "3 / 12"), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [onThree], timeout: 5), .completed,
                       "two taps on Next page showed \(label.label)")
        // The page is saved 500 ms after it changes; terminate() never sends the app to the background.
        Thread.sleep(forTimeInterval: 2)
        app.terminate()

        // The PDF was read last, so it's first on the shelf.
        app.launchArguments = ["-DemoData", "YES", "-DemoKeep", "YES", "-DemoTab", "shelf", "-DemoReader", "1"]
        app.launch()
        XCTAssertEqual(pageLabel(in: app), "3 / 12", "left the PDF on page 3, reopened elsewhere")
    }

    /// Waits for the pages, opens the chrome with a centre tap and reads its page counter.
    private func pageLabel(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> String {
        let pages = app.descendants(matching: .any)["pdf.pages"]
        XCTAssertTrue(pages.waitForExistence(timeout: 60), "the PDF never opened", file: file, line: line)
        // The cover slides in and the saved page lands first.
        Thread.sleep(forTimeInterval: 2)
        let label = app.staticTexts["pdf.page"]
        // A single tap waits out PDFKit's double tap, so give each try a moment.
        for _ in 0..<3 where !label.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
            _ = label.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(label.exists, "the chrome never showed", file: file, line: line)
        return label.label
    }
}
