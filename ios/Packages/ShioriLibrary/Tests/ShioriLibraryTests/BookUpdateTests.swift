import Foundation
import Testing
@testable import ShioriLibrary

@Test func appendedChaptersKeepProgress() async throws {
    let env = try TestEnvironment()
    let identifier = "trxs-https://example.invalid/tongren/1/1.html"
    let v1 = try env.writeEPUB(titles: (1...5).map { "第\($0)章" }, identifier: identifier)
    guard case .added(let id, _) = await env.importer.importFile(at: v1) else { Issue.record("not added"); return }
    let saved = try env.saveProgress(id, at: 2, offset: 42)
    let before = try #require(try env.db.bookList().first?.book)

    let v2 = try env.writeEPUB(titles: (1...8).map { "第\($0)章" }, identifier: identifier, revision: 2)
    let outcomes = await env.importer.importFiles(at: v2, origin: .watchedFolder, settings: .default)
    #expect(outcomes == [.updated(bookId: id, title: "测试书", change: .addedChapters(3))])

    let list = try env.db.bookList()
    #expect(list.count == 1)
    let item = try #require(list.first)
    #expect(item.book.id == id)
    #expect(item.book.chapterCount == 8)
    #expect(item.book.lastUpdateAddedChapters == 3)
    #expect(item.book.addedAt == before.addedAt)
    #expect(item.book.contentHash != before.contentHash)
    #expect(item.showsUpdatedBadge)

    let progress = try #require(item.progress)
    #expect(progress.chapterIndex == 2)
    #expect(progress.keyTitle == "第3章")
    #expect(progress.keyOccurrence == 0)
    #expect(progress.offset == 42)
    #expect(abs(progress.updatedAt.timeIntervalSince(saved.updatedAt)) < 0.01)

    // The stored file was swapped: the chapters read the second download's text.
    let chapters = try env.db.chapters(bookId: id)
    let source = try BookContentSource(book: item.book, paths: env.paths)
    #expect(try source.content(of: chapters[2]).blocks.dropFirst().first == .paragraph("第3章，第2版。"))
    #expect(try source.content(of: chapters[7]).blocks.first == .heading("第8章", level: 2))
    #expect(try env.bookFolderNames() == [id.uuidString])
    #expect(try env.stagingIsEmpty())

    let batch = try #require(try env.db.importLog(limit: 1).first)
    #expect(batch.origin == .watchedFolder)
    #expect(batch.outcomes == outcomes)
}

@Test func repeatedTitlesRemapByOccurrence() async throws {
    let env = try TestEnvironment()
    let v1 = try env.writeEPUB(titles: ["序章", "第1章", "番外", "第2章", "番外", "第3章"], identifier: "repeats")
    guard case .added(let id, _) = await env.importer.importFile(at: v1) else { Issue.record("not added"); return }
    try env.saveProgress(id, at: 4, offset: 7)

    // A chapter inserted near the front moves the second 番外 from index 4 to 5, where index 4
    // is now 第2章.
    let v2 = try env.writeEPUB(titles: ["序章", "楔子", "第1章", "番外", "第2章", "番外", "第3章", "番外"],
                               identifier: "repeats", revision: 2)
    #expect(await env.importer.importFiles(at: v2, origin: .picker, settings: .default)
        == [.updated(bookId: id, title: "测试书", change: .addedChapters(2))])

    let progress = try #require(try env.db.progress(bookId: id))
    #expect(progress.chapterIndex == 5)
    #expect(progress.keyTitle == "番外")
    #expect(progress.keyOccurrence == 1)
    #expect(progress.offset == 7)
}

@Test func identifierMatchWithChangedTitleUpdates() async throws {
    let env = try TestEnvironment()
    let titles = (1...4).map { "第\($0)章" }
    let v1 = try env.writeEPUB(titles: titles, identifier: "same-source", title: "旧书名", author: "某甲")
    guard case .added(let id, _) = await env.importer.importFile(at: v1) else { Issue.record("not added"); return }
    try env.saveProgress(id, at: 3, offset: 5)

    let v2 = try env.writeEPUB(titles: titles, identifier: "same-source", title: "新书名", author: "某乙", revision: 2)
    #expect(await env.importer.importFiles(at: v2, origin: .watchedFolder, settings: .default)
        == [.updated(bookId: id, title: "新书名", change: .changed)])
    let list = try env.db.bookList()
    #expect(list.count == 1)
    let book = try #require(list.first?.book)
    #expect(book.title == "新书名")
    #expect(book.author == "某乙")
    #expect(book.lastUpdatedAt != nil)
    #expect(book.lastUpdateAddedChapters == nil)
    #expect(try env.db.progress(bookId: id)?.keyTitle == "第4章")

    // Another identifier is another source's copy, a separate book even with the same title.
    let elsewhere = try env.writeEPUB(titles: titles, identifier: "other-source", title: "新书名", author: "某乙")
    guard case .added(let otherId, _) = await env.importer.importFile(at: elsewhere) else { Issue.record("not added"); return }
    #expect(otherId != id)
}

