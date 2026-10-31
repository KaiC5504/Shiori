import Foundation
import Observation
import os
import ShioriLibrary

private let readerLog = Logger(subsystem: "com.kaichuan.shiori", category: "reader")

/// A paragraph in the scroll: the chapter's index in the book and the block's in the chapter.
struct ParagraphAnchor: Hashable, Sendable {
    var chapter: Int
    var block: Int
}

struct ReaderRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case title(String)
        case heading(String, level: Int)
        case paragraph(String)
        case image
        case unreadable(title: String)
        case empty
    }

    let id: ParagraphAnchor
    let kind: Kind

    static func rows(chapter: Int, title: String, content: ChapterContent?) -> [ReaderRow] {
        let first = ParagraphAnchor(chapter: chapter, block: 0)
        guard let content else { return [ReaderRow(id: first, kind: .unreadable(title: title))] }
        guard !content.blocks.isEmpty else { return [ReaderRow(id: first, kind: .empty)] }
        return content.blocks.enumerated().map { index, block in
            let kind: Kind
            switch block {
            case .heading(let text, let level): kind = index == 0 ? .title(text) : .heading(text, level: level)
            case .paragraph(let text): kind = .paragraph(text)
            case .image: kind = .image
            }
            return ReaderRow(id: ParagraphAnchor(chapter: chapter, block: index), kind: kind)
        }
    }
}

/// A chapter that finished loading; nil content means it couldn't be read.
private struct LoadedChapter: Sendable {
    let content: ChapterContent?
    let rows: [ReaderRow]
}

private struct OpenedBook: Sendable {
    let chapters: [Chapter]
    let saved: ShioriLibrary.Progress?
    let source: BookContentSource
}

enum ReaderError: Error {
    case noChapters
}

/// Holds a window of at most five chapters around the visible one, so a 4,834-chapter book
/// never builds more than a few chapters of rows, and saves the top visible paragraph.
@MainActor @Observable
final class ReaderModel {
    let book: Book
    let chapters: [Chapter]
    /// The saved paragraph, else the start of the book. `start()` settles the block.
    private(set) var initialAnchor: ParagraphAnchor
    /// A contiguous run of loaded chapters around `currentChapter`.
    private(set) var rows: [ReaderRow] = []
    private(set) var currentChapter: Int

    private let database: LibraryDatabase
    private let source: BookContentSource
    private let saved: ShioriLibrary.Progress?
    @ObservationIgnored private var loaded: [Int: LoadedChapter] = [:]
    @ObservationIgnored private var inFlight: [Int: Task<LoadedChapter, Never>] = [:]
    @ObservationIgnored private var displayed: ClosedRange<Int>?
    @ObservationIgnored private var isReady = false
    @ObservationIgnored private var isJumping = false
    @ObservationIgnored private var pending: ShioriLibrary.Progress?
    @ObservationIgnored private var lastSaved: ShioriLibrary.Progress?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let radius = 2

    private init(book: Book, database: LibraryDatabase, opened: OpenedBook) {
        self.book = book
        self.database = database
        chapters = opened.chapters
        source = opened.source
        saved = opened.saved
        lastSaved = opened.saved
        let start = opened.saved.map { ReadingPosition.chapterIndex(for: $0, in: opened.chapters) } ?? 0
        initialAnchor = ParagraphAnchor(chapter: start, block: 0)
        currentChapter = start
    }

    /// Reads the chapter list and indexes the archive off the main actor: for the test book
    /// that is thousands of rows and ZIP entries.
    static func open(book: Book, database: LibraryDatabase, paths: LibraryPaths) async throws -> ReaderModel {
        let opened = try await Task.detached(priority: .userInitiated) {
            let chapters = try database.chapters(bookId: book.id)
            guard !chapters.isEmpty else { throw ReaderError.noChapters }
            return OpenedBook(chapters: chapters, saved: try database.progress(bookId: book.id),
                              source: try BookContentSource(book: book, paths: paths))
        }.value
        return ReaderModel(book: book, database: database, opened: opened)
    }

    /// Loads the chapters around the saved one, then finds the saved paragraph in its text.
    func start() async {
        let chapter = initialAnchor.chapter
        await show(chapter: chapter)
        if let saved, let content = await content(for: chapter) {
            initialAnchor.block = ReadingPosition.block(for: saved, in: content)
        }
        pending = progress(at: initialAnchor)
        isReady = true
    }

