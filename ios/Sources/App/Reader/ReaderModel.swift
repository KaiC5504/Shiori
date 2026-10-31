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
    /// The gap between chapters hangs below a chapter's last row rather than above the next
    /// title, so a chapter scrolled to the top starts right under the safe area.
    let endsChapter: Bool

    static func rows(chapter: Int, title: String, content: ChapterContent?) -> [ReaderRow] {
        let first = ParagraphAnchor(chapter: chapter, block: 0)
        guard let content else { return [ReaderRow(id: first, kind: .unreadable(title: title), endsChapter: true)] }
        guard !content.blocks.isEmpty else { return [ReaderRow(id: first, kind: .empty, endsChapter: true)] }
        let last = content.blocks.count - 1
        return content.blocks.enumerated().map { index, block in
            let kind: Kind
            switch block {
            case .heading(let text, let level): kind = index == 0 ? .title(text) : .heading(text, level: level)
            case .paragraph(let text): kind = .paragraph(text)
            case .image: kind = .image
            }
            return ReaderRow(id: ParagraphAnchor(chapter: chapter, block: index), kind: kind,
                             endsChapter: index == last)
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

/// A jump whose rows are in place. `finishJump` resumes tracking once the scroll has landed.
struct ReaderJump: Sendable {
    fileprivate let generation: Int
    let anchor: ParagraphAnchor
}

/// Holds a contiguous run of chapters around the visible one, so a 4,834-chapter book only
/// builds the chapters actually read, and saves the top visible paragraph.
@MainActor @Observable
final class ReaderModel {
    let book: Book
    let chapters: [Chapter]
    /// The saved paragraph, else the start of the book. `start()` settles the block.
    private(set) var initialAnchor: ParagraphAnchor
    /// The chapters in `displayed`, in order.
    private(set) var rows: [ReaderRow] = []
    private(set) var currentChapter: Int

    private let database: LibraryDatabase
    private let source: BookContentSource
    private let saved: ShioriLibrary.Progress?
    @ObservationIgnored private var loaded: [Int: LoadedChapter] = [:]
    @ObservationIgnored private var inFlight: [Int: Task<LoadedChapter, Never>] = [:]
    @ObservationIgnored private var displayed: ClosedRange<Int>?
    /// True until the first landing too: before it, nothing the scroll view reports is a place
    /// the reader has been.
    @ObservationIgnored private var isJumping = true
    @ObservationIgnored private var jumpGeneration = 0
    @ObservationIgnored private var extendTask: Task<Void, Never>?
    @ObservationIgnored private var lastVisible: ParagraphAnchor?
    @ObservationIgnored private var pending: ShioriLibrary.Progress?
    /// The position last written or restored; saving the same place again would only bump
    /// `updatedAt` and reorder the shelf.
    @ObservationIgnored private var lastSaved: ShioriLibrary.Progress?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// While a finger or momentum moves the text, the scroll view can't hold its place over
    /// rows inserted above it: the text slides into the new chapter, which asks for another
    /// one above, and the reader runs away upwards. Chapters join above only at rest.
    @ObservationIgnored private var isScrolling = false

    /// Chapters kept joined on each side of the visible one.
    private static let lead = 2

    private init(book: Book, database: LibraryDatabase, opened: OpenedBook) {
        self.book = book
        self.database = database
        chapters = opened.chapters
        source = opened.source
        saved = opened.saved
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

    /// Jumps to the saved chapter, then finds the saved paragraph in its text.
    func start() async -> ReaderJump? {
        guard let jump = await show(chapter: initialAnchor.chapter) else { return nil }
        if let saved, let content = loaded[jump.anchor.chapter]?.content {
            initialAnchor.block = ReadingPosition.block(for: saved, in: content)
        }
        // Nil when the chapter failed to load, so nothing is saved until the reader reaches
        // text that did, and the old position survives.
        pending = progress(at: initialAnchor)
        lastSaved = pending
        return ReaderJump(generation: jump.generation, anchor: initialAnchor)
    }

    /// Replaces the rows with `chapter` and the next one, so the target is the first row and
    /// the scroll lands on it at offset zero without estimating anything above. Tracking stays
    /// off until `finishJump`: until the scroll lands, the old offset over the new rows reports
    /// chapters that aren't on screen. Nil when a later jump has overtaken this one.
    func show(chapter: Int) async -> ReaderJump? {
        guard chapters.indices.contains(chapter) else { return nil }
        jumpGeneration += 1
        let generation = jumpGeneration
        isJumping = true
        // A running extension sees the new generation and stops without touching the rows.
        extendTask = nil
        currentChapter = chapter
        let span = chapter...min(chapter + 1, chapters.count - 1)
        let loads = span.map { index in Task { (index, await load(index, retryingFailure: true)) } }
        var results: [Int: LoadedChapter] = [:]
        for pendingLoad in loads {
            let (index, result) = await pendingLoad.value
            results[index] = result
        }
        guard generation == jumpGeneration else { return nil }
        loaded = results
        displayed = span
        rows = span.flatMap { results[$0]?.rows ?? [] }
        return ReaderJump(generation: generation, anchor: ParagraphAnchor(chapter: chapter, block: 0))
    }

    /// Resumes tracking at `jump.anchor`, saves it at once since a jump is a deliberate move,
    /// and starts joining the chapters around it.
    func finishJump(_ jump: ReaderJump) {
        guard isJumping, jump.generation == jumpGeneration else { return }
        isJumping = false
        lastVisible = jump.anchor
        currentChapter = jump.anchor.chapter
        pending = progress(at: jump.anchor) ?? pending
        saveNow()
        extendIfNeeded()
    }

    func visibleAnchorChanged(_ anchor: ParagraphAnchor) {
        guard !isJumping, chapters.indices.contains(anchor.chapter), anchor != lastVisible else { return }
        lastVisible = anchor
        pending = progress(at: anchor) ?? pending
        if anchor.chapter != currentChapter {
            currentChapter = anchor.chapter
            extendIfNeeded()
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func scrollPhaseChanged(isScrolling: Bool) {
        self.isScrolling = isScrolling
        if !isScrolling, !isJumping { extendIfNeeded() }
    }

    func saveNow() {
        saveTask?.cancel()
        guard var progress = pending, !Self.samePlace(progress, lastSaved) else { return }
        progress.updatedAt = .now
        do {
            try database.save(progress)
            lastSaved = progress
        } catch {
            readerLog.error("saving progress failed: \(error)")
        }
    }

    private static func samePlace(_ a: ShioriLibrary.Progress, _ b: ShioriLibrary.Progress?) -> Bool {
        guard let b else { return false }
        return a.chapterIndex == b.chapterIndex && a.keyTitle == b.keyTitle
            && a.keyOccurrence == b.keyOccurrence && a.offset == b.offset
    }

    /// Nil inside a chapter that failed to load: its offsets mean nothing.
    private func progress(at anchor: ParagraphAnchor) -> ShioriLibrary.Progress? {
        guard chapters.indices.contains(anchor.chapter), let content = loaded[anchor.chapter]?.content else {
            return nil
        }
        return ReadingPosition.progress(bookId: book.id, chapter: chapters[anchor.chapter],
                                        chapterCount: chapters.count, content: content,
                                        block: anchor.block, now: .now)
    }

    /// Rows are only ever added while reading. Dropping or swapping a chapter above the
    /// viewport changes the height above the text, which is what made it jump.
    private func extendIfNeeded() {
        guard extendTask == nil else { return }
        let generation = jumpGeneration
        extendTask = Task { [weak self] in
            await self?.extend(generation: generation)
            guard let self, generation == self.jumpGeneration else { return }
            self.extendTask = nil
        }
    }

    private func extend(generation: Int) async {
        while generation == jumpGeneration, let index = nextChapterToJoin() {
            let result = await load(index)
            guard generation == jumpGeneration, let range = displayed else { return }
            loaded[index] = result
            // The load may have outlasted the rest; it joins at the next one.
            if index < range.lowerBound, isScrolling { return }
            if index > range.upperBound {
                displayed = range.lowerBound...index
                rows.append(contentsOf: result.rows)
            } else {
                displayed = index...range.upperBound
                rows.insert(contentsOf: result.rows, at: 0)
            }
        }
    }

    /// Below first, since reading goes forward. Once filled, a chapter joins above only while
    /// a whole chapter sits between it and the visible one, so it lands out of sight.
    private func nextChapterToJoin() -> Int? {
        guard let range = displayed else { return nil }
        if range.upperBound - currentChapter < Self.lead, range.upperBound < chapters.count - 1 {
            return range.upperBound + 1
        }
        if !isScrolling, currentChapter - range.lowerBound < Self.lead, range.lowerBound > 0 {
            return range.lowerBound - 1
        }
        return nil
    }

    /// A failed chapter keeps its row, but `retryingFailure` reads it again.
    private func load(_ index: Int, retryingFailure: Bool = false) async -> LoadedChapter {
        if let done = loaded[index], done.content != nil || !retryingFailure { return done }
        let task = inFlight[index] ?? startLoading(index)
        let result = await task.value
        inFlight[index] = nil
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
}
