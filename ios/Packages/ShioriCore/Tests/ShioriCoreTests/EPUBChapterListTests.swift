import Foundation
import Testing
@testable import ShioriCore

@Test func chapterListUsesDeepestTitleAndVolume() {
    let toc = [
        TOCEntry(title: "简介", path: "E/intro.xhtml", fragment: nil, children: []),
        TOCEntry(title: "第一卷", path: "E/c1.xhtml", fragment: nil, children: [
            TOCEntry(title: "第一章", path: "E/c1.xhtml", fragment: nil, children: []),
            TOCEntry(title: "第二章", path: "E/c2.xhtml", fragment: nil, children: []),
        ]),
    ]
    let chapters = EPUBChapterList.build(spine: ["E/intro.xhtml", "E/c1.xhtml", "E/c2.xhtml", "E/c3.xhtml"], toc: toc)
    #expect(chapters.map(\.title) == ["简介", "第一章", "第二章", ""])
    #expect(chapters.map(\.volume) == [nil, "第一卷", "第一卷", "第一卷"])
    #expect(chapters.map(\.index) == [0, 1, 2, 3])
}
