import Foundation
import Testing
@testable import ShioriLibrary

@Test func txtPrefaceHasNoHeadingAndKeepsEveryLine() async throws {
    let env = try TestEnvironment()
    let url = try env.writeTXT(name: "书.txt", text: "　　前言一\r\n　　前言二\r\n第一章 甲\r\n内容", encoding: .utf8)
    guard case .added(let id, _) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    let book = try #require(try env.db.bookList().first?.book)
    let chapters = try env.db.chapters(bookId: id)
    let source = try BookContentSource(book: book, paths: env.paths)
    #expect(try source.content(of: chapters[0]).blocks == [.paragraph("前言一"), .paragraph("前言二")])
    #expect(try source.content(of: chapters[1]).plainText == "第一章 甲\n内容")
}
@Test func epubChapterWithoutHeadingGetsItsContentsTitle() throws {
    let blocks = BookContentSource.withHeading([.paragraph("甲")], title: "第一章")
    #expect(blocks == [.heading("第一章", level: 2), .paragraph("甲")])
    #expect(BookContentSource.withHeading([.heading("x", level: 1)], title: "第一章") == [.heading("x", level: 1)])
    #expect(BookContentSource.withHeading([.paragraph("甲")], title: "") == [.paragraph("甲")])
}
