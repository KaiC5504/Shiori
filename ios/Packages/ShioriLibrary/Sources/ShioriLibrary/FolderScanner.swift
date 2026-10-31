import CryptoKit
import Foundation
import os

public enum ScanFormat: String, Codable, CaseIterable, Sendable {
    case epub, txt, pdf, zip
}

public struct ScanSummary: Sendable {
    public var outcomes: [ImportOutcome]
    public var newBooks: Int
    public var date: Date

    public init(outcomes: [ImportOutcome], newBooks: Int, date: Date) {
        self.outcomes = outcomes
        self.newBooks = newBooks
        self.date = date
    }
}

/// Imports what's new in the watched folder (spec §8.1–8.3). One scan is one batch in the
/// import log. The caller holds the folder's security scope for the whole scan.
public actor FolderScanner {
    public static let fileLimit = 2000

    private let database: LibraryDatabase
    private let importer: BookImporter
    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "scan")

    private static var stagingRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "FolderScan", directoryHint: .isDirectory)
    }

    public init(database: LibraryDatabase, importer: BookImporter) {
        self.database = database
        self.importer = importer
    }

    /// Throws only when the folder itself can't be read. Each file's result is in the summary
    /// and in the log.
    public func scan(folder: URL, formats: Set<ScanFormat>, settings: ImportSettings) async throws -> ScanSummary {
        let date = Date()
        let found = try await Self.offPool { try Self.listFiles(in: folder) }
        let known = (try? database.scannedFiles()) ?? [:]
        do {
            try database.forgetScannedFiles(notIn: Set(found.map(\.path)))
        } catch {
            Self.log.error("pruning scanned files failed: \(error)")
        }

        var work = found
            .filter { formats.contains($0.format) && Self.needsWork($0, known: known[$0.path]) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let truncated = work.count > Self.fileLimit
        if truncated { work = Array(work.prefix(Self.fileLimit)) }

        try? FileManager.default.removeItem(at: Self.stagingRoot)
        // Without a starting row, gather nothing rather than sweep earlier scans into this one.
        var batch = LogBatch(lastId: (try? database.lastImportLogId()) ?? .max, date: date)
        var outcomes: [ImportOutcome] = []
        for file in work {
            if Task.isCancelled { break }
            if file.placeholder != nil {
                Self.startDownload(file)
                let waiting = ImportOutcome.skipped(fileName: file.name, reason: .waitingForDownload)
                outcomes.append(waiting)
                gather(&batch, appending: [waiting])
                continue
            }
            let (fileOutcomes, logged) = await importFile(file, settings: settings, date: date)
            outcomes += fileOutcomes
            gather(&batch, appending: logged ? [] : fileOutcomes)
        }
        if truncated {
            let name = (try? folder.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? folder.lastPathComponent
            let tooMany = ImportOutcome.skipped(fileName: name, reason: .tooManyFiles(limit: Self.fileLimit))
            outcomes.append(tooMany)
            gather(&batch, appending: [tooMany])
        }
        try? FileManager.default.removeItem(at: Self.stagingRoot)

        let added = outcomes.filter { if case .added = $0 { true } else { false } }.count
        return ScanSummary(outcomes: outcomes, newBooks: added, date: date)
    }

    private struct LogBatch {
        let id = UUID()
        var lastId: Int64
        let date: Date
        var position = 0
    }

    private func gather(_ batch: inout LogBatch, appending extra: [ImportOutcome]) {
        do {
            (batch.lastId, batch.position) = try database.gatherLog(
                after: batch.lastId, origin: .watchedFolder, into: batch.id, date: batch.date,
                from: batch.position, appending: extra)
        } catch {
            Self.log.error("gathering the scan's log failed: \(error)")
        }
    }

    /// `logged` is false when the file never reached the importer, which logs everything it sees.
    private func importFile(_ file: FoundFile, settings: ImportSettings, date: Date) async -> ([ImportOutcome], logged: Bool) {
        let staged: Staged
        do {
            staged = try await Self.offPool { try Self.stage(file, in: Self.stagingRoot) }
        } catch {
            let nsError = error as NSError
            Self.log.error("copying a .\(file.format.rawValue, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            return ([.failed(fileName: file.name, reason: .unreadable(error.localizedDescription))], false)
        }
        let outcomes = await importer.importFiles(at: staged.file, origin: .watchedFolder, settings: settings)
        try? FileManager.default.removeItem(at: staged.folder)

        // Recorded even when the import failed: the importer read a local copy, so it would
        // fail the same way next time, and the log would repeat it on every launch. A copy
        // that failed (a provider offline, say) isn't recorded, so it's tried again.
        do {
            try database.recordScanned(ScannedFile(path: file.path, size: file.size, modifiedAt: file.modifiedAt,
                                                   contentHash: staged.hash, scannedAt: date))
        } catch {
            Self.log.error("recording a scanned file failed: \(error)")
        }
        return (outcomes, true)
    }

    private static func needsWork(_ file: FoundFile, known: ScannedFile?) -> Bool {
        guard let known else { return true }
        switch file.placeholder {
        // A stub's size and date are its own, and a stub for a file already scanned is an
        // evicted copy: downloading it again would gain nothing.
        case .stub: return false
        case .dataless, nil:
            // GRDB stores dates to the millisecond.
            return known.size != file.size || abs(known.modifiedAt.timeIntervalSince(file.modifiedAt)) > 0.001
        }
    }

    private static func startDownload(_ file: FoundFile) {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: file.url)
        } catch {
            let nsError = error as NSError
            log.error("starting an iCloud download failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
        }
    }

    private enum Placeholder: Sendable {
        /// `.Name.epub.icloud`, standing in for `Name.epub`.
        case stub
        /// Listed under its real name, with its real size and date, but not on this device.
        case dataless
    }

    private struct FoundFile: Sendable {
        /// The file to read, or for a placeholder, the item to download.
        var url: URL
        /// Relative to the folder, under the file's real name.
        var path: String
        var name: String
        var format: ScanFormat
        var size: Int64
        var modifiedAt: Date
        var placeholder: Placeholder?
    }

    private struct Staged: Sendable {
        var folder: URL
        var file: URL
        var hash: String
    }

    /// Every file of a supported format, whatever `formats` says, so switching a format off
    /// doesn't forget what was scanned.
    private static func listFiles(in folder: URL) throws -> [FoundFile] {
        let root = try folder.resourceValues(forKeys: [.isDirectoryKey])
        guard root.isDirectory == true else { throw CocoaError(.fileReadNoSuchFile) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                                      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var rootError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                if url.resolvingSymlinksInPath().standardizedFileURL.pathComponents.count <= base.count {
                    rootError = error
                    return false
                }
                return true
            })
        else { throw CocoaError(.fileReadUnknown) }

        var found: [FoundFile] = []
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                // Open in drops its copies in Documents/Inbox, which the importer has seen.
                if name == "Inbox" || name.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }

            var realName = name
            var placeholder: Placeholder?
            if name.hasPrefix(".") {
                guard name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { continue }
                realName = String(name.dropFirst().dropLast(".icloud".count))
                placeholder = .stub
            } else if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
                placeholder = .dataless
            }
            guard let format = ScanFormat(rawValue: (realName as NSString).pathExtension.lowercased()) else { continue }

            let realURL = url.deletingLastPathComponent().appending(path: realName, directoryHint: .notDirectory)
            found.append(FoundFile(url: placeholder == .stub ? realURL : url,
                                   path: relativePath(of: realURL, base: base),
                                   name: realName, format: format,
                                   size: Int64(values.fileSize ?? 0),
                                   modifiedAt: values.contentModificationDate ?? .distantPast,
                                   placeholder: placeholder))
        }
        if let rootError { throw rootError }
        return found
    }

    /// The enumerator may report `/private/var/…` for a folder chosen as `/var/…`, so both
    /// sides are resolved before comparing.
    private static func relativePath(of url: URL, base: [String]) -> String {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let components = parent + [url.lastPathComponent]
        guard components.count > base.count, Array(components.prefix(base.count)) == base else {
            return url.lastPathComponent
        }
        return components.dropFirst(base.count).joined(separator: "/")
    }

    /// A coordinated copy, so a file another app is writing (or iCloud is updating) is read
    /// whole. Each file gets its own folder under its own name, which the importer reads the
    /// title and author from.
    private static func stage(_ file: FoundFile, in root: URL) throws -> Staged {
        let fm = FileManager.default
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: file.name, directoryHint: .notDirectory)
        do {
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: file.url, options: [.withoutChanges],
                                           error: &coordinationError) { readable in
                do {
                    try fm.copyItem(at: readable, to: destination)
                } catch {
                    copyError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
            return Staged(folder: folder, file: destination, hash: try sha256(of: destination))
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // Enumerating, copying and hashing block on disk and on file providers, so they run on a
    // dispatch queue rather than holding one of the actor pool's few threads.
    private static func offPool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
