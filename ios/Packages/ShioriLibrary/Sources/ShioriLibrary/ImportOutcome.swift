import Foundation

public enum ImportFailure: Error, Equatable, Sendable {
    case unsupportedFormat
    case tooLarge(limitBytes: Int64)
    case drmProtected
    case fixedLayout
    case noChapters
    case empty
    /// The message is for logs; the UI shows a plain "couldn't read" line.
    case unreadable(String)
}

public enum ImportOutcome: Equatable, Sendable {
    case added(bookId: UUID, title: String)
    case alreadyInLibrary(bookId: UUID, title: String)
    case failed(fileName: String, reason: ImportFailure)
}
