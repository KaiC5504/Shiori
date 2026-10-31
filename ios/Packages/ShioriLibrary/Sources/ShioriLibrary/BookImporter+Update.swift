import Foundation
import ShioriCore

/// A book's folder while it's being replaced or removed sits beside it, named `<id>.<state>`,
/// so a launch after a crash can tell which version the rows point at and finish or undo
/// the change (`BookImporter.recoverInterruptedChanges`).
extension LibraryPaths {
    /// A new version, written before the rows that point at it. `hash` is its content hash,
    /// so the rows show whether it was committed.
    func pendingVersion(of id: UUID, hash: String) -> URL {
        books.appending(path: "\(id.uuidString).next-\(hash)", directoryHint: .isDirectory)
    }

    /// The version being replaced, kept until the new one is in place.
    func retiredVersion(of id: UUID) -> URL {
        books.appending(path: "\(id.uuidString).old", directoryHint: .isDirectory)
    }

    /// A removed book's folder, kept until its rows are gone.
    func removedFolder(of id: UUID) -> URL {
        books.appending(path: "\(id.uuidString).removed", directoryHint: .isDirectory)
    }
}

extension BookImporter {
    /// Swaps in a new download of `existing` (spec §8.4): the same id, its progress moved
    /// onto the new chapters by key.
    func update(_ existing: Book, from stage: URL, parsed: ParsedBook, hash: String,
                fileName: String) throws -> ImportOutcome {
        let fm = FileManager.default
        let chapters = parsed.chapterRecords(bookId: existing.id)
        let added = chapters.count - existing.chapterCount
        var book = existing
        book.title = parsed.title
        book.author = parsed.author
        book.sourceIdentifier = parsed.identifier ?? existing.sourceIdentifier
        book.titleAuthorKey = parsed.titleAuthorKey
        book.contentHash = hash
        book.originalFileName = fileName
        book.chapterCount = chapters.count
        book.hasCover = parsed.hasCover
        book.lastUpdatedAt = Date()
        book.lastUpdateAddedChapters = added > 0 ? added : nil

        let pending = paths.pendingVersion(of: existing.id, hash: hash)
        try? fm.removeItem(at: pending)
        try fm.moveItem(at: stage, to: pending)
        do {
            try database.replace(book, chapters: chapters) { progress in
                Self.remap(progress, oldChapterCount: existing.chapterCount, onto: chapters)
            }
        } catch {
            try? fm.removeItem(at: pending)
            throw error
        }
        do {
            try install(pending, for: existing.id)
        } catch {
            // The rows already point at the new version, so the next launch finishes this.
            Self.log.error("installing an update failed: \(Self.loggable(error), privacy: .public)")
        }
        return .updated(bookId: book.id, title: book.title,
                        change: added > 0 ? .addedChapters(added) : .changed)
    }

    private func install(_ pending: URL, for id: UUID) throws {
        let fm = FileManager.default
        let current = paths.bookDirectory(id)
        let retired = paths.retiredVersion(of: id)
        try? fm.removeItem(at: retired)
        if fm.fileExists(atPath: current.path(percentEncoded: false)) {
            try fm.moveItem(at: current, to: retired)
        }
        try fm.moveItem(at: pending, to: current)
        try? fm.removeItem(at: retired)
    }

    /// The chapter with the saved key, else the saved index clamped (`ReadingPosition`), at
    /// the same offset. `updatedAt` is kept, so the shelf's order and Updated badge still
    /// reflect when the book was last read.
    static func remap(_ progress: Progress, oldChapterCount: Int, onto chapters: [Chapter]) -> Progress {
        guard !chapters.isEmpty else { return progress }
        let index = ReadingPosition.chapterIndex(for: progress, in: chapters)
        let within = min(max(progress.fraction * Double(max(oldChapterCount, 1)) - Double(progress.chapterIndex), 0), 1)
        var moved = progress
        moved.chapterIndex = index
        moved.keyTitle = chapters[index].keyTitle
        moved.keyOccurrence = chapters[index].keyOccurrence
        moved.fraction = min(max((Double(index) + within) / Double(chapters.count), 0), 1)
        return moved
    }

