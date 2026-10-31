import CoreGraphics
import CoreText
import Foundation
import ShioriCore
import Testing
@testable import ShioriLibrary

private let bookId = UUID()
private let phone = PageSize(width: 390, height: 640)

/// Generated text with the shapes real chapters have: headings, an illustration, an empty
/// paragraph, Latin words, an emoji (two UTF-16 units) and a paragraph already indented.
private func generatedChapter(paragraphs: Int = 60) -> ChapterContent {
    let characters = Array("山水风月花鸟云雨春秋天地日星江河湖海林木竹石")
    var blocks: [ChapterBlock] = [.heading("第七章 生成的样章", level: 2)]
    for n in 0..<paragraphs {
        var text = n == 10 ? "\u{3000}\u{3000}" : ""
        text += "第\(n + 1)段，"
        for i in 0..<(30 + (n * 37) % 120) {
            text.append(characters[(n * 7 + i * 3) % characters.count])
            if i % 23 == 22 { text += "，" }
        }
        if n % 9 == 4 { text += " Shiori 0.\(n) 🌸" }
        blocks.append(.paragraph(text + "。"))
        if n == 20 { blocks.append(.image(path: "OEBPS/images/fig.png")) }
        if n == 30 { blocks.append(.paragraph("")) }
        if n == 40 { blocks.append(.heading("小节", level: 3)) }
    }
    return ChapterContent(blocks: blocks)
}

private func key(size: Double, page: PageSize = phone) -> PaginationKey {
    var typography = ReaderTypography.default
    typography.size = size
    return PaginationKey(bookId: bookId, chapter: ChapterKey(title: "第七章", occurrence: 0),
                         typography: typography, size: page)
}

/// The pages tile the chapter, each frame shows exactly its page, and no page starts inside
/// a surrogate pair.
private func expectTiles(_ layout: ChapterLayout, _ content: ChapterContent,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    let units = Array(content.plainText.utf16)
    #expect(layout.attributedText.string == content.plainText, sourceLocation: sourceLocation)
    #expect(layout.pages.first?.range.lowerBound == 0, sourceLocation: sourceLocation)
    #expect(layout.pages.last?.range.upperBound == units.count, sourceLocation: sourceLocation)
    for (index, page) in layout.pages.enumerated() {
        #expect(page.index == index, sourceLocation: sourceLocation)
        #expect(!page.range.isEmpty, sourceLocation: sourceLocation)
        if index > 0 {
            #expect(page.range.lowerBound == layout.pages[index - 1].range.upperBound, sourceLocation: sourceLocation)
        }
        let visible = CTFrameGetVisibleStringRange(layout.frame(forPage: index))
        #expect(visible.location == page.range.lowerBound && visible.length == page.range.count,
                "page \(index) draws \(visible) for \(page.range)", sourceLocation: sourceLocation)
        #expect(!UTF16.isTrailSurrogate(units[page.range.lowerBound]), sourceLocation: sourceLocation)
    }
}

@Test func pagesCoverChapterContiguously() {
    let content = generatedChapter()
    let paginator = Paginator(cache: PaginationCache())
    for size in [10.0, 18, 27] {
        let layout = paginator.layout(content, key: key(size: size))
        #expect(layout.pages.count > 1)
        expectTiles(layout, content)
        let margins = ReaderTypography.default.margins
        let box = CGRect(x: margins.left, y: margins.bottom, width: phone.width - margins.left - margins.right,
                         height: phone.height - margins.top - margins.bottom)
        #expect(CTFrameGetPath(layout.frame(forPage: 0)).boundingBox == box)
        #expect(layout.textRect == CGRect(x: margins.left, y: margins.top, width: box.width, height: box.height))
    }
}

@Test func linesTileEachPageInReadingOrder() {
    let content = generatedChapter()
    let layout = Paginator(cache: PaginationCache()).layout(content, key: key(size: 18))
    for page in layout.pages {
        let lines = layout.lines(onPage: page.index)
        #expect(lines.first?.range.lowerBound == page.range.lowerBound)
        #expect(lines.last?.range.upperBound == page.range.upperBound)
        for (above, below) in zip(lines, lines.dropFirst()) {
            #expect(above.range.upperBound == below.range.lowerBound)
            #expect(above.bounds.minY < below.bounds.minY)
        }
        for line in lines {
            #expect(line.block == content.block(containing: line.range.lowerBound))
        }
        let paragraphs = layout.paragraphs(onPage: page.index)
        #expect(paragraphs.flatMap(\.lines).count == lines.count)
        #expect(zip(paragraphs, paragraphs.dropFirst()).allSatisfy { $0.block < $1.block })
    }
}

