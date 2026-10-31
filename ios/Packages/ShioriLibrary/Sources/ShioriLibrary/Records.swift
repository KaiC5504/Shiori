import Foundation
import GRDB
import ShioriCore

public enum BookFormat: String, Codable, Sendable {
    case epub, txt, pdf
}

public struct Book: Codable, Identifiable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var title: String
    public var author: String?
    public var format: BookFormat
    /// The EPUB `dc:identifier`, trimmed; nil for TXT.
    public var sourceIdentifier: String?
    public var titleAuthorKey: String
    /// SHA-256 of the imported file, hex.
    public var contentHash: String
    public var originalFileName: String
    public var addedAt: Date
    public var chapterCount: Int
    public var hasCover: Bool

    public init(id: UUID, title: String, author: String?, format: BookFormat, sourceIdentifier: String?,
                titleAuthorKey: String, contentHash: String, originalFileName: String, addedAt: Date,
                chapterCount: Int, hasCover: Bool) {
        self.id = id
        self.title = title
        self.author = author
        self.format = format
        self.sourceIdentifier = sourceIdentifier
        self.titleAuthorKey = titleAuthorKey
        self.contentHash = contentHash
        self.originalFileName = originalFileName
        self.addedAt = addedAt
        self.chapterCount = chapterCount
        self.hasCover = hasCover
    }
}

public struct Chapter: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public var bookId: UUID
    public var index: Int
    public var title: String
    public var volume: String?
    public var keyTitle: String
    public var keyOccurrence: Int
    /// The archive path for EPUB, or `chapters/00001.txt` (relative to the book folder) for TXT.
    public var source: String

    public init(bookId: UUID, index: Int, title: String, volume: String?, keyTitle: String,
                keyOccurrence: Int, source: String) {
        self.bookId = bookId
        self.index = index
        self.title = title
        self.volume = volume
        self.keyTitle = keyTitle
        self.keyOccurrence = keyOccurrence
        self.source = source
    }

    public var key: ChapterKey { ChapterKey(title: keyTitle, occurrence: keyOccurrence) }
}

/// The reading position: (chapter key, UTF-16 offset in the chapter's plain text), which
/// survives typography changes and re-imports (spec §7.3). `chapterIndex` is a fast path.
public struct Progress: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public var bookId: UUID
    public var chapterIndex: Int
    public var keyTitle: String
    public var keyOccurrence: Int
    public var offset: Int
    /// 0...1 through the whole book, for the shelf.
    public var fraction: Double
    public var updatedAt: Date

    public init(bookId: UUID, chapterIndex: Int, keyTitle: String, keyOccurrence: Int, offset: Int,
                fraction: Double, updatedAt: Date) {
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.keyTitle = keyTitle
        self.keyOccurrence = keyOccurrence
        self.offset = offset
        self.fraction = fraction
        self.updatedAt = updatedAt
    }
}

public struct BookListItem: Equatable, Sendable, Identifiable {
    public var book: Book
    public var progress: Progress?
    public var id: UUID { book.id }

    public init(book: Book, progress: Progress?) {
        self.book = book
        self.progress = progress
    }
}
