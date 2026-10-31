import Foundation
import GRDB

extension BookListItem {
    /// An update the reader hasn't opened since.
    public var showsUpdatedBadge: Bool {
        guard let updated = book.lastUpdatedAt else { return false }
        return updated > (progress?.updatedAt ?? .distantPast)
    }
}

/// One file's outcome within an import batch; `outcome` is `ImportOutcome` as JSON.
struct ImportLogEntry: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "importLog"
    var id: Int64?
    var batchId: UUID
    var date: Date
    var origin: String
    var position: Int
    var outcome: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A book the user removed, so the watched folder doesn't bring it back.
public struct RemovedBook: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "removedBook"
    public var contentHash: String
    /// The book's `sourceIdentifier`, else its `titleAuthorKey`, so a re-downloaded copy also stays out.
    public var identityKey: String
    public var title: String
    public var removedAt: Date

    public init(contentHash: String, identityKey: String, title: String, removedAt: Date) {
        self.contentHash = contentHash
        self.identityKey = identityKey
        self.title = title
        self.removedAt = removedAt
    }
}

/// What the watched-folder scan last saw of a file, so unchanged files aren't hashed again.
public struct ScannedFile: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "scannedFile"
    /// Relative to the watched folder.
    public var path: String
    public var size: Int64
    public var modifiedAt: Date
    public var contentHash: String?
    public var scannedAt: Date

    public init(path: String, size: Int64, modifiedAt: Date, contentHash: String?, scannedAt: Date) {
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
        self.contentHash = contentHash
        self.scannedAt = scannedAt
    }
}