    /// Loads the whole window around `chapter` before swapping the rows, so a jump or the
    /// first screen lands in one step instead of chapters arriving above the text.
    func show(chapter: Int) async {
        guard chapters.indices.contains(chapter) else { return }
        isJumping = true
        currentChapter = chapter
        trimToWindow()
        let loads = windowByDistance.map { index in Task { await load(index) } }
        for pendingLoad in loads { _ = await pendingLoad.value }
        isJumping = false
        rebuildRows()
    }

    func content(for chapter: Int) async -> ChapterContent? {
        guard chapters.indices.contains(chapter) else { return nil }
        return await load(chapter).content
    }

    func visibleAnchorChanged(_ anchor: ParagraphAnchor) {
        guard isReady, !isJumping, chapters.indices.contains(anchor.chapter) else { return }
        pending = progress(at: anchor) ?? pending
        if anchor.chapter != currentChapter {
            currentChapter = anchor.chapter
            trimToWindow()
            rebuildRows()
            fillWindow()
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save(onlyIfMoved: true)
        }
    }

    func saveNow() {
        save(onlyIfMoved: false)
    }

    private func save(onlyIfMoved: Bool) {
        saveTask?.cancel()
        guard var progress = pending else { return }
        if onlyIfMoved, let lastSaved, lastSaved.chapterIndex == progress.chapterIndex,
           lastSaved.offset == progress.offset {
            return
        }
        progress.updatedAt = .now
        do {
            try database.save(progress)
            lastSaved = progress
        } catch {
            readerLog.error("saving progress failed: \(error)")
        }
    }

    private func progress(at anchor: ParagraphAnchor) -> ShioriLibrary.Progress? {
        guard chapters.indices.contains(anchor.chapter), let entry = loaded[anchor.chapter] else { return nil }
        return ReadingPosition.progress(bookId: book.id, chapter: chapters[anchor.chapter],
                                        chapterCount: chapters.count,
                                        content: entry.content ?? ChapterContent(blocks: []),
                                        block: anchor.block, now: .now)
    }

    private var window: ClosedRange<Int> {
        max(0, currentChapter - Self.radius)...min(chapters.count - 1, currentChapter + Self.radius)
    }

    /// The visible chapter first, then outwards, so the next chapter is ready before the far ones.
    private var windowByDistance: [Int] {
        window.sorted { abs($0 - currentChapter) < abs($1 - currentChapter) }
    }

    private func trimToWindow() {
        let window = window
        loaded = loaded.filter { window.contains($0.key) }
    }

    private func fillWindow() {
        for index in windowByDistance where loaded[index] == nil && inFlight[index] == nil {
            Task {
                _ = await load(index)
                rebuildRows()
            }
        }
    }

    private func load(_ index: Int) async -> LoadedChapter {
        if let done = loaded[index] { return done }
        let task = inFlight[index] ?? startLoading(index)
        let result = await task.value
        inFlight[index] = nil
        // A chapter the reader scrolled away from while it parsed would only be evicted again.
        if window.contains(index) { loaded[index] = result }
        return result
    }

    private func startLoading(_ index: Int) -> Task<LoadedChapter, Never> {
        let source = source
        let chapter = chapters[index]
        let task = Task.detached(priority: .userInitiated) {
            var content: ChapterContent?
            do {
                content = try source.content(of: chapter)
            } catch {
                readerLog.error("chapter \(index) failed to load: \(error)")
            }
            return LoadedChapter(content: content,
                                 rows: ReaderRow.rows(chapter: index, title: chapter.title, content: content))
        }
        inFlight[index] = task
        return task
    }

    /// Shows only chapters joined to the visible one, so a slow neighbour never leaves a gap
    /// that later fills in and pushes the text around.
    private func rebuildRows() {
        guard !isJumping else { return }
        var range: ClosedRange<Int>?
        if loaded[currentChapter] != nil {
            let window = window
            var low = currentChapter
            var high = currentChapter
            while low > window.lowerBound, loaded[low - 1] != nil { low -= 1 }
            while high < window.upperBound, loaded[high + 1] != nil { high += 1 }
            range = low...high
        }
        guard range != displayed else { return }
        displayed = range
        rows = range.map { run in run.flatMap { loaded[$0]?.rows ?? [] } } ?? []
    }
}
