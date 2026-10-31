import Foundation
import GRDB
import os

public final class LibraryDatabase: Sendable {
    private let queue: DatabaseQueue
    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "database")

    public init(path: URL) throws {
        queue = try DatabaseQueue(path: path.path(percentEncoded: false))
        try Self.migrator.migrate(queue)
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Self.migrator.migrate(queue)
    }

    public static func inMemory() throws -> LibraryDatabase {
        try LibraryDatabase(queue: DatabaseQueue())
    }

    /// Versioned from the first build so a TestFlight update never loses the library (spec §10).
    /// Never edit a shipped migration; add a new one.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "book") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("format", .text).notNull()
                t.column("sourceIdentifier", .text)
                t.column("titleAuthorKey", .text).notNull()
                t.column("contentHash", .text).notNull().unique()
                t.column("originalFileName", .text).notNull()
                t.column("addedAt", .datetime).notNull()
                t.column("chapterCount", .integer).notNull()
                t.column("hasCover", .boolean).notNull()
            }
            try db.create(table: "chapter") { t in
                t.column("bookId", .blob).notNull().references("book", onDelete: .cascade)
                t.column("index", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("volume", .text)
                t.column("keyTitle", .text).notNull()
                t.column("keyOccurrence", .integer).notNull()
                t.column("source", .text).notNull()
                t.primaryKey(["bookId", "index"])
            }
            try db.create(table: "progress") { t in
                t.primaryKey("bookId", .blob).references("book", onDelete: .cascade)
                t.column("chapterIndex", .integer).notNull()
                t.column("keyTitle", .text).notNull()
                t.column("keyOccurrence", .integer).notNull()
                t.column("offset", .integer).notNull()
                t.column("fraction", .double).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        return migrator
    }

    public func insert(book: Book, chapters: [Chapter]) throws {
        try queue.write { db in
            try book.insert(db)
            for chapter in chapters {
                try chapter.insert(db)
            }
        }
    }

    public func book(withContentHash hash: String) throws -> Book? {
        try queue.read { db in
            try Book.filter(Column("contentHash") == hash).fetchOne(db)
        }
    }

    public func bookList() throws -> [BookListItem] {
        try queue.read(Self.bookList)
    }

    public func chapters(bookId: UUID) throws -> [Chapter] {
        try queue.read { db in
            try Chapter.filter(Column("bookId") == bookId).order(Column("index")).fetchAll(db)
        }
    }

    public func progress(bookId: UUID) throws -> Progress? {
        try queue.read { db in
            try Progress.fetchOne(db, key: bookId)
        }
    }

    public func save(_ progress: Progress) throws {
        try queue.write { db in
            try progress.save(db)
        }
    }

    /// Calls `onChange` on the main queue with the current list, then after every change.
    /// Call it on the main thread: the first list arrives before it returns, so the shelf never flashes empty.
    public func observeBookList(_ onChange: @escaping @Sendable ([BookListItem]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation.tracking { db in try Self.bookList(db) }.start(
            in: queue,
            scheduling: .immediate,
            onError: { error in Self.log.error("book list observation failed: \(error)") },
            onChange: onChange)
    }

    /// Recently read books first, then the rest newest first.
    private static func bookList(_ db: Database) throws -> [BookListItem] {
        let progress = Dictionary(try Progress.fetchAll(db).map { ($0.bookId, $0) }, uniquingKeysWith: { a, _ in a })
        return try Book.fetchAll(db)
            .map { BookListItem(book: $0, progress: progress[$0.id]) }
            .sorted { a, b in
                switch (a.progress, b.progress) {
                case let (pa?, pb?): pa.updatedAt > pb.updatedAt
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): a.book.addedAt > b.book.addedAt
                }
            }
    }
}
