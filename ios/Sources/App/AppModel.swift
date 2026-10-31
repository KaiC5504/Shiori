import Foundation
import Observation
import os
import ShioriLibrary

@MainActor @Observable
final class AppModel {
    let paths: LibraryPaths
    let database: LibraryDatabase
    let importer: BookImporter
    let settings: AppSettings
    let readerPreferences: ReaderPreferences
    let watchedFolder: WatchedFolderModel

    var books: [BookListItem] = []
    /// Newest batch first, kept current from the import log.
    var importBatches: [ImportBatch] = []
    var importSettings: ImportSettings {
        didSet { importSettings.save(to: defaults) }
    }
    var isImporting = false
    var selectedTab: AppTab = .shelf
    /// Non-nil presents the reader full screen.
    var openBook: Book?
    /// A 0-based chapter the next reader opened jumps to, instead of the saved place.
    var openChapter: Int?
    var toast: Toast?

    @ObservationIgnored private let defaults: UserDefaults
    // GRDB's cancellables; held as AnyObject so the app needn't import GRDB.
    @ObservationIgnored private var observations: [AnyObject] = []
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "app")

    private init(paths: LibraryPaths, database: LibraryDatabase, defaults: UserDefaults) {
        self.paths = paths
        self.database = database
        self.defaults = defaults
        importer = BookImporter(database: database, paths: paths)
        settings = AppSettings(defaults: defaults)
        readerPreferences = ReaderPreferences(defaults: defaults)
        importSettings = ImportSettings.load(from: defaults)
        watchedFolder = WatchedFolderModel(defaults: defaults,
                                           scanner: FolderScanner(database: database, importer: importer))
        observations.append(database.observeBookList { [weak self] items in
            MainActor.assumeIsolated { self?.books = items }
        })
        observations.append(database.observeImportLog(limit: 50) { [weak self] batches in
            MainActor.assumeIsolated { self?.importBatches = batches }
        })
    }

    /// Opens the library at `paths` and clears half-built imports a crash left behind.
    static func live(paths: LibraryPaths, defaults: UserDefaults = .standard) throws -> AppModel {
        try paths.prepare()
        let model = AppModel(paths: paths, database: try LibraryDatabase(path: paths.database), defaults: defaults)
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

    /// `urls` must be readable local files; the Import tab copies picked files first. The
    /// importer logs each file's outcomes itself.
    func importFiles(_ urls: [URL], origin: ImportOrigin) async {
        guard !urls.isEmpty else { return }
        await cleanup?.value
        isImporting = true
        for url in urls {
            _ = await importer.importFiles(at: url, origin: origin, settings: importSettings)
        }
        isImporting = false
    }

    /// Files that never reached the importer (the copy failed) still belong in the log.
    func logFailures(_ outcomes: [ImportOutcome], origin: ImportOrigin) {
        guard !outcomes.isEmpty else { return }
        do {
            try database.appendLog(outcomes, batchId: UUID(), origin: origin, date: .now)
        } catch {
            Self.log.error("logging failed imports failed: \(error)")
        }
    }

    /// Open in / Share → Shiori.
    /// The launch scan stages files too, so it waits for the launch cleanup as imports do.
    func scanOnLaunch() async {
        await cleanup?.value
        await watchedFolder.scanOnLaunchIfNeeded(settings: importSettings)
    }

    func handleIncoming(_ url: URL) async {
        // On a cold launch from Open in, the launch cleanup would empty the inbox under the copy.
        await cleanup?.value
        guard let copy = await IncomingFiles.copy(url) else {
            logFailures([.failed(fileName: url.lastPathComponent, reason: .unreadable("open in"))], origin: .openIn)
            return
        }
        isImporting = true
        let outcomes = await importer.importFiles(at: copy, origin: .openIn, settings: importSettings)
        isImporting = false
        await ImportInbox.discard([copy.deletingLastPathComponent()])
        toast = outcomes.lazy.compactMap(Self.toast(for:)).first
    }

    func removeBook(_ id: UUID) async {
        if openBook?.id == id { openBook = nil }
        do {
            try await importer.remove(bookId: id)
        } catch {
            Self.log.error("removing a book failed: \(error)")
        }
    }

    func resplit(_ id: UUID) async {
        let outcome = await importer.resplit(bookId: id, settings: importSettings)
        toast = Self.toast(for: outcome)
    }

    private static func toast(for outcome: ImportOutcome) -> Toast? {
        switch outcome {
        case .added(let bookId, let title), .alreadyInLibrary(let bookId, let title):
            Toast(id: UUID(), message: "Imported “\(title)”", bookId: bookId)
        case .updated(let bookId, let title, _):
            Toast(id: UUID(), message: "Updated “\(title)”", bookId: bookId)
        case .resplit(let bookId, _, let chapters):
            Toast(id: UUID(), message: "Re-detected: \(chapters) chapters", bookId: bookId)
        case .skipped, .failed:
            nil
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id: UUID
    var message: LocalizedStringResource
    var bookId: UUID?
}
