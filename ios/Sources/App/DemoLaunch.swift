#if DEBUG
import Foundation
import ShioriLibrary

/// Launch arguments that let the compile check screenshot every screen with fake data.
/// Launch arguments land in UserDefaults' argument domain, so `-DemoTab shelf` reads as a string.
enum DemoLaunch {
    private static var arguments: UserDefaults { .standard }

    static var usesDemoData: Bool { arguments.bool(forKey: "DemoData") }
    static var showContents: Bool { arguments.bool(forKey: "DemoContents") }
    static var showsImportResults: Bool { arguments.bool(forKey: "DemoImportResults") }
    /// Imports only the generated 3,000-chapter book, for the reader's UI tests.
    static var usesLongBook: Bool { arguments.bool(forKey: "DemoLongBook") }
    /// Keeps the previous launch's demo library, so a UI test can kill and reopen the app.
    static var keepsLibrary: Bool { arguments.bool(forKey: "DemoKeep") }
    /// The icon gallery replaces the tabs.
    static var showsIcons: Bool { arguments.bool(forKey: "DemoIcons") }
    /// "accent" or "txt": the Settings sub-page to push once open.
    static var settingsPage: String? { arguments.string(forKey: "DemoSettingsPage") }
    static var usesWatchedFolder: Bool { arguments.bool(forKey: "DemoWatchedFolder") }
    /// Marks the first demo book as updated, so the shelf shows its badge.
    static var marksUpdated: Bool { arguments.bool(forKey: "DemoUpdated") }
    /// A file on the simulator's host Mac, imported into whichever library is open, so a real
    /// book can be read in the simulator without the Files picker.
    static var importPath: String? { arguments.string(forKey: "DemoImportFile") }
    /// The reader opens with its chrome showing.
    static var showsChrome: Bool { arguments.bool(forKey: "DemoChrome") }
    /// The reader opens with the Aa sheet up.
    static var showsAppearance: Bool { arguments.bool(forKey: "DemoAppearance") }

    /// A 0-based chapter the reader jumps to once open, through the same path as Contents.
    static var jumpTo: Int? {
        arguments.object(forKey: "DemoJumpTo") == nil ? nil : arguments.integer(forKey: "DemoJumpTo")
    }

    /// 1-based position on the shelf whose detail page is pushed.
    static var detailIndex: Int? {
        let n = arguments.integer(forKey: "DemoDetail")
        return n > 0 ? n : nil
    }

    /// Text the contents search opens with.
    static var contentsQuery: String? { arguments.string(forKey: "DemoContentsQuery") }
    /// The first illustration the reader shows opens the zoom viewer.
    static var opensImageViewer: Bool { arguments.bool(forKey: "DemoImageViewer") }
    /// The curl stops partway through its first forward turn, showing the page's back.
    static var freezesCurl: Bool { arguments.bool(forKey: "DemoCurlFreeze") }
    /// "YES" imports a generated PDF and opens it; "thumbs" also opens its thumbnail grid.
    static var pdf: String? { arguments.string(forKey: "DemoPDF") }

    static var tab: AppTab? {
        switch arguments.string(forKey: "DemoTab") {
        case "shelf": .shelf
        case "imports": .imports
        case "settings": .settings
        default: nil
        }
    }

    /// 1-based position on the shelf.
    static var readerIndex: Int? {
        let n = arguments.integer(forKey: "DemoReader")
        return n > 0 ? n : nil
    }

