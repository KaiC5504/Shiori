import Foundation
import Testing
@testable import ShioriCore

@Test func splitsChineseChaptersWithPreface() {
    let text = "序言内容\n第一章 开始\n正文一\n第二章 继续\n正文二\n"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["", "第一章 开始", "第二章 继续"])
    #expect(ch.map(\.body) == ["序言内容", "正文一", "正文二"])
}
@Test func volumesTagFollowingChapters() {
    let text = "第一卷 风起\n第一章 甲\n内容\n第二卷 云涌\n第二章 乙\n内容"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第一章 甲", "第二章 乙"])
    #expect(ch.map(\.volume) == ["第一卷 风起", "第二卷 云涌"])
}
@Test func handlesCRLFIndentsAndFullWidthDigits() {
    let text = "\u{FEFF}第１２章　标题\r\n　　第一段\r\n\r\n　　第二段\r\n"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第１２章　标题"])
    #expect(ch.first?.body == "第一段\n第二段")
}
@Test func englishAndNumberedHeadings() {
    #expect(ChapterSplitter.split("Chapter 3: The Road\nText", rules: ChapterRule.presets).map(\.title) == ["Chapter 3: The Road"])
    #expect(ChapterSplitter.split("12. 回家\n内容", rules: ChapterRule.presets).map(\.title) == ["12. 回家"])
}
@Test func longLinesAreNotHeadings() {
    let line = "第一章" + String(repeating: "很", count: 60)
    #expect(ChapterSplitter.split(line + "\n内容", rules: ChapterRule.presets).map(\.title) == [""])
}
@Test func fallsBackToNumberedPartsAtLineBoundaries() {
    let text = (1...10).map { "第\($0)行" + String(repeating: "字", count: 5) }.joined(separator: "\n")
    let parts = ChapterSplitter.split(text, rules: [], fallbackLength: 20)
    #expect(parts.count > 1)
    #expect(parts.allSatisfy { $0.title.isEmpty })
    #expect(parts.map(\.body).joined(separator: "\n") == text)
}
@Test func numberedRuleDoesNotEatBodyLines() {
    let text = "第一章 甲\n他花了\n3.5万块买下它\n1、先去买菜\n结束"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第一章 甲"])
    #expect(ch.first?.body == "他花了\n3.5万块买下它\n1、先去买菜\n结束")
}
@Test func chapterWordInsideASentenceIsNotAHeading() {
    let text = "第一章 开始\n第一节课是数学课。\n第三回合，他终于赢了。"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第一章 开始"])
}
@Test func leadingTableOfContentsIsDropped() {
    let text = "第一章 甲\n第二章 乙\n第一章 甲\n正文甲\n第二章 乙\n正文乙"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第一章 甲", "第二章 乙"])
    #expect(ch.map(\.body) == ["正文甲", "正文乙"])
}
@Test func trailingHeadingKeepsItsEmptyChapter() {
    let ch = ChapterSplitter.split("第一章 甲\n正文\n第二章 乙", rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第一章 甲", "第二章 乙"])
    #expect(ch.map(\.body) == ["正文", ""])
}
@Test func volumeLinesOnlyFallBackToParts() {
    let ch = ChapterSplitter.split("第一卷 风起\n第二卷 云涌", rules: ChapterRule.presets)
    #expect(!ch.isEmpty)
    #expect(ch.map(\.body).joined(separator: "\n") == "第一卷 风起\n第二卷 云涌")
}
