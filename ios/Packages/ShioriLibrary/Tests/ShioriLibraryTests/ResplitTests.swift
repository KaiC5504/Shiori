import Foundation
import Testing
@testable import ShioriLibrary

@Test func resplitKeepsProgressByKey() async throws {
    let env = try TestEnvironment()
    let text = "第一卷 起\n第一章 甲\n甲的正文。\n第二章 乙\n乙的正文。\n第二卷 承\n第三章 丙\n丙的正文。\n第四章 丁\n丁的正文。"
    let url = try env.writeTXT(name: "四章(某人).txt", text: text, encoding: .utf8)
    guard case .added(let id, _) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    #expect(try env.db.chapters(bookId: id).map(\.title) == ["第一章 甲", "第二章 乙", "第三章 丙", "第四章 丁"])
    try env.saveProgress(id, at: 2, offset: 3)

    // With the 第X卷 rule off, the volume lines become text, and the first one a preface
    // that moves every chapter down by one.
    let outcome = await env.importer.resplit(bookId: id, settings: .with(disabling: ["zh-volume"]))
    #expect(outcome == .resplit(bookId: id, title: "四章", chapters: 5))

    let chapters = try env.db.chapters(bookId: id)
    #expect(chapters.map(\.title) == ["", "第一章 甲", "第二章 乙", "第三章 丙", "第四章 丁"])
    #expect(chapters.allSatisfy { $0.volume == nil })
    let progress = try #require(try env.db.progress(bookId: id))
    #expect(progress.chapterIndex == 3)
    #expect(progress.keyTitle == "第三章 丙")
    #expect(progress.offset == 3)

    let book = try #require(try env.db.bookList().first?.book)
    #expect(book.chapterCount == 5)
    #expect(book.lastUpdatedAt == nil)
    #expect(try BookContentSource(book: book, paths: env.paths).content(of: chapters[2]).blocks
        == [.heading("第二章 乙", level: 2), .paragraph("乙的正文。"), .paragraph("第二卷 承")])
    let folders = try FileManager.default.contentsOfDirectory(atPath: env.paths.bookDirectory(id).path)
        .filter { $0.hasPrefix("chapters") }
    #expect(folders.count == 1)
    #expect(folders.first != "chapters")
    #expect(try env.db.importLog(limit: 1).first?.outcomes == [outcome])
}

@Test func encodingOverrideWins() async throws {
    // UTF-16 without a byte-order mark, which detection reads as GB18030 or Big5.
    let text = "第一章 开端\n这是开端的正文。\n第二章 继续\n这是继续的正文。\n"
    let utf16 = ImportSettings.with(encoding: .utf16)

    let picked = try TestEnvironment()
    let url = try picked.writeTXT(name: "无标记(某人).txt", text: text, encoding: .utf16LittleEndian)
    guard case .added(let id, _)? = await picked.importer.importFiles(at: url, origin: .picker, settings: utf16).first
    else { Issue.record("not added"); return }
    #expect(try picked.db.chapters(bookId: id).map(\.title) == ["第一章 开端", "第二章 继续"])

    // Imported with detection, then re-detected once the encoding is set.
    let fixed = try TestEnvironment()
    guard case .added(let garbled, _) = await fixed.importer.importFile(at: url) else { Issue.record("not added"); return }
    #expect(await fixed.importer.resplit(bookId: garbled, settings: utf16)
        == .resplit(bookId: garbled, title: "无标记", chapters: 2))
    #expect(try fixed.db.chapters(bookId: garbled).map(\.title) == ["第一章 开端", "第二章 继续"])
}

@Test func resplitIsTXTOnly() async throws {
    let env = try TestEnvironment()
    guard case .added(let id, _) = await env.importer.importFile(at: try env.writeEPUB(chapters: 2)) else {
        Issue.record("not added"); return
    }
    #expect(await env.importer.resplit(bookId: id, settings: .default)
        == .failed(fileName: "测试书.epub", reason: .unsupportedFormat))
    #expect(try env.db.chapters(bookId: id).count == 2)
}
