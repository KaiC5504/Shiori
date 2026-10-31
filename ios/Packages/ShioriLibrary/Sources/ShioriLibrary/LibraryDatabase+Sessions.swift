import Foundation
import GRDB

extension LibraryDatabase {
    /// Returns the session with its new id.
    public func insert(_ session: ReadingSession) throws -> ReadingSession {
        try queue.write { db in
            var session = session
            try session.insert(db)
            return session
        }
    }

    public func update(_ session: ReadingSession) throws {
        try queue.write { db in
            try session.update(db)
        }
    }

    public func readingSeconds(bookId: UUID) throws -> Int {
        try queue.read { db in
            try ReadingSession
                .filter(Column("bookId") == bookId)
                .select(sum(Column("seconds")), as: Int.self)
                .fetchOne(db) ?? 0
        }
    }

    /// Oldest first.
    public func sessions(bookId: UUID) throws -> [ReadingSession] {
        try queue.read { db in
            try ReadingSession
                .filter(Column("bookId") == bookId)
                .order(Column("startedAt"), Column("id"))
                .fetchAll(db)
        }
    }
}

/// The timing rules for reading sessions (spec §9 "Reading time"), kept out of the app so the
/// tests can drive them with their own clock.
///
/// A ping is user input: a scroll step, a tap or a page turn. The first one opens a session,
/// and one more than `idleLimit` after the last activity ends that session there and opens a
/// new one. Only active time counts: time away from the reader doesn't, though coming back
/// within the limit carries on the same session. A session under `shortest` seconds is never
/// written.
public struct SessionClock {
    public static let idleLimit: TimeInterval = 120
    public static let saveInterval: TimeInterval = 60
    public static let shortest = 5

    private let database: LibraryDatabase
    private let bookId: UUID
    private let now: () -> Date
    private var session: ReadingSession?
    private var active: TimeInterval = 0
    private var lastActivity = Date.distantPast
    private var lastSave = Date.distantPast
    private var isPaused = false

    public init(database: LibraryDatabase, bookId: UUID, now: @escaping () -> Date = { Date() }) {
        self.database = database
        self.bookId = bookId
        self.now = now
    }

    public mutating func ping(chapter: Int) throws {
        let time = now()
        guard session != nil, time.timeIntervalSince(lastActivity) <= Self.idleLimit else {
            let ended = snapshot
            begin(chapter: chapter, at: time)
            if let ended { _ = try write(ended) }
            return
        }
        if !isPaused { active += max(0, time.timeIntervalSince(lastActivity)) }
        lastActivity = time
        isPaused = false
        session?.lastChapter = chapter
        // Nothing changes between pings, so checking here is as good as a 60 s timer.
        if time.timeIntervalSince(lastSave) >= Self.saveInterval { try save(at: time) }
    }

    /// The reader left the foreground. Leaving is input too, so the time up to now counts if
    /// the reader was still in use.
    public mutating func pause() throws {
        guard session != nil else { return }
        let time = now()
        if !isPaused, time.timeIntervalSince(lastActivity) <= Self.idleLimit {
            active += max(0, time.timeIntervalSince(lastActivity))
            lastActivity = time
        }
        isPaused = true
        try save(at: time)
    }

    /// The reader closed: writes the session and ends it.
    public mutating func stop() throws {
        defer { session = nil }
        try pause()
    }

    private mutating func begin(chapter: Int, at time: Date) {
        session = ReadingSession(bookId: bookId, startedAt: time, endedAt: time, seconds: 0,
                                 firstChapter: chapter, lastChapter: chapter)
        active = 0
        lastActivity = time
        lastSave = time
        isPaused = false
    }

    private var snapshot: ReadingSession? {
        guard var session else { return nil }
        session.endedAt = lastActivity
        session.seconds = Int(active)
        return session
    }

    private mutating func save(at time: Date) throws {
        guard let snapshot else { return }
        // Set before writing, so a failing database is retried a minute later, not on every ping.
        lastSave = time
        if let written = try write(snapshot) { session?.id = written.id }
    }

    /// Inserts the session the first time and updates its row after that.
    private func write(_ session: ReadingSession) throws -> ReadingSession? {
        guard session.seconds >= Self.shortest else { return nil }
        guard session.id != nil else { return try database.insert(session) }
        try database.update(session)
        return session
    }
}
