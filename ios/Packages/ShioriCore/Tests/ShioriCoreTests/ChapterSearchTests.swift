import Foundation
import Testing
@testable import ShioriCore

private let numerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三"]
/// "简介" at index 0, so chapter N (第N章) sits at index N, one after position N.
private let numbered = ["简介"] + numerals.map { "第\($0)章" }

@Test func emptyMatchesAll() {
    let titles = ["简介", "第一章 开始", "第二章 继续"]
    #expect(ChapterSearch.matches("", titles: titles) == [0, 1, 2])
    #expect(ChapterSearch.matches("   ", titles: titles) == [0, 1, 2])
    #expect(ChapterSearch.matches("", titles: []) == [])
}

@Test func textMatchesTitles() {
    let titles = ["简介", "第一章 转职仪式开始", "第二章 转职异象", "第三章 骷髅战士", "第四章 再次转职"]
    #expect(ChapterSearch.matches("转职", titles: titles) == [1, 2, 4])
    #expect(ChapterSearch.matches("龙", titles: titles) == [])
}

@Test func textIsCaseAndWidthInsensitive() {
    let titles = ["Prologue", "Chapter One: The Road", "chapter two", "Ｅｐｉｌｏｇｕｅ"]
    #expect(ChapterSearch.matches("CHAPTER", titles: titles) == [1, 2])
    #expect(ChapterSearch.matches("the  road", titles: titles) == [1])
    #expect(ChapterSearch.matches("epilogue", titles: titles) == [3])
}

@Test func numberMatchesChineseNumeral() {
    let titles = ["简介", "第三千六百二十四章 前夜", "第三千六百二十五章 决战", "第三千六百二十六章 余波"]
    #expect(ChapterSearch.matches("3625", titles: titles) == [2])
}

@Test func numberMatchesPosition() {
    #expect(ChapterSearch.matches("12", titles: numbered) == [11, 12])
    // A position past the end is no match.
    #expect(ChapterSearch.matches("99", titles: numbered) == [])
}

@Test func chineseNumeralQuery() {
    #expect(ChapterSearch.matches("十二", titles: numbered) == [11, 12])
}

@Test func fullWidthDigits() {
    #expect(ChapterSearch.matches("１２", titles: numbered) == ChapterSearch.matches("12", titles: numbered))
    #expect(ChapterSearch.matches("１２", titles: numbered) == [11, 12])
}

@Test func chapterFormQueryIsANumber() {
    #expect(ChapterSearch.matches("第12章", titles: numbered) == [11, 12])
    #expect(ChapterSearch.matches("第十二", titles: numbered) == [11, 12])
}

@Test func arabicNumberListsItsChapterThenTitlesHoldingIt() {
    let titles = (1...1300).map { "第\($0)章" }
    // 第120章 first, then 第1120章 and 第1200章–第1209章, in book order.
    #expect(ChapterSearch.matches("120", titles: titles) == [119, 1119] + Array(1199...1208))
}

@Test func numberMatchesOtherChapterUnits() {
    let titles = ["楔子", "第一回 宴桃园豪杰三结义", "第二回 张翼德怒鞭督邮", "第三节 余论"]
    #expect(ChapterSearch.matches("2", titles: titles).first == 1)
    #expect(ChapterSearch.matches("2", titles: titles).contains(2))
    #expect(ChapterSearch.matches("3", titles: titles) == [2, 3])
}

@Test func numberInsideAVolumeTitle() {
    let titles = ["第一卷 第一章 起", "第一卷 第二章 承"]
    #expect(ChapterSearch.chapterNumber(in: "第一卷 第二章 承") == 2)
    #expect(ChapterSearch.matches("2", titles: titles) == [1])
}

@Test func parsesChineseNumerals() {
    #expect(ChapterSearch.number("三千六百二十五") == 3625)
    #expect(ChapterSearch.number("十") == 10)
    #expect(ChapterSearch.number("十二") == 12)
    #expect(ChapterSearch.number("二十") == 20)
    #expect(ChapterSearch.number("一百零五") == 105)
    #expect(ChapterSearch.number("一千零一十") == 1010)
    #expect(ChapterSearch.number("一千零十") == 1010)
    #expect(ChapterSearch.number("零") == 0)
    #expect(ChapterSearch.number("两百") == 200)
    #expect(ChapterSearch.number("一万二千") == 12000)
    #expect(ChapterSearch.number("二〇二四") == 2024)
    #expect(ChapterSearch.number("0042") == 42)
    #expect(ChapterSearch.number("") == nil)
    #expect(ChapterSearch.number("十二a") == nil)
    #expect(ChapterSearch.number("12345678901234567890") == nil)
}

@Test func preparedIndexAgreesWithMatches() {
    let index = ChapterSearch.Index(titles: numbered)
    for query in ["", "12", "十二", "第", "章", "简介", "x"] {
        #expect(index.matches(query) == ChapterSearch.matches(query, titles: numbered))
    }
}
