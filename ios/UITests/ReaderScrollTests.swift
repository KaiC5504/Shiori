import XCTest

/// Drives the reader over the generated 3,000-chapter book (DemoBooks.writeLong), whose
/// paragraphs start with a 〔chapter·paragraph〕 marker, so every check reads the exact
/// paragraph at the top of the screen.
final class ReaderScrollTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-DemoData", "YES", "-DemoLongBook", "YES", "-DemoTab", "shelf",
                               "-DemoReader", "1", "-DemoJumpTo", "1499"]
        app.launch()
        XCTAssertTrue(app.staticTexts["第1500章"].waitForExistence(timeout: 90), "the jump never showed 第1500章")
        settle()
    }

    func testJumpLandsOnTheChapterAndStaysThere() {
        let landed = top()
        XCTAssertEqual(landed.place.chapter, 1500, "jumped to \(landed.label)")
        XCTAssertEqual(landed.place.paragraph, 0, "the chapter title should be at the top, got \(landed.label)")
        assertStill(landed)
    }

    func testReadingForwardKeepsItsPlace() {
        let before = top()
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        settle()
        let after = top()
        XCTAssertGreaterThan(after.place, before.place, "scrolling forward went from \(before.label) to \(after.label)")
        assertStill(after)
    }

    func testReadingBackIntoEarlierChaptersKeepsItsPlace() {
        for _ in 0..<3 { app.swipeUp(velocity: .fast) }
        settle()
        let forward = top()
        for _ in 0..<12 { app.swipeDown(velocity: .fast) }
        settle()
        let back = top()
        XCTAssertLessThan(back.place.chapter, 1500, "couldn't scroll back before the jump target: \(back.label)")
        XCTAssertLessThan(back.place, forward.place)
        assertStill(back)
    }

    func testSlowScrollingAcrossAChapterBoundaryNeverJumps() {
        var previous = top()
        for _ in 0..<10 {
            app.swipeUp(velocity: .slow)
            settle()
            let now = top()
            XCTAssertGreaterThan(now.place, previous.place, "went from \(previous.label) to \(now.label)")
            // A slow swipe moves well under a screen; a jump of several chapters is the bug.
            XCTAssertLessThanOrEqual(now.place.chapter - previous.place.chapter, 1,
                                     "jumped from \(previous.label) to \(now.label)")
            previous = now
        }
        assertStill(previous)
    }

    private struct Place: Comparable {
        var chapter: Int
        var paragraph: Int
        static func < (a: Place, b: Place) -> Bool { (a.chapter, a.paragraph) < (b.chapter, b.paragraph) }
    }

    private struct Top {
        var label: String
        var minY: CGFloat
        var place: Place
    }

    /// The topmost text that is at least partly below the safe area.
    private func top(file: StaticString = #filePath, line: UInt = #line) -> Top {
        let safeTop = app.windows.firstMatch.frame.minY + 60
        var best: Top?
        for element in app.staticTexts.allElementsBoundByIndex {
            let frame = element.frame
            guard frame.height > 0, frame.maxY > safeTop, let place = Self.place(of: element.label) else { continue }
            if best == nil || frame.minY < best!.minY {
                best = Top(label: element.label, minY: frame.minY, place: place)
            }
        }
        guard let best else {
            XCTFail("no reader text on screen", file: file, line: line)
            return Top(label: "", minY: 0, place: Place(chapter: 0, paragraph: 0))
        }
        return best
    }

    private static func place(of label: String) -> Place? {
        if label.hasPrefix("第"), label.hasSuffix("章"), let n = Int(label.dropFirst().dropLast()) {
            return Place(chapter: n, paragraph: 0)
        }
        guard label.hasPrefix("〔"), let close = label.firstIndex(of: "〕") else { return nil }
        let parts = label[label.index(after: label.startIndex)..<close].split(separator: "·")
        guard parts.count == 2, let c = Int(parts[0]), let p = Int(parts[1]) else { return nil }
        return Place(chapter: c, paragraph: p)
    }

    /// Lets momentum and any chapter loading finish.
    private func settle() {
        Thread.sleep(forTimeInterval: 2.5)
    }

    /// The reported bug: the text moves by itself a moment after scrolling stops.
    private func assertStill(_ before: Top, file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: 3)
        let after = top(file: file, line: line)
        XCTAssertEqual(after.label, before.label, "the text moved by itself", file: file, line: line)
        XCTAssertEqual(after.minY, before.minY, accuracy: 2, "the text shifted by itself", file: file, line: line)
    }
}
