import CoreGraphics
import Foundation
@testable import ShioriLibrary
import ZIPFoundation

extension Book {
    static func fixture(title: String, addedAt seconds: TimeInterval) -> Book {
        Book(id: UUID(), title: title, author: nil, format: .epub, sourceIdentifier: nil,
             titleAuthorKey: "\(title.lowercased())|", contentHash: UUID().uuidString,
             originalFileName: "\(title).epub", addedAt: Date(timeIntervalSince1970: seconds),
             chapterCount: 0, hasCover: false)
    }
}

/// A throwaway library on disk with an in-memory database, plus a folder for source files.
struct TestEnvironment {
    let paths: LibraryPaths
    let db: LibraryDatabase
    let importer: BookImporter
    let sources: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shiori-tests-\(UUID().uuidString)")
        paths = LibraryPaths(root: root.appending(path: "Library"))
        try paths.prepare()
        sources = root.appending(path: "Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        db = try LibraryDatabase.inMemory()
        importer = BookImporter(database: db, paths: paths)
    }

    /// Each file gets its own folder, so two books can share a file name, as downloads do.
    private func freshFolder() throws -> URL {
        let folder = sources.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func writeEPUB(chapters: Int, encrypted: Bool = false, fixedLayout: Bool = false) throws -> URL {
        let url = try freshFolder().appending(path: "测试书.epub")
        let content = (1...chapters).map { n in
            (title: "第\(n)章", volume: String?.none, paragraphs: ["第\(n)章的第一段。", "第二段。", "第三段。"])
        }
        try EPUBWriter.write(.init(title: "测试书", author: "测试", identifier: "test-\(UUID().uuidString)",
                                   chapters: content, coverJPEG: nil, fixedLayout: fixedLayout,
                                   encrypted: encrypted), to: url)
        return url
    }

    func writeTXT(name: String, text: String, encoding: String.Encoding) throws -> URL {
        guard let data = text.data(using: encoding) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return try writeFile(name: name, data: data)
    }

    func writeFile(name: String, data: Data) throws -> URL {
        let url = try freshFolder().appending(path: name)
        try data.write(to: url)
        return url
    }

    /// A ZIP that names itself an EPUB but has no `META-INF/container.xml`.
    func writeEPUBWithoutContainer() throws -> URL {
        let url = try freshFolder().appending(path: "无容器.epub")
        let archive = try Archive(url: url, accessMode: .create)
        let entries = [("mimetype", "application/epub+zip"),
                       ("EPUB/chapter_1.xhtml", "<html><body><p>甲</p></body></html>")]
        for (path, text) in entries {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: .none) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    /// One download of a book in SoNovel's shape. A later download passes the same
    /// `identifier` and a higher `revision`, which changes every chapter's first line.
    func writeEPUB(titles: [String], identifier: String, title: String = "测试书", author: String = "测试",
                   revision: Int = 1) throws -> URL {
        let url = try freshFolder().appending(path: "测试书.epub")
        let content = titles.enumerated().map { index, chapter in
            (title: chapter, volume: String?.none,
             paragraphs: ["\(chapter)，第\(revision)版。", "第\(index + 1)个文件的第二段。"])
        }
        try EPUBWriter.write(.init(title: title, author: author, identifier: identifier, chapters: content,
                                   coverJPEG: nil), to: url)
        return url
    }

    func writeZIP(name: String, entries: [(path: String, data: Data)]) throws -> URL {
        let url = try freshFolder().appending(path: name)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    /// A stored ZIP written byte by byte with raw entry names, because ZIPFoundation always
    /// writes UTF-8 names with the UTF-8 flag (bit 11) set, and Chinese Windows doesn't.
    func writeRawZIP(name: String, entries: [(name: Data, utf8Flag: Bool, data: Data)]) throws -> URL {
        func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let dosDate: UInt16 = (46 << 9) | (10 << 5) | 31  // 2026-10-31
        var body = Data()
        var directory = Data()
        for entry in entries {
            let offset = UInt32(body.count)
            let crc = entry.data.crc32(checksum: 0)
            let flags: UInt16 = entry.utf8Flag ? 1 << 11 : 0
            let size = UInt32(entry.data.count)

            append(UInt32(0x0403_4B50), to: &body)
            for field: UInt16 in [20, flags, 0, 0, dosDate] { append(field, to: &body) }
            for field: UInt32 in [crc, size, size] { append(field, to: &body) }
            append(UInt16(entry.name.count), to: &body)
            append(UInt16(0), to: &body)
            body.append(entry.name)
            body.append(entry.data)

            append(UInt32(0x0201_4B50), to: &directory)
            // Made by MS-DOS: no Unix mode bits, so an entry is a file unless its name ends in a slash.
            for field: UInt16 in [20, 20, flags, 0, 0, dosDate] { append(field, to: &directory) }
            for field: UInt32 in [crc, size, size] { append(field, to: &directory) }
            for field: UInt16 in [UInt16(entry.name.count), 0, 0, 0, 0] { append(field, to: &directory) }
            for field: UInt32 in [0, offset] { append(field, to: &directory) }
            directory.append(entry.name)
        }
        var end = Data()
        append(UInt32(0x0605_4B50), to: &end)
        for field: UInt16 in [0, 0, UInt16(entries.count), UInt16(entries.count)] { append(field, to: &end) }
        for field: UInt32 in [UInt32(directory.count), UInt32(body.count)] { append(field, to: &end) }
        append(UInt16(0), to: &end)

        let url = try freshFolder().appending(path: name)
        try (body + directory + end).write(to: url)
        return url
    }

    /// Two filled pages, with the title and author in the document's info when given.
    func writePDF(name: String, title: String?, author: String?, password: String? = nil) throws -> URL {
        let url = try freshFolder().appending(path: name)
        var info: [CFString: Any] = [:]
        if let title { info[kCGPDFContextTitle] = title }
        if let author { info[kCGPDFContextAuthor] = author }
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        var box = CGRect(x: 0, y: 0, width: 420, height: 595)
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for shade in [0.3, 0.6] {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: shade, green: 0.2, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 40, y: 40, width: 340, height: 515))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// Progress partway into chapter `index`, saved an hour ago so a later update is newer.
    @discardableResult
    func saveProgress(_ bookId: UUID, at index: Int, offset: Int) throws -> ShioriLibrary.Progress {
        let chapters = try db.chapters(bookId: bookId)
        let chapter = chapters[index]
        let progress = Progress(bookId: bookId, chapterIndex: index, keyTitle: chapter.keyTitle,
                                keyOccurrence: chapter.keyOccurrence, offset: offset,
                                fraction: (Double(index) + 0.5) / Double(chapters.count),
                                updatedAt: Date(timeIntervalSinceNow: -3600))
        try db.save(progress)
        return progress
    }

    /// Everything in `Books/`, sorted: book folders and any `<id>.<state>` left beside them.
    func bookFolderNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: paths.books.path).sorted()
    }

    func stagingIsEmpty() throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: paths.staging.path).isEmpty
    }
}

extension ImportSettings {
    static func with(encoding: TXTEncodingChoice = .auto, disabling ruleIDs: Set<String> = []) -> ImportSettings {
        var settings = ImportSettings.default
        settings.encoding = encoding
        settings.enabledRuleIDs.subtract(ruleIDs)
        return settings
    }
}
