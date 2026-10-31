import Foundation
import Testing
@testable import ShioriLibrary

/// Whole seconds, so dates come back from the database's millisecond storage unchanged.
private final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

private func sessionLibrary() throws -> (db: LibraryDatabase, book: Book) {
    let db = try LibraryDatabase.inMemory()
    let book = Book.fixture(title: "A", addedAt: 1)
    try db.insert(book: book, chapters: [])
    return (db, book)
}

@Test func pingsWithinTwoMinutesExtendOneSession() throws {
    let (db, book) = try sessionLibrary()
    let time = FakeClock()
    let start = time.now
    var clock = SessionClock(database: db, bookId: book.id, now: { time.now })
    try clock.ping(chapter: 0)
    time.advance(30); try clock.ping(chapter: 1)
    time.advance(120); try clock.ping(chapter: 2)
    time.advance(20); try clock.ping(chapter: 2)
    try clock.stop()

    let sessions = try db.sessions(bookId: book.id)
    #expect(sessions.count == 1)
    let session = try #require(sessions.first)
    #expect(session.startedAt == start)
    #expect(session.endedAt == start + 170)
    #expect(session.seconds == 170)
    #expect(session.firstChapter == 0)
    #expect(session.lastChapter == 2)
}

@Test func gapOverTwoMinutesStartsANewSession() throws {
    let (db, book) = try sessionLibrary()
    let time = FakeClock()
    let start = time.now
    var clock = SessionClock(database: db, bookId: book.id, now: { time.now })
    try clock.ping(chapter: 0)
    time.advance(40); try clock.ping(chapter: 1)
    time.advance(121); try clock.ping(chapter: 3)
    time.advance(30); try clock.ping(chapter: 3)
    try clock.stop()

    let sessions = try db.sessions(bookId: book.id)
    #expect(sessions.count == 2)
    let first = try #require(sessions.first), second = try #require(sessions.last)
    #expect(first.startedAt == start)
    #expect(first.endedAt == start + 40)
    #expect(first.seconds == 40)
    #expect(first.firstChapter == 0 && first.lastChapter == 1)
    #expect(second.startedAt == start + 161)
    #expect(second.endedAt == start + 191)
    #expect(second.seconds == 30)
    #expect(second.firstChapter == 3 && second.lastChapter == 3)
}

@Test func shortSessionsAreDropped() throws {
    let (db, book) = try sessionLibrary()
    let time = FakeClock()
    var clock = SessionClock(database: db, bookId: book.id, now: { time.now })
    try clock.ping(chapter: 0)
    time.advance(2); try clock.pause()
    #expect(try db.sessions(bookId: book.id).isEmpty)
    // Back after 30 s away, which doesn't count: 4 s in all, closed by the next ping.
    time.advance(30); try clock.ping(chapter: 0)
    time.advance(2); try clock.ping(chapter: 0)
    time.advance(200); try clock.ping(chapter: 1)
    time.advance(4); try clock.stop()
    #expect(try db.sessions(bookId: book.id).isEmpty)

    try clock.ping(chapter: 2)
    time.advance(5); try clock.stop()
    #expect(try db.sessions(bookId: book.id).map(\.seconds) == [5])
    #expect(try db.readingSeconds(bookId: book.id) == 5)
}

@Test func flushWritesRunningSession() throws {
    let (db, book) = try sessionLibrary()
    let time = FakeClock()
    let start = time.now
    var clock = SessionClock(database: db, bookId: book.id, now: { time.now })
    try clock.ping(chapter: 0)
    time.advance(20); try clock.ping(chapter: 0)
    time.advance(20); try clock.ping(chapter: 1)
    #expect(try db.sessions(bookId: book.id).isEmpty)
    time.advance(20); try clock.ping(chapter: 1)
    let periodic = try db.sessions(bookId: book.id)
    #expect(periodic.count == 1)
    let first = try #require(periodic.first)
    #expect(first.id != nil)
    #expect(first.seconds == 60)

    time.advance(10); try clock.pause()
    let paused = try db.sessions(bookId: book.id)
    #expect(paused.map(\.id) == [first.id])
    #expect(paused.first?.seconds == 70)
    #expect(paused.first?.endedAt == start + 70)

    // Away from the reader for 90 s, which doesn't count, then back.
    time.advance(90); try clock.ping(chapter: 2)
    time.advance(15); try clock.ping(chapter: 2)
    try clock.stop()
    let stopped = try db.sessions(bookId: book.id)
    #expect(stopped.map(\.id) == [first.id])
    let last = try #require(stopped.first)
    #expect(last.startedAt == start)
    #expect(last.endedAt == start + 175)
    #expect(last.seconds == 85)
    #expect(last.lastChapter == 2)
}

@Test func readingSecondsSumsBook() throws {
    let db = try LibraryDatabase.inMemory()
    let a = Book.fixture(title: "A", addedAt: 1), b = Book.fixture(title: "B", addedAt: 2), c = Book.fixture(title: "C", addedAt: 3)
    for book in [a, b, c] { try db.insert(book: book, chapters: []) }
    let t = Date(timeIntervalSince1970: 1_000_000)
    var first = try db.insert(ReadingSession(bookId: a.id, startedAt: t, endedAt: t + 100, seconds: 100,
                                             firstChapter: 0, lastChapter: 3))
    #expect(first.id != nil)
    _ = try db.insert(ReadingSession(bookId: a.id, startedAt: t + 1000, endedAt: t + 1050, seconds: 50,
                                     firstChapter: 3, lastChapter: 4))
    _ = try db.insert(ReadingSession(bookId: b.id, startedAt: t, endedAt: t + 30, seconds: 30,
                                     firstChapter: 0, lastChapter: 0))
    first.seconds = 120
    try db.update(first)

    #expect(try db.readingSeconds(bookId: a.id) == 170)
    #expect(try db.readingSeconds(bookId: b.id) == 30)
    #expect(try db.readingSeconds(bookId: c.id) == 0)
    #expect(try db.sessions(bookId: a.id).map(\.seconds) == [120, 50])
}
