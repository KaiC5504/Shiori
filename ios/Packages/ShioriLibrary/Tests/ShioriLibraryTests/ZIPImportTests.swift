import Foundation
import Testing
@testable import ShioriLibrary

@Test func decodesGBKNames() async throws {
    let env = try TestEnvironment()
    func gbk(_ name: String) throws -> Data {
        try #require(name.data(using: TextDecoding.gb18030))
    }
    func body(_ chapters: Int) -> Data {
        Data((1...chapters).map { "第\($0)章 节\($0)\n正文。" }.joined(separator: "\n").utf8)
    }
    let zip = try env.writeRawZIP(name: "合集.zip", entries: [
        // As Chinese Windows writes them: GBK, flag off, folder included.
        (name: try gbk("小说/第一卷(作者甲).txt"), utf8Flag: false, data: body(1)),
        (name: Data("小说/第二卷(作者甲).txt".utf8), utf8Flag: true, data: body(2)),
        // UTF-8 without the flag, as some older tools write them.
        (name: Data("第三卷(作者甲).txt".utf8), utf8Flag: false, data: body(3)),
    ])

    let outcomes = await env.importer.importFiles(at: zip, origin: .picker, settings: .default)
    let titles = outcomes.compactMap { outcome -> String? in
        if case .added(_, let title) = outcome { title } else { nil }
    }
    #expect(titles == ["第一卷", "第二卷", "第三卷"], "\(outcomes)")
    let books = try env.db.bookList().map(\.book)
    #expect(Set(books.map(\.originalFileName)) == ["第一卷(作者甲).txt", "第二卷(作者甲).txt", "第三卷(作者甲).txt"])
    #expect(books.allSatisfy { $0.author == "作者甲" })

    let log = try env.db.importLog(limit: 5)
    #expect(log.count == 1)
    #expect(log.first?.outcomes == outcomes)
    #expect(try env.stagingIsEmpty())
}

@Test func zipNamesAreUTF8WhenValidElseGB18030() throws {
    #expect(ZIPNames.decode(try #require("第一卷.txt".data(using: TextDecoding.gb18030))) == "第一卷.txt")
    #expect(ZIPNames.decode(Data("第一卷.txt".utf8)) == "第一卷.txt")
    #expect(ZIPNames.decode(Data("plain.txt".utf8)) == "plain.txt")
}

@Test func skipsNestedZip() async throws {
    let env = try TestEnvironment()
    let epub = try Data(contentsOf: try env.writeEPUB(chapters: 2))
    let zip = try env.writeZIP(name: "打包.zip", entries: [
        (path: "书/测试书.epub", data: epub),
        (path: "书/内层.zip", data: Data("PK".utf8)),
        (path: "__MACOSX/书/._测试书.epub", data: Data([0, 5, 22, 7])),
        (path: "书/说明.md", data: Data("说明".utf8)),
    ])

    let outcomes = await env.importer.importFiles(at: zip, origin: .watchedFolder, settings: .default)
    #expect(outcomes.count == 2, "\(outcomes)")
    guard case .added(_, let title)? = outcomes.first else { Issue.record("\(outcomes)"); return }
    #expect(title == "测试书")
    #expect(outcomes.last == .skipped(fileName: "内层.zip", reason: .nestedArchive))
    #expect(try env.db.bookList().count == 1)
    #expect(try env.stagingIsEmpty())
}

@Test func zipWithoutBooksFails() async throws {
    let env = try TestEnvironment()
    let zip = try env.writeZIP(name: "图片.zip", entries: [(path: "封面.jpg", data: Data([0xFF, 0xD8, 0xFF]))])
    #expect(await env.importer.importFiles(at: zip, origin: .picker, settings: .default)
        == [.failed(fileName: "图片.zip", reason: .unsupportedFormat)])
    #expect(try env.bookFolderNames().isEmpty)
    #expect(try env.stagingIsEmpty())
}
