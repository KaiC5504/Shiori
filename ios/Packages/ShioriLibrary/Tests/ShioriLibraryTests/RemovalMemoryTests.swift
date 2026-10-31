import Foundation
import Testing
@testable import ShioriLibrary

@Test func watchedFolderSkipsRemoved() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 3)
    guard case .added(let id, _) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    try env.saveProgress(id, at: 1, offset: 0)

    try await env.importer.remove(bookId: id)
    #expect(try env.db.bookList().isEmpty)
    #expect(try env.db.chapters(bookId: id).isEmpty)
    #expect(try env.db.progress(bookId: id) == nil)
    #expect(try env.bookFolderNames().isEmpty)

    #expect(await env.importer.importFiles(at: url, origin: .watchedFolder, settings: .default)
        == [.skipped(fileName: "测试书.epub", reason: .removedEarlier)])
    #expect(try env.db.bookList().isEmpty)
    #expect(try env.bookFolderNames().isEmpty)
    #expect(try env.stagingIsEmpty())
}

@Test func pickerReAddsRemoved() async throws {
    let env = try TestEnvironment()
    let titles = ["第1章", "第2章"]
    let v1 = try env.writeEPUB(titles: titles, identifier: "picked-again")
    guard case .added(let first, _) = await env.importer.importFile(at: v1) else { Issue.record("not added"); return }
    try await env.importer.remove(bookId: first)

    guard case .added(let second, _)? = await env.importer.importFiles(at: v1, origin: .picker, settings: .default).first
    else { Issue.record("the picker didn't re-add it"); return }
    #expect(second != first)
    // Brought back by hand, it's no longer remembered as removed, so the folder updates it.
    let v2 = try env.writeEPUB(titles: titles + ["第3章"], identifier: "picked-again", revision: 2)
    #expect(await env.importer.importFiles(at: v2, origin: .watchedFolder, settings: .default)
        == [.updated(bookId: second, title: "测试书", change: .addedChapters(1))])

    try await env.importer.remove(bookId: second)
    guard case .added? = await env.importer.importFiles(at: v1, origin: .openIn, settings: .default).first
    else { Issue.record("Open in didn't re-add it"); return }
    #expect(try env.db.bookList().count == 1)
}

@Test func newerDownloadOfRemovedBookIsSkippedFromFolder() async throws {
    let env = try TestEnvironment()
    let identifier = "trxs-https://example.invalid/tongren/2/1.html"
    let v1 = try env.writeEPUB(titles: ["第1章", "第2章"], identifier: identifier)
    guard case .added(let id, _) = await env.importer.importFile(at: v1) else { Issue.record("not added"); return }
    try await env.importer.remove(bookId: id)

    let v2 = try env.writeEPUB(titles: ["第1章", "第2章", "第3章"], identifier: identifier, revision: 2)
    #expect(await env.importer.importFiles(at: v2, origin: .watchedFolder, settings: .default)
        == [.skipped(fileName: "测试书.epub", reason: .removedEarlier)])

    // A TXT has no identifier, so its title and author are what's remembered.
    let txt1 = try env.writeTXT(name: "残卷(佚名).txt", text: "第1章 始\n正文", encoding: .utf8)
    guard case .added(let txtId, _) = await env.importer.importFile(at: txt1) else { Issue.record("TXT not added"); return }
    try await env.importer.remove(bookId: txtId)
    let txt2 = try env.writeTXT(name: "残卷(佚名).txt", text: "第1章 始\n正文\n第2章 续\n正文", encoding: .utf8)
    #expect(await env.importer.importFiles(at: txt2, origin: .watchedFolder, settings: .default)
        == [.skipped(fileName: "残卷(佚名).txt", reason: .removedEarlier)])

    #expect(try env.db.bookList().isEmpty)
    #expect(try env.bookFolderNames().isEmpty)
}

@Test func interruptedRemovalIsSettledOnLaunch() async throws {
    let env = try TestEnvironment()
    guard case .added(let id, _) = await env.importer.importFile(at: try env.writeEPUB(chapters: 2)) else {
        Issue.record("not added"); return
    }
    let fm = FileManager.default
    // Killed after the folder was moved aside but before the rows went: the book stays.
    try fm.moveItem(at: env.paths.bookDirectory(id), to: env.paths.removedFolder(of: id))
    // Killed after the rows went but before the folder did: the folder goes.
    try fm.createDirectory(at: env.paths.removedFolder(of: UUID()), withIntermediateDirectories: true)

    try await env.importer.cleanStaging()
    #expect(try env.bookFolderNames() == [id.uuidString])
    let book = try #require(try env.db.bookList().first?.book)
    let chapters = try env.db.chapters(bookId: id)
    #expect(try BookContentSource(book: book, paths: env.paths).content(of: chapters[1]).blocks.first
        == .heading("第2章", level: 2))
}
