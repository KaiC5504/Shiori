import Foundation

/// Files handed over by Open in / Share (spec §8.2).
enum IncomingFiles {
    /// A plain local copy inside the import inbox, or nil when it can't be read. The inbox's
    /// copy starts the security scope and reads through a file coordinator.
    static func copy(_ url: URL) async -> URL? {
        guard url.isFileURL else { return nil }
        guard let copy = await ImportInbox.copy([url]).copies.first else { return nil }
        // AirDrop and Mail hand over a copy of their own in Documents/Inbox, which Files would
        // otherwise show inside Shiori's folder. Only once copied: it may be the only copy.
        if isSystemInboxCopy(url) {
            await Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: url)
            }.value
        }
        return copy
    }

    private static func isSystemInboxCopy(_ url: URL) -> Bool {
        let inbox = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
            .resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return parent == inbox
    }
}
