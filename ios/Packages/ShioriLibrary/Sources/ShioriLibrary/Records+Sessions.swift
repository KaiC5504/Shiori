import Foundation
import GRDB

/// A stretch of active reading in one book (spec §9 "Reading time").
public struct ReadingSession: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "readingSession"
    public var id: Int64?
    public var bookId: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var seconds: Int
    public var firstChapter: Int
    public var lastChapter: Int

    public init(id: Int64? = nil, bookId: UUID, startedAt: Date, endedAt: Date, seconds: Int,
                firstChapter: Int, lastChapter: Int) {
        self.id = id
        self.bookId = bookId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
        self.firstChapter = firstChapter
        self.lastChapter = lastChapter
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