    private static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "ShioriDemo", directoryHint: .isDirectory)
    }

    /// A throwaway library, wiped on every launch, so demo data never touches the real one.
    static func paths() -> LibraryPaths? {
        guard usesDemoData else { return nil }
        if !keepsLibrary { try? FileManager.default.removeItem(at: root) }
        return LibraryPaths(root: root.appending(path: "Library", directoryHint: .isDirectory))
    }

    /// Demo settings live in their own suite, so one shot's accent or language never leaks
    /// into the next one or into the real app.
    static func defaults() -> UserDefaults {
        let name = "com.kaichuan.shiori.demo"
        let suite = UserDefaults(suiteName: name) ?? .standard
        if !keepsLibrary { suite.removePersistentDomain(forName: name) }
        return suite
    }

    @MainActor static func apply(to model: AppModel) async {
        if let tab { model.selectedTab = tab }
        applySettings(to: model.settings)
        if let theme = arguments.string(forKey: "DemoTheme").flatMap(ReaderTheme.init) {
            model.readerPreferences.theme = theme
        }
        if let layout = arguments.string(forKey: "DemoLayout").flatMap(ReaderLayout.init) {
            model.readerPreferences.layout = layout
        }
        if let effect = arguments.string(forKey: "DemoEffect").flatMap(PageTurnEffect.init) {
            model.readerPreferences.effect = effect
        }
        let kept = keepsLibrary && !((try? model.database.bookList())?.isEmpty ?? true)
        if usesDemoData, !kept {
            let sources = model.paths.root.deletingLastPathComponent().appending(path: "Sources")
            if usesWatchedFolder {
                // The scan does the importing, so the log shows a watched-folder batch.
                let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
                _ = try? DemoBooks.write(into: documents)
                model.watchedFolder.choose(documents)
                await model.watchedFolder.scanNow(settings: model.importSettings)
            } else {
                let urls = usesLongBook
                    ? (try? DemoBooks.writeLong(into: sources)).map { [$0] }
                    : try? DemoBooks.write(into: sources)
                if let urls {
                    await model.importFiles(urls, origin: .picker)
                }
            }
        }
        if let importPath {
            await model.importFiles([URL(filePath: importPath)], origin: .picker)
        }
        // One book part-read, so the shelf shows its ribbon and chapter status.
        if usesDemoData, !kept, !usesLongBook, let item = try? model.database.bookList().first(where: { $0.progress == nil }),
           let chapters = try? model.database.chapters(bookId: item.book.id), chapters.count > 3 {
            try? model.database.save(ShioriLibrary.Progress(
                bookId: item.book.id, chapterIndex: 2, keyTitle: chapters[2].keyTitle,
                keyOccurrence: chapters[2].keyOccurrence, offset: 0,
                fraction: 2 / Double(chapters.count), updatedAt: .now))
        }
        if marksUpdated, let first = try? model.database.bookList().first {
            try? model.database.markUpdated(bookId: first.id, addedChapters: 37, at: .now)
        }
        if showsImportResults {
            model.logFailures(sampleOutcomes, origin: .picker)
        }
        if pdf != nil {
            let url = model.paths.root.deletingLastPathComponent().appending(path: "Sources/示例.pdf")
            if (try? model.database.bookList())?.contains(where: { $0.book.format == .pdf }) != true {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? DemoPDF.write(to: url)
                await model.importFiles([url], origin: .picker)
            }
            model.openBook = (try? model.database.bookList())?.first { $0.book.format == .pdf }?.book
        }
        if let readerIndex, let list = try? model.database.bookList(), list.indices.contains(readerIndex - 1) {
            model.openBook = list[readerIndex - 1].book
        }
    }

    @MainActor private static func applySettings(to settings: AppSettings) {
        switch arguments.string(forKey: "DemoLanguage") {
        case "en": settings.language = .english
        case "zh-Hans": settings.language = .zhHans
        default: break
        }
        if let accent = arguments.string(forKey: "DemoAccent").flatMap(AccentPreset.init) {
            settings.accent = .preset(accent)
        }
    }

    /// One row of every kind, so the Import screenshot shows each style.
    private static let sampleOutcomes: [ImportOutcome] = [
        .added(bookId: UUID(), title: "桃花源记"),
        .alreadyInLibrary(bookId: UUID(), title: "兰亭集序"),
        .updated(bookId: UUID(), title: "岳阳楼记", change: .addedChapters(37)),
        .updated(bookId: UUID(), title: "醉翁亭记", change: .changed),
        .resplit(bookId: UUID(), title: "赤壁赋", chapters: 12),
        .skipped(fileName: "已删除.epub", reason: .removedEarlier),
        .skipped(fileName: "合集.zip", reason: .nestedArchive),
        .skipped(fileName: "云端.epub", reason: .waitingForDownload),
        .skipped(fileName: "书库", reason: .tooManyFiles(limit: 2000)),
        .failed(fileName: "加密的书.epub", reason: .drmProtected),
        .failed(fileName: "画册.epub", reason: .fixedLayout),
        .failed(fileName: "目录.epub", reason: .noChapters),
        .failed(fileName: "空白.txt", reason: .empty),
        .failed(fileName: "笔记.mobi", reason: .unsupportedFormat),
        .failed(fileName: "合集.txt", reason: .tooLarge(limitBytes: 128 << 20)),
        .failed(fileName: "损坏.epub", reason: .unreadable("demo")),
    ]
}
#endif
