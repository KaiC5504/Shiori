import XCTest

/// The paged layout over the generated 3,000-chapter book (DemoBooks.writeLong), whose paragraphs
/// start with a 〔chapter·paragraph〕 marker. A page's text is its accessibility label
/// (`paged.page`), so the markers on it say exactly where the reader is.
final class ReaderPagedTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // A fresh library and fresh settings (relay, standard zones): -DemoKeep here would reopen
        // whatever an earlier test left behind.
        app.launchArguments = ["-DemoData", "YES", "-DemoLongBook", "YES", "-DemoLayout", "paged", "-DemoEffect", "relay",
                               "-DemoTab", "shelf", "-DemoReader", "1", "-DemoJumpTo", "1499"]
        app.launch()
        XCTAssertTrue(page(containing: "〔1500·").waitForExistence(timeout: 90), "the jump never showed chapter 1500")
        settle()
    }

    func testRelayTurnsForward() {
        let before = page()
        tap(atX: 0.9)
        settle()
        let after = page()
        XCTAssertGreaterThan(after.first, before.first, "the tap went from \(before.first) to \(after.first)")
        // One page on: the new page starts in the paragraph the last one ended in, or the next.
        XCTAssertLessThanOrEqual(after.first, before.last.next, "skipped from \(before.last) to \(after.first)")
    }

    /// Curl, the default effect, through the same tap zones.
    func testCurlTurnsForward() {
        app.terminate()
        app.launchArguments = ["-DemoData", "YES", "-DemoLongBook", "YES", "-DemoLayout", "paged", "-DemoEffect", "curl",
                               "-DemoTab", "shelf", "-DemoReader", "1", "-DemoJumpTo", "1499"]
        app.launch()
        XCTAssertTrue(page(containing: "〔1500·").waitForExistence(timeout: 90), "the jump never showed chapter 1500")
        settle()
        let before = page()
        tap(atX: 0.9)
        settle()
        let after = page()
        XCTAssertGreaterThan(after.first, before.first, "the curl went from \(before.first) to \(after.first)")
        XCTAssertLessThanOrEqual(after.first, before.last.next, "skipped from \(before.last) to \(after.first)")
    }

    /// Mid-chapter, where a new size moves every page break: the page shown after it still holds
    /// the character the old page started with.
    func testSizeChangeKeepsPlace() {
        turnForward(2)
        let before = page()
        openAppearance()
        let larger = app.buttons["aa.larger"]
        XCTAssertTrue(larger.waitForExistence(timeout: 5), "the Aa sheet never opened")
        for _ in 0..<3 {
            larger.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        settle()
        let after = page()
        XCTAssertTrue(Self.holds(after.text, startOf: before.text),
                      "left a page starting “\(before.text.prefix(12))”, now on \(after.first)…\(after.last)")
        XCTAssertLessThanOrEqual(after.first, before.first, "moved ahead: \(after.first), was at \(before.first)")
    }

    func testLayoutSwitchKeepsPlace() {
        turnForward(3)
        let before = page()
        openAppearance()
        let scroll = app.buttons["aa.turn.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "the Aa sheet never opened")
        scroll.tap()
        settle()
        // The scroll lands on the paragraph holding the page's first character, which is this one
        // or the one before it, so this one starts near the top.
        let marker = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", before.first.marker)).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "\(before.first) isn't in the scroll")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(marker.frame.minY, window.minY, "\(before.first) is above the screen")
        XCTAssertLessThan(marker.frame.minY, window.midY,
                          "\(before.first) isn't near the top; the scroll shows \(shownMarkers()), the page started “\(before.text.prefix(16))”")

        // And back: the page holds the paragraph the scroll had at the top.
        let relay = app.buttons["aa.turn.relay"]
        XCTAssertTrue(relay.waitForExistence(timeout: 5), "the Aa sheet closed")
        relay.tap()
        settle()
        let back = page()
        let read = before.first
        XCTAssertTrue(back.places.contains { $0.chapter == read.chapter && $0.paragraph >= read.paragraph - 1
            && $0.paragraph <= read.paragraph }, "left \(read) for the scroll, came back to \(back.first)…\(back.last)")
        XCTAssertLessThanOrEqual(back.first, read, "came back ahead: \(back.first), was at \(read)")
    }

    func testReopensOnSamePage() {
        turnForward(2)
        // Past the save 500 ms after the last turn.
        settle()
        let left = page()

        app.terminate()
        app.launchArguments = ["-DemoData", "YES", "-DemoKeep", "YES", "-DemoLayout", "paged",
                               "-DemoTab", "shelf", "-DemoReader", "1"]
        app.launch()
        XCTAssertTrue(page(containing: "〔\(left.first.chapter)·").waitForExistence(timeout: 60),
                      "reopened somewhere other than chapter \(left.first.chapter)")
        settle()
        let reopened = page()
        XCTAssertEqual(reopened.first, left.first, "left at \(left.first), reopened at \(reopened.first)")
        XCTAssertEqual(reopened.text, left.text, "reopened on another page around \(left.first)")
    }

    /// The scroll's paragraphs on screen, top first, with their tops.
    private func shownMarkers() -> String {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "〔")).allElementsBoundByIndex
            .filter { $0.isHittable }
            .prefix(4)
            .map { "\(String($0.label.prefix(11)))@\(Int($0.frame.minY))" }
            .joined(separator: ", ")
    }

    private var pages: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "paged.page")
    }

    private func page(containing text: String) -> XCUIElement {
        pages.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Mid-height, clear of the left edge's brightness strip.
    private func tap(atX x: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
    }

    private func turnForward(_ count: Int) {
        for _ in 0..<count {
            tap(atX: 0.9)
            Thread.sleep(forTimeInterval: 1.2)
        }
        settle()
    }

    private func openAppearance() {
        tap(atX: 0.5)
        let appearance = app.buttons["chrome.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5), "the chrome never showed")
        appearance.tap()
    }

    private struct Place: Comparable, CustomStringConvertible {
        var chapter: Int
        var paragraph: Int

        var next: Place { Place(chapter: chapter, paragraph: paragraph + 1) }
        var marker: String { "〔\(chapter)·\(paragraph)〕" }
        var description: String { marker }

        static func < (a: Place, b: Place) -> Bool { (a.chapter, a.paragraph) < (b.chapter, b.paragraph) }
    }

    private struct Shown {
        var text: String
        /// Every marker on the page, in order; never empty.
        var places: [Place]
        var first: Place { places[0] }
        var last: Place { places[places.count - 1] }
    }

    private func page(file: StaticString = #filePath, line: UInt = #line) -> Shown {
        let element = pages.firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "no page on screen", file: file, line: line)
        let text = element.label
        let places = Self.places(in: text)
        guard !places.isEmpty else {
            XCTFail("no marker on the page “\(text.prefix(40))”", file: file, line: line)
            return Shown(text: text, places: [Place(chapter: 0, paragraph: 0)])
        }
        return Shown(text: text, places: places)
    }

    /// A marker cut off by the page's end isn't counted.
    private static func places(in text: String) -> [Place] {
        text.components(separatedBy: "〔").dropFirst().compactMap { part in
            guard let close = part.firstIndex(of: "〕") else { return nil }
            let numbers = part[..<close].split(separator: "·")
            guard numbers.count == 2, let chapter = Int(numbers[0]), let paragraph = Int(numbers[1]) else { return nil }
            return Place(chapter: chapter, paragraph: paragraph)
        }
    }

    /// True when `page` holds the first character of `earlier`: the text `earlier` opens with is
    /// on it, whole or cut off by the page's end.
    private static func holds(_ page: String, startOf earlier: String) -> Bool {
        let opening = String(earlier.prefix(10))
        guard !opening.isEmpty else { return false }
        if page.contains(opening) { return true }
        return (min(3, opening.count)...opening.count).contains { page.hasSuffix(opening.prefix($0)) }
    }

    /// Lets the turn, the save after it and any chapter layout finish.
    private func settle() {
        Thread.sleep(forTimeInterval: 2.5)
    }
}
