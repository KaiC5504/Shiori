import Foundation
import Observation
import os
import ShioriLibrary

/// The watched folder (spec §8.1–8.2): a folder held as a security-scoped bookmark, or
/// Shiori's own Documents folder, scanned on launch and on Scan now.
@MainActor @Observable
final class WatchedFolderModel {
    var folderName: String?
    var lastScan: Date?
    var lastNewBooks = 0
    var autoImport = true {
        didSet { defaults.set(autoImport, forKey: Keys.autoImport) }
    }
    var formats: Set<ScanFormat> = Set(ScanFormat.allCases) {
        didSet { defaults.set(formats.map(\.rawValue).sorted(), forKey: Keys.formats) }
    }
    var isScanning = false
    var problem: LocalizedStringResource?
    var usesOwnFolder = false

    var hasFolder: Bool { usesOwnFolder || folderName != nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let scanner: FolderScanner
    // Demo mode and tests scan right after launch; the launch scan then has nothing to add.
    @ObservationIgnored private var scannedThisLaunch = false
    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "scan")
    private static let unavailable: LocalizedStringResource = "Folder unavailable. Choose it again."

    init(defaults: UserDefaults, scanner: FolderScanner) {
        self.defaults = defaults
        self.scanner = scanner
        usesOwnFolder = defaults.bool(forKey: Keys.ownFolder)
        folderName = usesOwnFolder ? Self.ownFolderName : defaults.string(forKey: Keys.name)
        lastScan = defaults.object(forKey: Keys.lastScan) as? Date
        lastNewBooks = defaults.integer(forKey: Keys.lastNewBooks)
        autoImport = defaults.object(forKey: Keys.autoImport) as? Bool ?? true
        if let stored = defaults.stringArray(forKey: Keys.formats) {
            formats = Set(stored.compactMap(ScanFormat.init))
        }
    }

    /// `folder` comes from the folder picker, security-scoped. Demo mode passes a plain
    /// folder inside the app, where starting the scope fails and isn't needed.
    func choose(_ folder: URL) {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Keys.bookmark)
        } catch {
            let nsError = error as NSError
            Self.log.error("bookmarking the folder failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            problem = Self.unavailable
            return
        }
        setFolder(name: Self.displayName(of: folder), own: false)
    }

    /// Documents, which Files shows as On My iPhone › Shiori.
    func useOwnFolder() {
        defaults.removeObject(forKey: Keys.bookmark)
        setFolder(name: Self.ownFolderName, own: true)
    }

    func disconnect() {
        defaults.removeObject(forKey: Keys.bookmark)
        setFolder(name: nil, own: false)
    }

    func scanNow(settings: ImportSettings) async {
        guard !isScanning, let folder = resolveFolder() else { return }
        isScanning = true
        let accessing = folder.startAccessingSecurityScopedResource()
        do {
            let summary = try await scanner.scan(folder: folder, formats: formats, settings: settings)
            problem = nil
            lastScan = summary.date
            lastNewBooks = summary.newBooks
            defaults.set(summary.date, forKey: Keys.lastScan)
            defaults.set(summary.newBooks, forKey: Keys.lastNewBooks)
        } catch {
            let nsError = error as NSError
            Self.log.error("scanning the folder failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            problem = Self.unavailable
        }
        if accessing { folder.stopAccessingSecurityScopedResource() }
        scannedThisLaunch = true
        isScanning = false
    }

    /// With auto-import off this still checks the bookmark, so a lost folder shows on the
    /// card before anyone taps Scan now.
    func scanOnLaunchIfNeeded(settings: ImportSettings) async {
        guard !scannedThisLaunch else { return }
        if autoImport {
            await scanNow(settings: settings)
        } else {
            _ = resolveFolder()
        }
    }

    private func setFolder(name: String?, own: Bool) {
        usesOwnFolder = own
        folderName = name
        problem = nil
        lastScan = nil
        lastNewBooks = 0
        defaults.set(own, forKey: Keys.ownFolder)
        defaults.set(own ? nil : name, forKey: Keys.name)
        defaults.removeObject(forKey: Keys.lastScan)
        defaults.removeObject(forKey: Keys.lastNewBooks)
    }

    /// Nil with no folder chosen, or with `problem` set when the folder can't be found.
    private func resolveFolder() -> URL? {
        if usesOwnFolder { return URL.documentsDirectory }
        guard let bookmark = defaults.data(forKey: Keys.bookmark) else { return nil }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            // Files keeps deleted folders in a hidden trash, and a bookmark still finds them there.
            guard !url.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) else {
                problem = Self.unavailable
                return nil
            }
            if stale { refresh(url) }
            return url
        } catch {
            let nsError = error as NSError
            Self.log.error("resolving the folder failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            problem = Self.unavailable
            return nil
        }
    }

    /// A stale bookmark still resolved: the folder was moved or renamed. Apple's advice is to
    /// bookmark it again; if it can't be reached, the scan reports it as unavailable.
    private func refresh(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        defaults.set(bookmark, forKey: Keys.bookmark)
        let name = Self.displayName(of: url)
        folderName = name
        defaults.set(name, forKey: Keys.name)
    }

    private static let ownFolderName = "Shiori"

    /// "iCloud Drive" rather than "com~apple~CloudDocs".
    private static func displayName(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }

    private enum Keys {
        static let bookmark = "watchedFolder.bookmark"
        static let name = "watchedFolder.name"
        static let ownFolder = "watchedFolder.ownFolder"
        static let lastScan = "watchedFolder.lastScan"
        static let lastNewBooks = "watchedFolder.lastNewBooks"
        static let autoImport = "watchedFolder.autoImport"
        static let formats = "watchedFolder.formats"
    }
}
