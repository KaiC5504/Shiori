import Foundation
import Testing
@testable import ShioriLibrary

@Test func importsEPUBAndDedupes() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 3)
    guard case .added(let id, let title) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    #expect(title == "测试书")
    #expect(try env.db.chapters(bookId: id).map(\.title) == ["第1章", "第2章", "第3章"])
    #expect(await env.importer.importFile(at: url) == .alreadyInLibrary(bookId: id, title: "测试书"))
}
@Test func concurrentImportsOfSameFileAddOnce() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 2)
    async let a = env.importer.importFile(at: url)
    async let b = env.importer.importFile(at: url)
    let outcomes = await [a, b]
    #expect(outcomes.filter { if case .added = $0 { true } else { false } }.count == 1)
    #expect(try env.db.bookList().count == 1)
}
@Test func importsGB18030TXTWithFileNameMetadata() async throws {
    let env = try TestEnvironment()
    let url = try env.writeTXT(name: "岳阳楼记(范仲淹).txt", text: "序\n第一章 庆历\n正文\n第二章 洞庭\n正文", encoding: TextDecoding.gb18030)
    guard case .added(let id, let title) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    #expect(title == "岳阳楼记")
    let book = try #require(try env.db.bookList().first?.book)
    #expect(book.author == "范仲淹")
    let chapters = try env.db.chapters(bookId: id)
    #expect(chapters.map(\.title) == ["", "第一章 庆历", "第二章 洞庭"])
    let content = try BookContentSource(book: book, paths: env.paths).content(of: chapters[1])
    #expect(content.blocks == [.heading("第一章 庆历", level: 2), .paragraph("正文")])
}
@Test func rejectsDRMFixedLayoutEmptyAndUnsupported() async throws {
    let env = try TestEnvironment()
    #expect(await env.importer.importFile(at: try env.writeEPUB(chapters: 1, encrypted: true)) == .failed(fileName: "测试书.epub", reason: .drmProtected))
    #expect(await env.importer.importFile(at: try env.writeEPUB(chapters: 1, fixedLayout: true)) == .failed(fileName: "测试书.epub", reason: .fixedLayout))
    #expect(await env.importer.importFile(at: try env.writeTXT(name: "空.txt", text: "", encoding: .utf8)) == .failed(fileName: "空.txt", reason: .empty))
    #expect(await env.importer.importFile(at: try env.writeTXT(name: "a.mobi", text: "x", encoding: .utf8)) == .failed(fileName: "a.mobi", reason: .unsupportedFormat))
}
@Test func failedImportLeavesNoFiles() async throws {
    let env = try TestEnvironment()
    _ = await env.importer.importFile(at: try env.writeEPUB(chapters: 1, encrypted: true))
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.books.path).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.staging.path).isEmpty)
}
@Test func failedImportsOfEveryKindLeaveNoFiles() async throws {
    let env = try TestEnvironment()
    let garbage = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
    let urls = [
        try env.writeFile(name: "乱码.epub", data: garbage),
        try env.writeEPUBWithoutContainer(),
        try env.writeTXT(name: "空.txt", text: "", encoding: .utf8),
    ]
    for url in urls {
        let outcome = await env.importer.importFile(at: url)
        guard case .failed = outcome else { Issue.record("\(url.lastPathComponent): \(outcome)"); continue }
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.books.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.staging.path).isEmpty)
    }
    #expect(try env.db.bookList().isEmpty)
}
@Test func cleanStagingRemovesLeftovers() async throws {
    let env = try TestEnvironment()
    try FileManager.default.createDirectory(at: env.paths.staging.appending(path: "orphan"), withIntermediateDirectories: true)
    try await env.importer.cleanStaging()
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.staging.path).isEmpty)
}
@Test func fiveThousandChapterBookImports() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 5_000)
    let start = Date()
    guard case .added(let id, _) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    print("5,000-chapter import took \(Date().timeIntervalSince(start)) s")
    #expect(try env.db.chapters(bookId: id).count == 5_000)
}
@Test func epubContentHasTheChapterHeadingAndKeysAreStable() async throws {
    let env = try TestEnvironment()
    guard case .added(let id, _) = await env.importer.importFile(at: try env.writeEPUB(chapters: 2)) else { Issue.record("not added"); return }
    let book = try #require(try env.db.bookList().first?.book)
    let chapters = try env.db.chapters(bookId: id)
    #expect(chapters.map(\.keyTitle) == ["第1章", "第2章"])
    #expect(chapters.map(\.source) == ["EPUB/chapter_1.xhtml", "EPUB/chapter_2.xhtml"])
    let content = try BookContentSource(book: book, paths: env.paths).content(of: chapters[1])
    #expect(content.blocks.first == .heading("第2章", level: 2))
    #expect(content.blocks.count == 4)
}
@Test func demoBooksImport() async throws {
    let env = try TestEnvironment()
    let urls = try DemoBooks.write(into: env.sources)
    #expect(urls.count == 3)
    for url in urls {
        guard case .added = await env.importer.importFile(at: url) else { Issue.record("\(url.lastPathComponent) not added"); return }
    }
    let list = try env.db.bookList()
    #expect(list.map(\.book.title) == ["兰亭集序", "岳阳楼记", "桃花源记"])
    let lanting = try env.db.chapters(bookId: list[0].book.id)
    #expect(Set(lanting.compactMap(\.volume)).count == 2)
    #expect(try env.db.chapters(bookId: list[2].book.id).count == 12)
    #expect(try env.db.chapters(bookId: list[1].book.id).first?.title == "")
}
@Test func importFilesLogsEachCallAsOneBatch() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 2)
    let first = await env.importer.importFiles(at: url, origin: .openIn, settings: .default)
    let second = await env.importer.importFiles(at: url, origin: .watchedFolder, settings: .default)
    let log = try env.db.importLog(limit: 10)
    #expect(log.map(\.origin) == [.watchedFolder, .openIn])
    #expect(log.map(\.outcomes) == [second, first])
}
@Test func importsPDFWithCoverAndAttributes() async throws {
    let env = try TestEnvironment()
    let url = try env.writePDF(name: "扫描件(某人).pdf", title: "图录", author: "编者")
    guard case .added(let id, let title)? = await env.importer.importFiles(at: url, origin: .picker, settings: .default).first
    else { Issue.record("not added"); return }
    #expect(title == "图录")
    let book = try #require(try env.db.bookList().first?.book)
    #expect(book.format == .pdf)
    #expect(book.author == "编者")
    #expect(book.chapterCount == 0)
    #expect(book.hasCover)
    let folder = env.paths.bookDirectory(id)
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "original.pdf").path))
    #expect(try Data(contentsOf: folder.appending(path: "cover.jpg")).starts(with: [0xFF, 0xD8]))

    // Without a title in the document, the file name gives the title and author.
    guard case .added(let untitledId, let fromName) = await env.importer.importFile(
        at: try env.writePDF(name: "无题(作者乙).pdf", title: nil, author: nil))
    else { Issue.record("untitled not added"); return }
    #expect(fromName == "无题")
    #expect(try env.db.bookList().first { $0.id == untitledId }?.book.author == "作者乙")

    let locked = try env.writePDF(name: "加密.pdf", title: nil, author: nil, password: "secret")
    #expect(await env.importer.importFile(at: locked) == .failed(fileName: "加密.pdf", reason: .drmProtected))
}
