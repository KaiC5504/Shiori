import Foundation
import GRDB

// Stub from the wave 3 contracts commit; T1 implements it.
extension LibraryDatabase {
    /// Returns the session with its new id.
    public func insert(_ session: ReadingSession) throws -> ReadingSession {
        session
    }

    public func update(_ session: ReadingSession) throws {}

    public func readingSeconds(bookId: UUID) throws -> Int {
        0
    }

    public func sessions(bookId: UUID) throws -> [ReadingSession] {
        []
    }
}
