import Foundation

public enum ImportFailure: Error, Codable, Equatable, Sendable {
    case unsupportedFormat
    case tooLarge(limitBytes: Int64)
    case drmProtected
    case fixedLayout
    case noChapters
    case empty
    /// The message is for logs; the UI shows a plain "couldn't read" line.
    case unreadable(String)
}

public enum ImportOrigin: String, Codable, Sendable {
    case picker, watchedFolder, openIn
}

public enum UpdateChange: Codable, Equatable, Sendable {
    case addedChapters(Int)
    case changed
}

public enum SkipReason: Codable, Equatable, Sendable {
    case removedEarlier
    case nestedArchive
    case waitingForDownload
    case tooManyFiles(limit: Int)
}

/// Stored as JSON in the import log, so cases may be added but never renamed.
public enum ImportOutcome: Codable, Equatable, Sendable {
    case added(bookId: UUID, title: String)
    case alreadyInLibrary(bookId: UUID, title: String)
    case updated(bookId: UUID, title: String, change: UpdateChange)
    case resplit(bookId: UUID, title: String, chapters: Int)
    case skipped(fileName: String, reason: SkipReason)
    case failed(fileName: String, reason: ImportFailure)
}

public struct ImportBatch: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var origin: ImportOrigin
    public var outcomes: [ImportOutcome]

    public init(id: UUID, date: Date, origin: ImportOrigin, outcomes: [ImportOutcome]) {
        self.id = id
        self.date = date
        self.origin = origin
        self.outcomes = outcomes
    }
}