@Test func sameHashIsAlreadyInLibrary() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(titles: ["第1章", "第2章"], identifier: "same-hash")
    guard case .added(let id, let title) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    let renamed = try env.writeFile(name: "改了名字.epub", data: try Data(contentsOf: url))

    #expect(await env.importer.importFiles(at: renamed, origin: .watchedFolder, settings: .default)
        == [.alreadyInLibrary(bookId: id, title: title)])
    let list = try env.db.bookList()
    #expect(list.count == 1)
    #expect(list.first?.book.lastUpdatedAt == nil)
    #expect(list.first?.book.originalFileName == "测试书.epub")
}

@Test func titleAuthorMatchForTXT() async throws {
    let env = try TestEnvironment()
    func text(chapters: Int) -> String {
        (1...chapters).map { "第\($0)章 夜\($0)\n这是第\($0)章的正文。" }.joined(separator: "\n")
    }
    let v1 = try env.writeTXT(name: "长夜(某人).txt", text: text(chapters: 3), encoding: .utf8)
    guard case .added(let id, _) = await env.importer.importFile(at: v1) else { Issue.record("not added"); return }
    try env.saveProgress(id, at: 1, offset: 3)

    let v2 = try env.writeTXT(name: "长夜(某人).txt", text: text(chapters: 5), encoding: TextDecoding.gb18030)
    #expect(await env.importer.importFiles(at: v2, origin: .watchedFolder, settings: .default)
        == [.updated(bookId: id, title: "长夜", change: .addedChapters(2))])
    let chapters = try env.db.chapters(bookId: id)
    #expect(chapters.count == 5)
    let progress = try #require(try env.db.progress(bookId: id))
    #expect(progress.chapterIndex == 1)
    #expect(progress.keyTitle == "第2章 夜2")
    #expect(progress.offset == 3)
    let book = try #require(try env.db.bookList().first?.book)
    #expect(try BookContentSource(book: book, paths: env.paths).content(of: chapters[4]).blocks
        == [.heading("第5章 夜5", level: 2), .paragraph("这是第5章的正文。")])

    // Another author is another book, and an EPUB never updates a TXT.
    let otherAuthor = try env.writeTXT(name: "长夜(别人).txt", text: text(chapters: 5), encoding: .utf8)
    guard case .added = await env.importer.importFile(at: otherAuthor) else { Issue.record("other author not added"); return }
    let epub = try env.writeEPUB(titles: ["第1章"], identifier: "long-night", title: "长夜", author: "某人")
    guard case .added = await env.importer.importFile(at: epub) else { Issue.record("EPUB not added"); return }
    #expect(try env.db.bookList().count == 3)
}

@Test func interruptedUpdateIsFinishedOnLaunch() async throws {
    let env = try TestEnvironment()
    guard case .added(let id, _) = await env.importer.importFile(at: try env.writeEPUB(chapters: 2)) else {
        Issue.record("not added"); return
    }
    let book = try #require(try env.db.bookList().first?.book)
    let fm = FileManager.default
    let current = env.paths.bookDirectory(id)

    // Killed mid-swap: the rows point at the pending version, and the old one was moved aside.
    let pending = env.paths.pendingVersion(of: id, hash: book.contentHash)
    try fm.copyItem(at: current, to: pending)
    try Data("new".utf8).write(to: pending.appending(path: "marker"))
    try fm.moveItem(at: current, to: env.paths.retiredVersion(of: id))
    // An update killed before its rows committed.
    try fm.createDirectory(at: env.paths.pendingVersion(of: id, hash: String(repeating: "0", count: 64)),
                           withIntermediateDirectories: true)

    try await env.importer.cleanStaging()
    #expect(try env.bookFolderNames() == [id.uuidString])
    #expect(fm.fileExists(atPath: current.appending(path: "marker").path))
    let chapters = try env.db.chapters(bookId: id)
    #expect(try BookContentSource(book: book, paths: env.paths).content(of: chapters[0]).blocks.first
        == .heading("第1章", level: 2))
}
