import Foundation
import Testing
@testable import ShioriLibrary

@Test func migrationCreatesTablesAndRoundTrips() throws {
    let db = try LibraryDatabase.inMemory()
    let id = UUID()
    let book = Book(id: id, title: "桃花源记", author: "陶渊明", format: .epub, sourceIdentifier: "demo-1",
                    titleAuthorKey: "桃花源记|陶渊明", contentHash: "abc", originalFileName: "桃花源记.epub",
                    addedAt: Date(timeIntervalSince1970: 0), chapterCount: 2, hasCover: false)
    let chapters = [
        Chapter(bookId: id, index: 0, title: "第一章", volume: nil, keyTitle: "第一章", keyOccurrence: 0, source: "E/c1.xhtml"),
        Chapter(bookId: id, index: 1, title: "第二章", volume: nil, keyTitle: "第二章", keyOccurrence: 0, source: "E/c2.xhtml"),
    ]
    try db.insert(book: book, chapters: chapters)
    #expect(try db.book(withContentHash: "abc") == book)
    #expect(try db.chapters(bookId: id) == chapters)
}
@Test func bookListOrdersRecentlyReadFirstThenNewest() throws {
    let db = try LibraryDatabase.inMemory()
    let a = Book.fixture(title: "A", addedAt: 1), b = Book.fixture(title: "B", addedAt: 2), c = Book.fixture(title: "C", addedAt: 3)
    for book in [a, b, c] { try db.insert(book: book, chapters: []) }
    try db.save(Progress(bookId: a.id, chapterIndex: 0, keyTitle: "", keyOccurrence: 0, offset: 0, fraction: 0.1, updatedAt: Date(timeIntervalSince1970: 10)))
    #expect(try db.bookList().map(\.book.title) == ["A", "C", "B"])
}
@Test func saveProgressReplaces() throws {
    let db = try LibraryDatabase.inMemory()
    let book = Book.fixture(title: "A", addedAt: 1)
    try db.insert(book: book, chapters: [])
    var p = Progress(bookId: book.id, chapterIndex: 3, keyTitle: "第四章", keyOccurrence: 0, offset: 120, fraction: 0.4, updatedAt: .now)
    try db.save(p); p.offset = 200; try db.save(p)
    #expect(try db.progress(bookId: book.id)?.offset == 200)
}
@Test func duplicateContentHashIsRejected() throws {
    let db = try LibraryDatabase.inMemory()
    var a = Book.fixture(title: "A", addedAt: 1)
    a.contentHash = "same"
    var b = Book.fixture(title: "B", addedAt: 2)
    b.contentHash = "same"
    try db.insert(book: a, chapters: [])
    #expect(throws: (any Error).self) { try db.insert(book: b, chapters: []) }
    #expect(try db.bookList().count == 1)
}
