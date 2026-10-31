import Foundation
import Observation
import os
import ShioriLibrary

@MainActor @Observable
final class AppModel {
    let paths: LibraryPaths
    let database: LibraryDatabase
    let importer: BookImporter

    var books: [BookListItem] = []
    /// Newest batch first.
    var recentImports: [ImportOutcome] = []
    var isImporting = false
    var selectedTab: AppTab = .shelf
    /// Non-nil presents the reader full screen.
    var openBook: Book?

    // GRDB's cancellable; held as AnyObject so the app needn't import GRDB.
    @ObservationIgnored private var observation: AnyObject?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "app")

    private init(paths: LibraryPaths, database: LibraryDatabase) {
        self.paths = paths
        self.database = database
        importer = BookImporter(database: database, paths: paths)
        observation = database.observeBookList { [weak self] items in
            MainActor.assumeIsolated { self?.books = items }
        }
    }

    /// Opens the library at `paths` and clears half-built imports a crash left behind.
    static func live(paths: LibraryPaths) throws -> AppModel {
        try paths.prepare()
        let model = AppModel(paths: paths, database: try LibraryDatabase(path: paths.database))
        let importer = model.importer
        model.cleanup = Task {
            await ImportInbox.clear()
            do {
                try await importer.cleanStaging()
            } catch {
                log.error("cleaning staging failed: \(error)")
            }
        }
        return model
    }

    /// `urls` must be readable local files; the Import tab copies picked files first.
    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await cleanup?.value
        isImporting = true
        var batch: [ImportOutcome] = []
        for url in urls {
            batch.append(await importer.importFile(at: url))
        }
        recentImports = batch + recentImports
        isImporting = false
    }
}
