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
}
