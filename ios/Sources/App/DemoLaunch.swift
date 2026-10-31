#if DEBUG
import Foundation
import ShioriLibrary

/// Launch arguments that let the compile check screenshot every screen with fake data.
/// Launch arguments land in UserDefaults' argument domain, so `-DemoTab shelf` reads as a string.
enum DemoLaunch {
    private static var defaults: UserDefaults { .standard }

    static var usesDemoData: Bool { defaults.bool(forKey: "DemoData") }
    static var showContents: Bool { defaults.bool(forKey: "DemoContents") }
    static var showsImportResults: Bool { defaults.bool(forKey: "DemoImportResults") }
    /// Imports only the generated 3,000-chapter book, for the reader's UI tests.
    static var usesLongBook: Bool { defaults.bool(forKey: "DemoLongBook") }

    /// A 0-based chapter the reader jumps to once open, through the same path as Contents.
    static var jumpTo: Int? {
        defaults.object(forKey: "DemoJumpTo") == nil ? nil : defaults.integer(forKey: "DemoJumpTo")
    }

    static var tab: AppTab? {
        switch defaults.string(forKey: "DemoTab") {
        case "shelf": .shelf
        case "imports": .imports
        case "settings": .settings
        default: nil
        }
    }

    /// 1-based position on the shelf.
    static var readerIndex: Int? {
        let n = defaults.integer(forKey: "DemoReader")
        return n > 0 ? n : nil
    }

    /// A throwaway library, wiped on every launch, so demo data never touches the real one.
    static func paths() -> LibraryPaths? {
        guard usesDemoData else { return nil }
        let root = FileManager.default.temporaryDirectory.appending(path: "ShioriDemo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        return LibraryPaths(root: root.appending(path: "Library", directoryHint: .isDirectory))
    }

    @MainActor static func apply(to model: AppModel) async {
        if let tab { model.selectedTab = tab }
        if usesDemoData {
            let sources = model.paths.root.deletingLastPathComponent().appending(path: "Sources")
            let urls = usesLongBook
                ? (try? DemoBooks.writeLong(into: sources)).map { [$0] }
                : try? DemoBooks.write(into: sources)
            if let urls {
                await model.importFiles(urls)
            }
        }
        if showsImportResults {
            model.recentImports = sampleOutcomes
        }
        if let readerIndex, let list = try? model.database.bookList(), list.indices.contains(readerIndex - 1) {
            model.openBook = list[readerIndex - 1].book
        }
    }

    /// One row of every kind, so the Import screenshot shows each style.
    private static let sampleOutcomes: [ImportOutcome] = [
        .added(bookId: UUID(), title: "桃花源记"),
        .alreadyInLibrary(bookId: UUID(), title: "兰亭集序"),
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
