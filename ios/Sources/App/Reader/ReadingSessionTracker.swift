import Foundation
import ShioriLibrary

// Stub from the wave 3 contracts commit; T1 implements it.
/// Records reading sessions (spec §9): open while the reader is in front and in use, closed
/// after two minutes without a ping.
@MainActor
final class ReadingSessionTracker {
    init(database: LibraryDatabase, bookId: UUID) {}

    /// A scroll step, a tap or a page turn.
    func ping(chapterIndex: Int) {}

    /// The app left the foreground; writes the open session.
    func pause() {}

    /// The reader closed.
    func stop() {}
}
