import Foundation

/// Files handed over by Open in / Share. Stub from wave 1's contracts commit; B2 owns it.
enum IncomingFiles {
    /// A plain local copy inside the import inbox, or nil when it can't be read.
    static func copy(_ url: URL) async -> URL? {
        await ImportInbox.copy([url]).copies.first
    }
}
