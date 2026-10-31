import Foundation
@testable import ShioriLibrary

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
        let url = try freshFolder().appending(path: name)
        guard let data = text.data(using: encoding) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        try data.write(to: url)
        return url
    }
}
