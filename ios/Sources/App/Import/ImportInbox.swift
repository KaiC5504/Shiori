import Foundation
import ShioriLibrary

/// Copies picked files into the temporary folder, each in its own UUID folder under its
/// original name (the importer reads the title and author from it), so the importer only
/// ever sees plain local files.
enum ImportInbox {
    struct Batch: Sendable {
        var copies: [URL] = []
        var failures: [ImportOutcome] = []
        var folders: [URL] = []
    }

    private static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "ImportInbox", directoryHint: .isDirectory)
    }

    // The coordinated read blocks until iCloud has downloaded the file, which can take a
    // while, so it runs on a dispatch queue rather than holding a cooperative-pool thread.
    static func copy(_ urls: [URL]) async -> Batch {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: copyNow(urls))
            }
        }
    }

    static func discard(_ folders: [URL]) async {
        await Task.detached(priority: .utility) {
            for folder in folders {
                try? FileManager.default.removeItem(at: folder)
            }
        }.value
    }

    private static func copyNow(_ urls: [URL]) -> Batch {
        var batch = Batch()
        for url in urls {
            let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            do {
                batch.copies.append(try copyFile(at: url, into: folder))
                batch.folders.append(folder)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                batch.failures.append(.failed(fileName: url.lastPathComponent,
                                              reason: .unreadable(error.localizedDescription)))
            }
        }
        return batch
    }

    private static func copyFile(at url: URL, into folder: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent, directoryHint: .notDirectory)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges],
                                       error: &coordinationError) { readable in
            do {
                try FileManager.default.copyItem(at: readable, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }
}
