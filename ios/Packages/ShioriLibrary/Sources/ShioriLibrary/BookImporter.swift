import CryptoKit
import Foundation
import os
import ShioriCore

/// Copies a file into the library and indexes it (spec §8.3). An actor whose import runs
/// without suspending, so imports happen one at a time: a second tap, or the same file
/// twice in one batch, finds the first copy when it deduplicates.
public actor BookImporter {
    let database: LibraryDatabase
    let paths: LibraryPaths
    private let rules: [ChapterRule]
    static let log = Logger(subsystem: "com.kaichuan.shiori", category: "import")

    static let epubLimit: Int64 = 512 << 20
    static let txtLimit: Int64 = 128 << 20
    static let pdfLimit: Int64 = 512 << 20
    static let zipLimit: Int64 = 512 << 20

    public init(database: LibraryDatabase, paths: LibraryPaths, rules: [ChapterRule] = ChapterRule.presets) {
        self.database = database
        self.paths = paths
        self.rules = rules
    }

    /// Removes half-built imports left by a crash or a kill, and finishes or undoes an
    /// update or removal that was cut short; run on launch.
    /// One stuck item doesn't stop the rest; the first error is thrown once all were tried.
    public func cleanStaging() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.staging, withIntermediateDirectories: true)
        var firstError: Error?
        do {
            try recoverInterruptedChanges()
        } catch {
            firstError = error
        }
        for item in try fm.contentsOfDirectory(at: paths.staging, includingPropertiesForKeys: nil) {
            do {
                try fm.removeItem(at: item)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    /// One outcome per book found: a ZIP can hold several. They're logged as one batch.
    public func importFiles(at url: URL, origin: ImportOrigin, settings: ImportSettings) async -> [ImportOutcome] {
        let outcomes = outcomes(for: url, origin: origin, txt: TXTOptions(settings))
        appendToLog(outcomes, origin: origin)
        return outcomes
    }

    /// `importFiles` without the log entry, for a caller that logs a larger batch itself, as
    /// the folder scan does.
    func importFilesUnlogged(at url: URL, origin: ImportOrigin, settings: ImportSettings) -> [ImportOutcome] {
        outcomes(for: url, origin: origin, txt: TXTOptions(settings))
    }

    /// `importFiles` from the picker, with this importer's chapter rules.
    public func importFile(at url: URL) async -> ImportOutcome {
        let outcomes = outcomes(for: url, origin: .picker, txt: TXTOptions(encoding: .auto, rules: rules))
        appendToLog(outcomes, origin: .picker)
        return outcomes.first ?? .failed(fileName: url.lastPathComponent, reason: .unsupportedFormat)
    }

    func appendToLog(_ outcomes: [ImportOutcome], origin: ImportOrigin) {
        guard !outcomes.isEmpty else { return }
        do {
            try database.appendLog(outcomes, batchId: UUID(), origin: origin, date: Date())
        } catch {
            Self.log.error("logging \(outcomes.count) outcomes failed: \(Self.loggable(error), privacy: .public)")
        }
    }

    private func outcomes(for url: URL, origin: ImportOrigin, txt: TXTOptions) -> [ImportOutcome] {
        if url.pathExtension.lowercased() == "zip" {
            return importZIP(url, origin: origin, txt: txt)
        }
        return [importOne(url, fileName: url.lastPathComponent, origin: origin, txt: txt)]
    }

    /// `fileName` is what the user sees and what TXT metadata comes from; for a ZIP entry it
    /// differs from the extracted file's own name.
    func importOne(_ file: URL, fileName: String, origin: ImportOrigin, txt: TXTOptions) -> ImportOutcome {
        let ext = (fileName as NSString).pathExtension.lowercased()
        do {
            return try importOrThrow(file, fileName: fileName, origin: origin, txt: txt)
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
    static func loggable(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain {
            return "\(ns.domain) \(ns.code)"
        }
        return String(describing: error)
    }

    static func format(forExtension ext: String) -> BookFormat? {
        switch ext {
        case "epub": .epub
        case "txt": .txt
        case "pdf": .pdf
        default: nil
        }
    }

    static func limit(for format: BookFormat) -> Int64 {
        switch format {
        case .epub: epubLimit
        case .txt: txtLimit
        case .pdf: pdfLimit
        }
    }

    static func fileSize(_ url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    private func importOrThrow(_ file: URL, fileName: String, origin: ImportOrigin, txt: TXTOptions) throws -> ImportOutcome {
        guard let format = Self.format(forExtension: (fileName as NSString).pathExtension.lowercased()) else {
            throw ImportFailure.unsupportedFormat
        }
        let limit = Self.limit(for: format)
        guard try Self.fileSize(file) <= limit else { throw ImportFailure.tooLarge(limitBytes: limit) }

        let hash = try Self.sha256(of: file)
        if let existing = try database.book(withContentHash: hash) {
            return .alreadyInLibrary(bookId: existing.id, title: existing.title)
        }
        // Only the watched folder honours removals: picking a file by hand means "bring it back".
        let fromFolder = origin == .watchedFolder
        if fromFolder, try database.isRemoved(contentHash: hash) {
            return .skipped(fileName: fileName, reason: .removedEarlier)
        }

        try paths.prepare()
        let fm = FileManager.default
        let stage = paths.staging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let original = stage.appending(path: "original.\(format.rawValue)")
        try fm.copyItem(at: file, to: original)

        let parsed: ParsedBook
        switch format {
        case .epub: parsed = try parseEPUB(original, in: stage, fileName: fileName)
        case .txt: parsed = try parseTXT(original, into: stage, folder: "chapters", fileName: fileName, options: txt)
        case .pdf: parsed = try parsePDF(original, in: stage, fileName: fileName)
        }
        guard format == .pdf || !parsed.chapters.isEmpty else { throw ImportFailure.noChapters }

        let identityKeys = [parsed.identifier, parsed.titleAuthorKey].compactMap { $0 }
        if fromFolder, try database.isRemoved(identityKeys: identityKeys) {
            return .skipped(fileName: fileName, reason: .removedEarlier)
        }

        let outcome: ImportOutcome
        if let existing = try database.bookToUpdate(format: format, identifier: parsed.identifier,
                                                    titleAuthorKey: parsed.titleAuthorKey) {
            outcome = try update(existing, from: stage, parsed: parsed, hash: hash, fileName: fileName)
        } else {
            outcome = try add(from: stage, parsed: parsed, format: format, hash: hash, fileName: fileName)
        }
        if !fromFolder {
            do {
                try database.forgetRemoved(contentHash: hash, identityKeys: identityKeys)
            } catch {
                Self.log.error("forgetting a removal failed: \(Self.loggable(error), privacy: .public)")
            }
        }
        return outcome
    }

    private func add(from stage: URL, parsed: ParsedBook, format: BookFormat, hash: String,
                     fileName: String) throws -> ImportOutcome {
        let fm = FileManager.default
        let id = UUID()
        let chapters = parsed.chapterRecords(bookId: id)
        let book = Book(id: id, title: parsed.title, author: parsed.author, format: format,
                        sourceIdentifier: parsed.identifier, titleAuthorKey: parsed.titleAuthorKey,
                        contentHash: hash, originalFileName: fileName, addedAt: Date(),
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

/// What a parse produced, before it becomes rows.
struct ParsedBook {
    var title: String
    var author: String?
    var identifier: String?
    var chapters: [(title: String, volume: String?, source: String)]
    var hasCover: Bool

    var titleAuthorKey: String { BookIdentity.titleAuthorKey(title: title, author: author) }

    func chapterRecords(bookId: UUID) -> [Chapter] {
        let keys = ChapterKeys.make(titles: chapters.map(\.title))
        return chapters.enumerated().map { index, chapter in
            Chapter(bookId: bookId, index: index, title: chapter.title, volume: chapter.volume,
                    keyTitle: keys[index].title, keyOccurrence: keys[index].occurrence, source: chapter.source)
        }
    }
}

struct TXTOptions {
    var encoding: TXTEncodingChoice
    var rules: [ChapterRule]

    init(encoding: TXTEncodingChoice, rules: [ChapterRule]) {
        self.encoding = encoding
        self.rules = rules
    }

    init(_ settings: ImportSettings) {
        self.init(encoding: settings.encoding, rules: settings.rules)
    }
}
