import Foundation

/// Where the library lives on disk. Everything sits under one root so demo mode and tests
/// can point a whole library at a temporary folder.
public struct LibraryPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/Shiori`: kept in device backups, hidden from the Files app.
    public static func standard() throws -> LibraryPaths {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return LibraryPaths(root: support.appending(path: "Shiori", directoryHint: .isDirectory))
    }

    public var database: URL { root.appending(path: "library.sqlite") }
    public var books: URL { root.appending(path: "Books", directoryHint: .isDirectory) }
    /// Imports are assembled here and moved into `books` only once complete.
    public var staging: URL { root.appending(path: "Staging", directoryHint: .isDirectory) }

    public func bookDirectory(_ id: UUID) -> URL {
        books.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    public func prepare() throws {
        for url in [root, books, staging] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
