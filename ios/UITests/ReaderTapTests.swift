import XCTest

/// Tap zones on the generated 3,000-chapter book (DemoBooks.writeLong), whose paragraphs start
/// with a 〔chapter·paragraph〕 marker. A side tap moves a screen less a line through the same
/// tracking as a swipe, so the place it lands on is saved and the text never moves by itself.
final class ReaderTapTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // A fresh library and fresh settings (standard zones): -DemoKeep here would reopen
        // whatever an earlier test left behind.
        app.launchArguments = ["-DemoData", "YES", "-DemoLongBook", "YES", "-DemoTab", "shelf",
                               "-DemoReader", "1", "-DemoJumpTo", "1499"]
        app.launch()
        XCTAssertTrue(app.staticTexts["第1500章"].waitForExistence(timeout: 90), "the jump never showed 第1500章")
        settle()
    }

    func testTapForwardKeepsPlaceAfterRelaunch() {
        let before = top()
        let lastBefore = bottom()
        tap(atX: 0.9)
        Thread.sleep(forTimeInterval: 1)
        let after = top()
        XCTAssertGreaterThan(after.place, before.place, "the tap went from \(before.label) to \(after.label)")
        // A line of overlap means the paragraph that was last on screen is still there.
        XCTAssertLessThanOrEqual(after.place, lastBefore.place, "skipped from \(lastBefore.label) to \(after.label)")
        settle()
        assertStill(after)

        app.terminate()
        app.launchArguments = ["-DemoData", "YES", "-DemoKeep", "YES", "-DemoTab", "shelf", "-DemoReader", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "〔\(after.place.chapter)·"))
            .firstMatch.waitForExistence(timeout: 60), "reopened somewhere other than chapter \(after.place.chapter)")
        settle()
        let reopened = top()
        XCTAssertEqual(reopened.place.chapter, after.place.chapter, "left at \(after.label), reopened at \(reopened.label)")
        XCTAssertLessThanOrEqual(abs(reopened.place.paragraph - after.place.paragraph), 1,
                                 "left at \(after.label), reopened at \(reopened.label)")
    }

    /// Going back from a chapter's start crosses into the chapter above, and the reader then
    /// joins another chapter above that one; the text must stay where the tap put it.
    func testTapBackIntoTheChapterAboveNeverJumps() {
        var previous = top()
        for _ in 0..<4 {
            tap(atX: 0.1)
            settle()
            let now = top()
            XCTAssertLessThan(now.place, previous.place, "went from \(previous.label) to \(now.label)")
            XCTAssertLessThanOrEqual(previous.place.chapter - now.place.chapter, 1,
                                     "ran from \(previous.label) to \(now.label)")
            previous = now
        }
        assertStill(previous)
    }

    /// Mid-height, clear of the left edge's brightness strip.
    private func tap(atX x: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
    }

    private struct Place: Comparable {
        var chapter: Int
        var paragraph: Int
        static func < (a: Place, b: Place) -> Bool { (a.chapter, a.paragraph) < (b.chapter, b.paragraph) }
    }

    private struct Shown {
        var label: String
        var minY: CGFloat
        var place: Place
    }

    /// The topmost text that is at least partly below the safe area.
    private func top(file: StaticString = #filePath, line: UInt = #line) -> Shown {
        let safeTop = app.windows.firstMatch.frame.minY + 60
        return shown(file: file, line: line) { frame in frame.maxY > safeTop } better: { $0.minY < $1.minY }
    }

    /// The bottommost text that starts above the home indicator.
    private func bottom(file: StaticString = #filePath, line: UInt = #line) -> Shown {
        let floor = app.windows.firstMatch.frame.maxY - 20
        return shown(file: file, line: line) { frame in frame.minY < floor } better: { $0.minY > $1.minY }
    }

    private func shown(file: StaticString, line: UInt, where onScreen: (CGRect) -> Bool,
                       better: (Shown, Shown) -> Bool) -> Shown {
        var best: Shown?
        for element in app.staticTexts.allElementsBoundByIndex {
            let frame = element.frame
            guard frame.height > 0, onScreen(frame), let place = Self.place(of: element.label) else { continue }
            let candidate = Shown(label: element.label, minY: frame.minY, place: place)
            if best == nil || better(candidate, best!) { best = candidate }
        }
        guard let best else {
            XCTFail("no reader text on screen", file: file, line: line)
            return Shown(label: "", minY: 0, place: Place(chapter: 0, paragraph: 0))
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

    /// Lets the scroll, the pinning after it and any chapter loading finish.
    private func settle() {
        Thread.sleep(forTimeInterval: 2.5)
    }

    private func assertStill(_ before: Shown, file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: 3)
        let after = top(file: file, line: line)
        XCTAssertEqual(after.label, before.label, "the text moved by itself", file: file, line: line)
        XCTAssertEqual(after.minY, before.minY, accuracy: 2, "the text shifted by itself", file: file, line: line)
    }
}