    /// Deletes the book's files and rows, and remembers it so the watched folder doesn't
    /// bring it back (spec §8.2). Picking the file by hand brings it back.
    public func remove(bookId: UUID) async throws {
        guard let book = try database.book(id: bookId) else { return }
        let fm = FileManager.default
        let current = paths.bookDirectory(bookId)
        let parked = paths.removedFolder(of: bookId)
        try? fm.removeItem(at: parked)
        let hasFolder = fm.fileExists(atPath: current.path(percentEncoded: false))
        if hasFolder {
            try fm.moveItem(at: current, to: parked)
        }
        do {
            try database.remove(book, at: Date())
        } catch {
            if hasFolder { try? fm.moveItem(at: parked, to: current) }
            throw error
        }
        guard hasFolder else { return }
        do {
            try fm.removeItem(at: parked)
        } catch {
            // The rows are gone, so the next launch deletes the folder.
            Self.log.error("deleting a removed book's files failed: \(Self.loggable(error), privacy: .public)")
        }
    }

    /// Splits a TXT book again with `settings`, keeping progress by chapter key. Logged as
    /// its own batch.
    public func resplit(bookId: UUID, settings: ImportSettings) async -> ImportOutcome {
        let outcome: ImportOutcome
        do {
            outcome = try resplitOrThrow(bookId, options: TXTOptions(settings))
        } catch {
            let fileName = (try? database.book(id: bookId))?.originalFileName ?? ""
            Self.log.error("re-split failed: \(Self.loggable(error), privacy: .public)")
            outcome = .failed(fileName: fileName, reason: error as? ImportFailure ?? .unreadable(Self.loggable(error)))
        }
        // Re-detecting is done from the shelf, and the picker is the closest origin the log has.
        appendToLog([outcome], origin: .picker)
        return outcome
    }

    private func resplitOrThrow(_ bookId: UUID, options: TXTOptions) throws -> ImportOutcome {
        guard let book = try database.book(id: bookId) else { throw ImportFailure.unreadable("no such book") }
        guard book.format == .txt else { throw ImportFailure.unsupportedFormat }
        let fm = FileManager.default
        let directory = paths.bookDirectory(bookId)
        // A fresh folder each time: the rows point at the old one until the new rows commit.
        let folder = "chapters-" + UUID().uuidString.prefix(8).lowercased()
        let written = directory.appending(path: folder, directoryHint: .isDirectory)
        let chapters: [Chapter]
        do {
            let parsed = try parseTXT(directory.appending(path: "original.txt"), into: directory, folder: folder,
                                      fileName: book.originalFileName, options: options)
            chapters = parsed.chapterRecords(bookId: bookId)
            var updated = book
            updated.chapterCount = chapters.count
            try database.replace(updated, chapters: chapters) { progress in
                Self.remap(progress, oldChapterCount: book.chapterCount, onto: chapters)
            }
        } catch {
            try? fm.removeItem(at: written)
            throw error
        }
        // Earlier splits' folders, including any a crash left before its rows committed.
        for item in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent.hasPrefix("chapters") && item.lastPathComponent != folder {
            try? fm.removeItem(at: item)
        }
        return .resplit(bookId: bookId, title: book.title, chapters: chapters.count)
    }

    /// Finishes or undoes an update or removal that a crash or kill cut short, from the
    /// folders beside each book (`LibraryPaths.pendingVersion` and friends): the rows decide
    /// which version is real.
    func recoverInterruptedChanges() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.books.path(percentEncoded: false)) else { return }
        let items = try fm.contentsOfDirectory(at: paths.books, includingPropertiesForKeys: nil)
        var sides: [(id: UUID, state: Substring, url: URL)] = items.compactMap { url in
            let name = url.lastPathComponent
            guard let dot = name.firstIndex(of: "."), let id = UUID(uuidString: String(name[..<dot])) else { return nil }
            return (id: id, state: name[name.index(after: dot)...], url: url)
        }
        // A pending version goes first: installing it settles its retired folder too.
        sides.sort { $0.state.hasPrefix("next-") && !$1.state.hasPrefix("next-") }

        var firstError: Error?
        for side in sides where fm.fileExists(atPath: side.url.path(percentEncoded: false)) {
            do {
                let current = paths.bookDirectory(side.id)
                let hasCurrent = fm.fileExists(atPath: current.path(percentEncoded: false))
                let row = try database.book(id: side.id)
                if side.state.hasPrefix("next-") {
                    if let row, row.contentHash == side.state.dropFirst("next-".count) {
                        try install(side.url, for: side.id)
                    } else {
                        try fm.removeItem(at: side.url)
                    }
                } else if side.state == "old" || side.state == "removed" {
                    if row != nil, !hasCurrent {
                        try fm.moveItem(at: side.url, to: current)
                    } else {
                        try fm.removeItem(at: side.url)
                    }
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }
}