@Test func pageContainingRoundTrips() {
    let content = generatedChapter()
    let layout = Paginator(cache: PaginationCache()).layout(content, key: key(size: 18))
    for page in layout.pages {
        #expect(layout.page(containing: page.range.lowerBound) == page.index)
        #expect(layout.page(containing: (page.range.lowerBound + page.range.upperBound) / 2) == page.index)
        #expect(layout.page(containing: page.range.upperBound - 1) == page.index)
    }
    #expect(layout.page(containing: -10) == 0)
    #expect(layout.page(containing: content.plainText.utf16.count + 50) == layout.pages.count - 1)
}

@Test func offsetSurvivesRelayout() {
    let content = generatedChapter()
    let paginator = Paginator(cache: PaginationCache())
    let small = paginator.layout(content, key: key(size: 18))
    let large = paginator.layout(content, key: key(size: 24))
    #expect(large.pages.count > small.pages.count)
    #expect(large.attributedText.string == small.attributedText.string)
    for page in small.pages {
        let offset = page.range.lowerBound
        let landed = large.pages[large.page(containing: offset)]
        #expect(landed.range.contains(offset), "page \(page.index)'s start \(offset) fell outside \(landed.range)")
    }

    // The reader keeps one anchor through several size changes and a rotation, rather than
    // re-anchoring on each new page's start, which would drift back a little every time.
    let anchor = small.pages[small.pages.count / 2].range.lowerBound + 5
    let changes: [(Double, PageSize)] = [(19, phone), (21, phone), (24, phone), (12, phone), (27, phone),
                                         (18, PageSize(width: phone.height, height: phone.width))]
    for (size, page) in changes {
        let layout = paginator.layout(content, key: key(size: size, page: page))
        expectTiles(layout, content)
        #expect(layout.pages[layout.page(containing: anchor)].range.contains(anchor))
    }
}

@Test func cacheHitReturnsSameLayout() {
    let content = generatedChapter()
    let paginator = Paginator(cache: PaginationCache())
    let first = paginator.layout(content, key: key(size: 18))
    #expect(paginator.layout(content, key: key(size: 18)) === first)
    #expect(paginator.layout(content, key: key(size: 20)) !== first)
    #expect(paginator.layout(content, key: key(size: 18, page: PageSize(width: 391, height: 640))) !== first)

    let updated = ChapterContent(blocks: content.blocks + [.paragraph("更新后新增的一段。")])
    let relaid = paginator.layout(updated, key: key(size: 18))
    #expect(relaid !== first)
    #expect(relaid.attributedText.string == updated.plainText)
}

@Test func emptyUnsizedAndTinyPagesStillTile() {
    let paginator = Paginator(cache: PaginationCache())
    let empty = paginator.layout(ChapterContent(blocks: []), key: key(size: 18))
    #expect(empty.pages == [Page(index: 0, range: 0..<0)])
    #expect(empty.page(containing: 5) == 0)
    #expect(empty.lines(onPage: 0).isEmpty)

    let content = generatedChapter(paragraphs: 8)
    let unsized = paginator.layout(content, key: key(size: 18, page: PageSize(width: 0, height: 0)))
    #expect(unsized.pages == [Page(index: 0, range: 0..<content.plainText.utf16.count)])

    // Shorter than one 27 pt line: every page still holds text and shows all of it.
    let tiny = paginator.layout(content, key: key(size: 27, page: PageSize(width: 390, height: 70)))
    expectTiles(tiny, content)
}

@Test func linkedMarginsUseOneValue() {
    var typography = ReaderTypography.default
    typography.margins = Margins(left: 40, right: 10, top: 5, bottom: 0)
    typography.marginsLinked = true
    #expect(TypographyAttributes.margins(typography) == Margins(left: 40, right: 40, top: 40, bottom: 40))
    typography.marginsLinked = false
    #expect(TypographyAttributes.margins(typography) == typography.margins)
}
