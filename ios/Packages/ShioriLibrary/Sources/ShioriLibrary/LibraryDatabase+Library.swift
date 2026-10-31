import Foundation
import GRDB
import os

extension LibraryDatabase {
    private static let libraryLog = Logger(subsystem: "com.kaichuan.shiori", category: "database")

    /// The newest `limit` batches, newest first.
    public func importLog(limit: Int) throws -> [ImportBatch] {
        try queue.read { db in try Self.importLog(db, limit: limit) }
    }

    /// Calls `onChange` on the main queue with the current log, then after every change.
    public func observeImportLog(limit: Int, _ onChange: @escaping @Sendable ([ImportBatch]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation.tracking { db in try Self.importLog(db, limit: limit) }.start(
            in: queue,
            scheduling: .immediate,
            onError: { error in Self.libraryLog.error("import log observation failed: \(error)") },
            onChange: onChange)
    }

    public func appendLog(_ outcomes: [ImportOutcome], batchId: UUID, origin: ImportOrigin, date: Date) throws {
        let encoder = JSONEncoder()
        try queue.write { db in
            for (position, outcome) in outcomes.enumerated() {
                let json = String(decoding: try encoder.encode(outcome), as: UTF8.self)
                var entry = ImportLogEntry(id: nil, batchId: batchId, date: date, origin: origin.rawValue,
                                           position: position, outcome: json)
                try entry.insert(db)
            }
        }
    }

    private static func importLog(_ db: Database, limit: Int) throws -> [ImportBatch] {
        let batchIds = try UUID.fetchAll(db, sql: """
            SELECT batchId FROM importLog GROUP BY batchId ORDER BY MAX(date) DESC, MAX(id) DESC LIMIT ?
            """, arguments: [limit])
        guard !batchIds.isEmpty else { return [] }
        let entries = try ImportLogEntry
            .filter(batchIds.contains(Column("batchId")))
            .order(Column("position"))
            .fetchAll(db)
        let decoder = JSONDecoder()
        let grouped = Dictionary(grouping: entries, by: \.batchId)
        return batchIds.compactMap { id in
            guard let rows = grouped[id], let first = rows.first else { return nil }
            // An outcome written by a newer build that this one can't decode is left out.
            let outcomes = rows.compactMap { try? decoder.decode(ImportOutcome.self, from: Data($0.outcome.utf8)) }
            return ImportBatch(id: id, date: first.date, origin: ImportOrigin(rawValue: first.origin) ?? .picker,
                               outcomes: outcomes)
        }
    }

    func book(id: UUID) throws -> Book? {
        try queue.read { db in try Book.fetchOne(db, key: id) }
    }

    /// The book a new download updates in place (spec §8.4): the same EPUB identifier, else
    /// the same title and author. Formats never cross, and a different identifier is
    /// another source's copy, so a separate book.
    func bookToUpdate(format: BookFormat, identifier: String?, titleAuthorKey: String) throws -> Book? {
        try queue.read { db in
            let sameFormat = Book.filter(Column("format") == format.rawValue).order(Column("addedAt").desc)
            guard let identifier else {
                return try sameFormat.filter(Column("titleAuthorKey") == titleAuthorKey).fetchOne(db)
            }
            if let match = try sameFormat.filter(Column("sourceIdentifier") == identifier).fetchOne(db) {
                return match
            }
            return try sameFormat
                .filter(Column("titleAuthorKey") == titleAuthorKey && Column("sourceIdentifier") == nil)
                .fetchOne(db)
        }
    }

    /// Replaces a book's row and chapters, and moves its progress onto the new chapters, in
    /// one transaction: a crash leaves the old version or the new one, never a mix.
    func replace(_ book: Book, chapters: [Chapter], remapping remap: (Progress) -> Progress) throws {
        try queue.write { db in
            try book.update(db)
            _ = try Chapter.filter(Column("bookId") == book.id).deleteAll(db)
            for chapter in chapters {
                try chapter.insert(db)
            }
            if let progress = try Progress.fetchOne(db, key: book.id) {
                try remap(progress).update(db)
            }
        }
    }

    /// Deletes the book (its chapters and progress cascade) and remembers it, so the watched
    /// folder doesn't bring it back.
    func remove(_ book: Book, at date: Date) throws {
        try queue.write { db in
            _ = try Book.deleteOne(db, key: book.id)
            try RemovedBook(contentHash: book.contentHash, identityKey: book.sourceIdentifier ?? book.titleAuthorKey,
                            title: book.title, removedAt: date).save(db)
        }
    }

    func isRemoved(contentHash: String) throws -> Bool {
        try queue.read { db in
            try RemovedBook.filter(Column("contentHash") == contentHash).fetchCount(db) > 0
        }
    }

    func isRemoved(identityKeys: [String]) throws -> Bool {
        guard !identityKeys.isEmpty else { return false }
        return try queue.read { db in
            try RemovedBook.filter(identityKeys.contains(Column("identityKey"))).fetchCount(db) > 0
        }
    }

    func forgetRemoved(contentHash: String, identityKeys: [String]) throws {
        try queue.write { db in
            _ = try RemovedBook
                .filter(Column("contentHash") == contentHash || identityKeys.contains(Column("identityKey")))
                .deleteAll(db)
        }
    }
}
