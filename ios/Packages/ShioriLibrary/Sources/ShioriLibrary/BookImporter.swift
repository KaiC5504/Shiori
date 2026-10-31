import CryptoKit
import Foundation
import os
import ShioriCore

/// Copies a file into the library and indexes it (spec §8.3). An actor whose import runs
/// without suspending, so imports happen one at a time: a second tap, or the same file
/// twice in one batch, finds the first copy when it deduplicates.
public actor BookImporter {
    private let database: LibraryDatabase
    private let paths: LibraryPaths
    private let rules: [ChapterRule]
    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "import")

    static let epubLimit: Int64 = 512 << 20
    static let txtLimit: Int64 = 128 << 20

    public init(database: LibraryDatabase, paths: LibraryPaths, rules: [ChapterRule] = ChapterRule.presets) {
        self.database = database
        self.paths = paths
        self.rules = rules
    }

    /// Removes half-built imports left by a crash or a kill; run on launch.
    /// One stuck item doesn't stop the rest; the first error is thrown once all were tried.
    public func cleanStaging() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.staging, withIntermediateDirectories: true)
        var firstError: Error?
        for item in try fm.contentsOfDirectory(at: paths.staging, includingPropertiesForKeys: nil) {
            do {
                try fm.removeItem(at: item)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    /// One outcome per book found: a ZIP can hold several.
    public func importFiles(at url: URL, origin: ImportOrigin, settings: ImportSettings) async -> [ImportOutcome] {
        [await importFile(at: url)]
    }

    public func remove(bookId: UUID) async throws {
        throw CocoaError(.featureUnsupported)
    }

    /// Splits a TXT book again with `settings`, keeping progress by chapter key.
    public func resplit(bookId: UUID, settings: ImportSettings) async -> ImportOutcome {
        .failed(fileName: "", reason: .unreadable("re-split is not built yet"))
    }

    public func importFile(at url: URL) async -> ImportOutcome {
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        do {
            return try importOrThrow(url)
        } catch let failure as ImportFailure {
            Self.log.error("import of .\(ext, privacy: .public) failed: \(String(describing: failure), privacy: .public)")
            return .failed(fileName: fileName, reason: failure)
        } catch {
            Self.log.error("import of .\(ext, privacy: .public) failed: \(Self.loggable(error), privacy: .public)")
            return .failed(fileName: fileName, reason: .unreadable(String(describing: error)))
        }
    }

    /// Cocoa and POSIX errors print the file's path, so for those only the domain and code
    /// are logged.
    private static func loggable(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain {
            return "\(ns.domain) \(ns.code)"
        }
        return String(describing: error)
    }

    private struct Parsed {
        var title: String
        var author: String?
        var identifier: String?
        var chapters: [(title: String, volume: String?, source: String)]
        var hasCover: Bool
    }

    private func importOrThrow(_ url: URL) throws -> ImportOutcome {
        let ext = url.pathExtension.lowercased()
        let format: BookFormat
        switch ext {
        case "epub": format = .epub
        case "txt": format = .txt
        default: throw ImportFailure.unsupportedFormat
        }
        let limit = format == .epub ? Self.epubLimit : Self.txtLimit
        let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size <= limit else { throw ImportFailure.tooLarge(limitBytes: limit) }

        let hash = try Self.sha256(of: url)
        if let existing = try database.book(withContentHash: hash) {
            return .alreadyInLibrary(bookId: existing.id, title: existing.title)
        }

        try paths.prepare()
        let fm = FileManager.default
        let stage = paths.staging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let original = stage.appending(path: "original.\(ext)")
        try fm.copyItem(at: url, to: original)

        let parsed = format == .epub
            ? try parseEPUB(original, in: stage, fileName: url.lastPathComponent)
            : try parseTXT(original, in: stage, fileName: url.lastPathComponent)
        guard !parsed.chapters.isEmpty else { throw ImportFailure.noChapters }

        let id = UUID()
        let keys = ChapterKeys.make(titles: parsed.chapters.map(\.title))
        let chapters = parsed.chapters.enumerated().map { index, chapter in
            Chapter(bookId: id, index: index, title: chapter.title, volume: chapter.volume,
                    keyTitle: keys[index].title, keyOccurrence: keys[index].occurrence, source: chapter.source)
        }
        let book = Book(id: id, title: parsed.title, author: parsed.author, format: format,
                        sourceIdentifier: parsed.identifier,
                        titleAuthorKey: BookIdentity.titleAuthorKey(title: parsed.title, author: parsed.author),
                        contentHash: hash, originalFileName: url.lastPathComponent, addedAt: Date(),
                        chapterCount: chapters.count, hasCover: parsed.hasCover)

        // Files first, then the row: a crash in between leaves an unlisted folder, never a
        // shelf entry without its files.
        let destination = paths.bookDirectory(id)
        try fm.moveItem(at: stage, to: destination)
        do {
            try database.insert(book: book, chapters: chapters)
        } catch {
            try? fm.removeItem(at: destination)
            if let existing = try? database.book(withContentHash: hash) {
                return .alreadyInLibrary(bookId: existing.id, title: existing.title)
            }
            throw error
        }
        return .added(bookId: id, title: book.title)
    }

    private func parseEPUB(_ file: URL, in stage: URL, fileName: String) throws -> Parsed {
        let archive = try EPUBArchive(url: file)
        if archive.hasDRM { throw ImportFailure.drmProtected }
        let package: EPUBPackage
        do {
            let opfPath = try ContainerParser.rootfilePath(from: try archive.data(at: "META-INF/container.xml"))
            package = try PackageParser.parse(try archive.data(at: opfPath), packagePath: opfPath)
        } catch EPUBError.noSpine {
            throw ImportFailure.noChapters
        }
        if package.metadata.isFixedLayout { throw ImportFailure.fixedLayout }

        let entries = EPUBChapterList.build(spine: package.spine, toc: contents(of: package, in: archive))
        let chapters = entries.map { entry in
            (title: entry.title.isEmpty ? firstHeading(entry.path, in: archive) : entry.title,
             volume: entry.volume, source: entry.path)
        }

        var hasCover = false
        if let coverPath = package.coverPath, let data = try? archive.data(at: coverPath) {
            let ext = (coverPath as NSString).pathExtension.lowercased()
            try data.write(to: stage.appending(path: "cover.\(ext.isEmpty ? "jpg" : ext)"))
            hasCover = true
        }

        let fromName = FileNameMetadata.parse(fileName)
        let title = package.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = package.metadata.creators.first ?? (title.isEmpty ? fromName.author : nil)
        return Parsed(title: title.isEmpty ? fromName.title : title, author: author,
                      identifier: BookIdentity.identifierKey(package.metadata.identifier),
                      chapters: chapters, hasCover: hasCover)
    }

    /// The nav document when it parses and lists something, else the NCX.
    private func contents(of package: EPUBPackage, in archive: EPUBArchive) -> [TOCEntry] {
        if let nav = package.navPath, let data = try? archive.data(at: nav),
           let toc = try? TOCParser.nav(data, basePath: nav), !toc.isEmpty {
            return toc
        }
        if let ncx = package.ncxPath, let data = try? archive.data(at: ncx),
           let toc = try? TOCParser.ncx(data, basePath: ncx) {
            return toc
        }
        return []
    }

    private func firstHeading(_ path: String, in archive: EPUBArchive) -> String {
        guard let data = try? archive.data(at: path),
              let blocks = try? XHTMLContentParser.blocks(from: String(decoding: data, as: UTF8.self), documentPath: path)
        else { return "" }
        for case .heading(let text, _) in blocks { return text }
        return ""
    }

    private func parseTXT(_ file: URL, in stage: URL, fileName: String) throws -> Parsed {
        let text: String
        do {
            text = try TextDecoding.decode(try Data(contentsOf: file)).text
        } catch is TextDecodingError {
            throw ImportFailure.empty
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}\u{FEFF}"))).isEmpty
        else { throw ImportFailure.empty }

        let split = ChapterSplitter.split(text, rules: rules)
        let folder = stage.appending(path: "chapters", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var chapters: [(title: String, volume: String?, source: String)] = []
        for (index, chapter) in split.enumerated() {
            let source = String(format: "chapters/%05d.txt", index + 1)
            try Data(chapter.body.utf8).write(to: stage.appending(path: source))
            chapters.append((chapter.title, chapter.volume, source))
        }
        let meta = FileNameMetadata.parse(fileName)
        return Parsed(title: meta.title, author: meta.author, identifier: nil, chapters: chapters, hasCover: false)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
