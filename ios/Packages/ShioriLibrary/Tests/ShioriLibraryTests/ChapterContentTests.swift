import Foundation
import Testing
@testable import ShioriLibrary

@Test func offsetsMapBothWays() {
    let c = ChapterContent(blocks: [.heading("第一章", level: 2), .paragraph("甲乙"), .paragraph("丙")])
    #expect(c.plainText == "第一章\n甲乙\n丙")
    #expect(c.offset(ofBlock: 2) == 7)
    #expect(c.block(containing: 5) == 1)
    #expect(c.block(containing: 7) == 2)
    #expect(c.block(containing: 999) == 2)
}
@Test func imagesCountAsOneCharacterAndEmptyContentIsSafe() {
    let c = ChapterContent(blocks: [.image(path: "E/i.jpg"), .paragraph("甲")])
    #expect(c.plainText == "\u{FFFC}\n甲")
    #expect(c.offset(ofBlock: 1) == 2)
    let empty = ChapterContent(blocks: [])
    #expect(empty.block(containing: 10) == 0)
    #expect(empty.offset(ofBlock: 3) == 0)
}
