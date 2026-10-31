import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShioriLibrary

private struct NotImported: Error {}

private let platePath = "EPUB/images/plate.png"
private let garbagePath = "EPUB/images/garbage.png"
private let missingPath = "EPUB/images/missing.png"

private func png(width: Int, height: Int) throws -> Data {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }
    context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

/// An imported EPUB whose first chapter holds a 400×300 PNG under its heading, an entry of
/// garbage bytes after the first paragraph, and an `<img>` at the end whose file isn't there.
private func illustratedBook(plate: Data) async throws -> (source: BookContentSource, content: ChapterContent) {
    let env = try TestEnvironment()
    let folder = env.sources.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: "插图.epub")
    try EPUBWriter.write(.init(
        title: "插图", author: "测试", identifier: "test-\(UUID().uuidString)",
        chapters: [("第一章", nil, ["第一段。", "第二段。"]), ("第二章", nil, ["第三段。"])],
        coverJPEG: nil,
        illustrations: [
            .init(chapter: 0, href: "images/plate.png", data: plate),
            .init(chapter: 0, beforeParagraph: 1, href: "images/garbage.png", data: Data("not an image".utf8)),
            .init(chapter: 0, beforeParagraph: 2, href: "images/missing.png", data: nil),
        ]), to: url)
    guard case .added(let id, _) = await env.importer.importFile(at: url) else { throw NotImported() }
    let book = try #require(try env.db.bookList().first?.book)
    let chapters = try env.db.chapters(bookId: id)
    let source = try BookContentSource(book: book, paths: env.paths)
    return (source, try source.content(of: chapters[0]))
}

@Test func imageSizeReadsHeader() async throws {
    let (source, content) = try await illustratedBook(plate: try png(width: 400, height: 300))
    #expect(content.blocks == [.heading("第一章", level: 2), .image(path: platePath), .paragraph("第一段。"),
                               .image(path: garbagePath), .paragraph("第二段。"), .image(path: missingPath)])
    #expect(source.imageSize(at: platePath) == CGSize(width: 400, height: 300))
}

@Test func unreadableImageHasNoSize() async throws {
    let (source, _) = try await illustratedBook(plate: try png(width: 400, height: 300))
    #expect(source.imageSize(at: missingPath) == nil)
    #expect(source.imageSize(at: garbagePath) == nil)
    #expect(throws: (any Error).self) { try source.imageData(at: missingPath) }
}

@Test func imageDataRoundTrips() async throws {
    let plate = try png(width: 400, height: 300)
    let (source, _) = try await illustratedBook(plate: plate)
    #expect(try source.imageData(at: platePath) == plate)
    #expect(try source.imageData(at: garbagePath) == Data("not an image".utf8))
}

@Test func demoIllustrationsDecode() throws {
    for night in [false, true] {
        let jpeg = try #require(DemoBooks.illustration(width: 720, height: 960, night: night))
        #expect(BookContentSource.pixelSize(of: jpeg) == CGSize(width: 720, height: 960))
    }
}

@Test func txtBookHasNoImages() async throws {
    let env = try TestEnvironment()
    let url = try env.writeTXT(name: "书.txt", text: "第一章 甲\n内容", encoding: .utf8)
    guard case .added = await env.importer.importFile(at: url) else { throw NotImported() }
    let book = try #require(try env.db.bookList().first?.book)
    let source = try BookContentSource(book: book, paths: env.paths)
    #expect(source.imageSize(at: "anything.png") == nil)
    #expect(throws: BookContentError.unsupportedFormat) { try source.imageData(at: "anything.png") }
}
