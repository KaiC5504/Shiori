import Foundation
import Testing
@testable import ShioriCore

@Test func resolvesSiblingHref() {
    #expect(EPUBPath.resolve("chapter_1.xhtml", relativeTo: "EPUB/content.opf") == "EPUB/chapter_1.xhtml")
}
@Test func resolvesParentAndPercentEncoding() {
    #expect(EPUBPath.resolve("../Images/a%20b.jpg", relativeTo: "OEBPS/Text/c1.xhtml") == "OEBPS/Images/a b.jpg")
}
@Test func resolveDropsFragment() {
    #expect(EPUBPath.resolve("c1.xhtml#p3", relativeTo: "OEBPS/toc.ncx") == "OEBPS/c1.xhtml")
}
@Test func splitsFragment() {
    let parts = EPUBPath.split("c1.xhtml#p3")
    #expect(parts.path == "c1.xhtml" && parts.fragment == "p3")
}
