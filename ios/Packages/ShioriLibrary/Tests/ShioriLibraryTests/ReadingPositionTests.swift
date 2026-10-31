import Foundation
import Testing
@testable import ShioriLibrary

private let bookId = UUID()

private func makeChapters(_ count: Int) -> [Chapter] {
    (0..<count).map { n in
        Chapter(bookId: bookId, index: n, title: "第\(n + 1)章", volume: nil, keyTitle: "第\(n + 1)章",
                keyOccurrence: 0, source: "OEBPS/c\(n).xhtml")
    }
}

private func makeContent(blocks: Int) -> ChapterContent {
    ChapterContent(blocks: [.heading("第一章", level: 2)] + (1..<blocks).map { .paragraph("第\($0)段，山间的风。") })
}

private func saved(index: Int, keyTitle: String) -> ShioriLibrary.Progress {
    ShioriLibrary.Progress(bookId: bookId, chapterIndex: index, keyTitle: keyTitle, keyOccurrence: 0, offset: 0,
                           fraction: 0, updatedAt: Date(timeIntervalSince1970: 0))
}

@Test func fractionCountsChaptersAndBlocks() {
    let chapters = makeChapters(4)
    let content = makeContent(blocks: 10)
    let now = Date(timeIntervalSince1970: 1_000)
    let progress = ReadingPosition.progress(bookId: bookId, chapter: chapters[2], chapterCount: 4,
                                            content: content, block: 5, now: now)
    #expect(progress.fraction == 0.625)
    #expect(progress.chapterIndex == 2)
    #expect(progress.keyTitle == "第3章")
    #expect(progress.offset == content.offset(ofBlock: 5))
    #expect(progress.updatedAt == now)
}

@Test func restoresByKeyWhenIndexMoved() {
    // A re-import put two new chapters in front of the one being read.
    let chapters = makeChapters(10)
    #expect(ReadingPosition.chapterIndex(for: saved(index: 3, keyTitle: "第6章"), in: chapters) == 5)
}

@Test func fallsBackToClampedIndex() {
    let chapters = makeChapters(10)
    #expect(ReadingPosition.chapterIndex(for: saved(index: 99, keyTitle: "不存在的章"), in: chapters) == 9)
}

@Test func blockFromOffsetRoundTrips() {
    let chapters = makeChapters(3)
    let content = makeContent(blocks: 6)
    let progress = ReadingPosition.progress(bookId: bookId, chapter: chapters[1], chapterCount: 3,
                                            content: content, block: 2, now: Date(timeIntervalSince1970: 0))
    #expect(ReadingPosition.block(for: progress, in: content) == 2)
}
