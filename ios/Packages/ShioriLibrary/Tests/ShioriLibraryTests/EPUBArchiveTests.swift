import Foundation
import ShioriCore
import Testing
@testable import ShioriLibrary

@Test func archiveRoundTripsWriterAndDetectsDRM() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).epub")
    try EPUBWriter.write(.init(title: "桃花源记", author: "陶渊明", identifier: "demo-1",
        chapters: [("第一章", nil, ["晋太元中，武陵人捕鱼为业。"])], coverJPEG: nil), to: url)
    let archive = try EPUBArchive(url: url)
    #expect(archive.contains("EPUB/content.opf"))
    #expect(archive.hasDRM == false)
    let locked = url.deletingLastPathComponent().appending(path: "\(UUID()).epub")
    try EPUBWriter.write(.init(title: "x", author: "y", identifier: "z", chapters: [("c", nil, ["p"])], coverJPEG: nil, encrypted: true), to: locked)
    #expect(try EPUBArchive(url: locked).hasDRM)
}
@Test func writerOutputParsesWithShioriCore() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).epub")
    try EPUBWriter.write(.init(title: "兰亭集序", author: "王羲之", identifier: "demo-3",
        chapters: [("第一章", "上卷", ["永和九年，岁在癸丑。"]), ("第二章", "上卷", ["群贤毕至。"]), ("第三章", "下卷", ["此地有崇山峻岭。"])],
        coverJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9])), to: url)
    let archive = try EPUBArchive(url: url)
    let opfPath = try ContainerParser.rootfilePath(from: try archive.data(at: "META-INF/container.xml"))
    let package = try PackageParser.parse(try archive.data(at: opfPath), packagePath: opfPath)
    #expect(package.metadata.title == "兰亭集序")
    #expect(package.coverPath.map(archive.contains) == true)
    let ncxPath = try #require(package.ncxPath)
    let toc = try TOCParser.ncx(try archive.data(at: ncxPath), basePath: ncxPath)
    let chapters = EPUBChapterList.build(spine: package.spine, toc: toc)
    #expect(chapters.map(\.title) == ["第一章", "第二章", "第三章"])
    #expect(chapters.map(\.volume) == ["上卷", "上卷", "下卷"])
    let navPath = try #require(package.navPath)
    #expect(try TOCParser.nav(try archive.data(at: navPath), basePath: navPath).map(\.title) == ["上卷", "下卷"])
    let html = String(decoding: try archive.data(at: chapters[1].path), as: UTF8.self)
    #expect(try XHTMLContentParser.blocks(from: html, documentPath: chapters[1].path) == [.heading("第二章", level: 2), .paragraph("群贤毕至。")])
}
