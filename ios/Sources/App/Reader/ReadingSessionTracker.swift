import Foundation
import os
import ShioriLibrary

private let sessionLog = Logger(subsystem: "com.kaichuan.shiori", category: "reader")

/// Records reading sessions (spec §9): open while the reader is in front and in use, closed
/// after two minutes without a ping. The rules live in `SessionClock`; a failed write is only
/// logged, so the reader never sees it.
@MainActor
final class ReadingSessionTracker {
    private var clock: SessionClock

    init(database: LibraryDatabase, bookId: UUID) {
        clock = SessionClock(database: database, bookId: bookId)
    }

    /// A scroll step, a tap or a page turn.
    func ping(chapterIndex: Int) {
        record { try $0.ping(chapter: chapterIndex) }
    }

    /// The app left the foreground; writes the open session.
    func pause() {
        record { try $0.pause() }
    }

    /// The reader closed.
    func stop() {
        record { try $0.stop() }
    }

    private func record(_ step: (inout SessionClock) throws -> Void) {
        do {
            try step(&clock)
        } catch {
            sessionLog.error("saving the reading session failed: \(error)")
        }
    }
}
