import Foundation
import GRDB

extension LibraryDatabase {
    func scannedFiles() throws -> [String: ScannedFile] {
        try queue.read { db in
            Dictionary(try ScannedFile.fetchAll(db).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    func recordScanned(_ file: ScannedFile) throws {
        try queue.write { db in try file.upsert(db) }
    }

    /// Paths are relative to the watched folder, so rows a scan no longer sees go: otherwise
    /// a newly chosen folder could match an old folder's file by path, size and date.
    func forgetScannedFiles(notIn paths: Set<String>) throws {
        try queue.write { db in
            for path in try String.fetchAll(db, sql: "SELECT path FROM scannedFile") where !paths.contains(path) {
                _ = try ScannedFile.deleteOne(db, key: path)
            }
        }
    }

    func lastImportLogId() throws -> Int64 {
        try queue.read { db in try Int64.fetchOne(db, sql: "SELECT MAX(id) FROM importLog") ?? 0 }
    }

    /// The importer logs each file as its own batch; a scan gathers the rows `origin` wrote
    /// after `id` into `batchId`, numbered on from `position`, then appends `extra`.
    func gatherLog(after id: Int64, origin: ImportOrigin, into batchId: UUID, date: Date, from position: Int,
                   appending extra: [ImportOutcome]) throws -> (lastId: Int64, nextPosition: Int) {
        let encoder = JSONEncoder()
        return try queue.write { db in
            var lastId = id
            var position = position
            let rows = try ImportLogEntry
                .filter(Column("id") > id && Column("origin") == origin.rawValue)
                .order(Column("id"))
                .fetchAll(db)
            for var row in rows {
                row.batchId = batchId
                row.date = date
                row.position = position
                try row.update(db)
                position += 1
                lastId = max(lastId, row.id ?? lastId)
            }
            for outcome in extra {
                let json = String(decoding: try encoder.encode(outcome), as: UTF8.self)
                var entry = ImportLogEntry(id: nil, batchId: batchId, date: date, origin: origin.rawValue,
                                           position: position, outcome: json)
                try entry.insert(db)
                position += 1
                lastId = max(lastId, entry.id ?? lastId)
            }
            return (lastId, position)
        }
    }
}
