import Foundation
import Observation
import os
import ShioriLibrary
import SwiftUI

private let readerLog = Logger(subsystem: "com.kaichuan.shiori", category: "reader")

/// A paragraph in the scroll: the chapter's index in the book and the block's in the chapter.
struct ParagraphAnchor: Hashable, Sendable {
    var chapter: Int
    var block: Int
}

/// An illustration in the text. `aspect` (width / height) is read from the image header when
/// the chapter loads, so the row's height is fixed before the picture arrives.
struct ReaderImage: Hashable, Sendable {
    let path: String
    let aspect: CGFloat?
}

struct ReaderRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case title(String)
        case heading(String, level: Int)
        case paragraph(String)
        case image(ReaderImage)
        case unreadable(title: String)
        case empty
    }

    let id: ParagraphAnchor
    let kind: Kind
    /// The gap between chapters hangs below a chapter's last row rather than above the next
    /// title, so a chapter scrolled to the top starts right under the safe area.
    let endsChapter: Bool

    static func rows(chapter: Int, title: String, content: ChapterContent?,
                     imageSize: (String) -> CGSize? = { _ in nil }) -> [ReaderRow] {
        let first = ParagraphAnchor(chapter: chapter, block: 0)
        guard let content else { return [ReaderRow(id: first, kind: .unreadable(title: title), endsChapter: true)] }
        guard !content.blocks.isEmpty else { return [ReaderRow(id: first, kind: .empty, endsChapter: true)] }
        let last = content.blocks.count - 1
        return content.blocks.enumerated().map { index, block in
            let kind: Kind
            switch block {
            case .heading(let text, let level): kind = index == 0 ? .title(text) : .heading(text, level: level)
            case .paragraph(let text): kind = .paragraph(text)
            case .image(let path):
                let aspect = imageSize(path).flatMap { $0.width > 0 && $0.height > 0 ? $0.width / $0.height : nil }
                kind = .image(ReaderImage(path: path, aspect: aspect))
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
/// builds the chapters actually read, and saves the top visible paragraph. In the paged layout
/// it lays chapters out for `PagedReaderView` and saves the page's first character instead.
@MainActor @Observable
final class ReaderModel {
    let book: Book
    let chapters: [Chapter]
    /// The saved paragraph, else the start of the book. `start()` settles the block.
    private(set) var initialAnchor: ParagraphAnchor
    /// The saved place to the character, which the paged layout opens on. `start()` settles it.
    private(set) var initialPlace: ReaderPosition
    /// The chapters in `displayed`, in order.
    private(set) var rows: [ReaderRow] = []
    private(set) var currentChapter: Int

    /// True while a jump or a held place is landing; nothing the scroll reports then is a
    /// place the reader has been.
    var isSettling: Bool { isJumping }

    private let database: LibraryDatabase
    private let source: BookContentSource
    private let saved: ShioriLibrary.Progress?
    /// Read at each layout, so pages always use the type the Aa sheet shows.
    private let preferences: ReaderPreferences
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
    /// The paragraph `holdPlace` is putting back at the top, and the generation it took; any
    /// jump after it makes it stale.
    @ObservationIgnored private var held: (generation: Int, anchor: ParagraphAnchor)?
    /// Where a jump is taking the scroll until it lands, so a switch to pages in that moment
    /// goes there rather than to the paragraph it left.
    @ObservationIgnored private var landing: ReaderPosition?

    /// The paged layout's place; nil while the scroll shows.
    @ObservationIgnored private var pagedPlace: ReaderPosition?
    /// The text of the chapters the pages can reach next, for saving, and their newest layouts.
    @ObservationIgnored private var pagedContents: [Int: ChapterContent] = [:]
    @ObservationIgnored private var pagedLayouts: [Int: ChapterLayout] = [:]
    @ObservationIgnored private var pagedSize: PageSize?
    @ObservationIgnored private var pagedTypography: ReaderTypography?

    /// Shared by every reader, so a book opened again finds its chapters already laid out.
    private static let paginator = Paginator(cache: PaginationCache())

    /// Chapters kept joined on each side of the visible one.
    private static let lead = 2

    private init(book: Book, database: LibraryDatabase, preferences: ReaderPreferences, opened: OpenedBook) {
        self.book = book
        self.database = database
        self.preferences = preferences
        chapters = opened.chapters
        source = opened.source
        saved = opened.saved
        let start = opened.saved.map { ReadingPosition.chapterIndex(for: $0, in: opened.chapters) } ?? 0
        initialAnchor = ParagraphAnchor(chapter: start, block: 0)
        initialPlace = ReaderPosition(chapter: start, offset: 0)
        currentChapter = start
    }

    /// Reads the chapter list and indexes the archive off the main actor: for the test book
    /// that is thousands of rows and ZIP entries.
    static func open(book: Book, database: LibraryDatabase, paths: LibraryPaths,
                     preferences: ReaderPreferences) async throws -> ReaderModel {
        let opened = try await Task.detached(priority: .userInitiated) {
            let chapters = try database.chapters(bookId: book.id)
            guard !chapters.isEmpty else { throw ReaderError.noChapters }
            return OpenedBook(chapters: chapters, saved: try database.progress(bookId: book.id),
                              source: try BookContentSource(book: book, paths: paths))
        }.value
        return ReaderModel(book: book, database: database, preferences: preferences, opened: opened)
    }

    /// Jumps to the saved chapter, then finds the saved paragraph in its text.
    func start() async -> ReaderJump? {
        guard let jump = await show(chapter: initialAnchor.chapter) else { return nil }
        if let saved, let content = loaded[jump.anchor.chapter]?.content {
            initialAnchor.block = ReadingPosition.block(for: saved, in: content)
            initialPlace.offset = min(max(saved.offset, 0), content.plainText.utf16.count)
        }
        // Nil when the chapter failed to load, so nothing is saved until the reader reaches
        // text that did, and the old position survives.
        pending = progress(at: initialAnchor)
        lastSaved = pending
        landing = initialPlace
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
        // The scroll owns the place from here; a paged jump still waiting for its chapter
        // mustn't save over it.
        pagedPlace = nil
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
        landing = ReaderPosition(chapter: chapter, offset: 0)
        return ReaderJump(generation: generation, anchor: ParagraphAnchor(chapter: chapter, block: 0))
    }

    /// The scroll at the paragraph holding `place`, for leaving the paged layout. Lands like
    /// any jump, through `finishJump`.
    func show(place: ReaderPosition) async -> ReaderJump? {
        guard let jump = await show(chapter: place.chapter) else { return nil }
        let block = loaded[place.chapter]?.content?.block(containing: place.offset) ?? 0
        landing = place
        return ReaderJump(generation: jump.generation, anchor: ParagraphAnchor(chapter: place.chapter, block: block))
    }

    /// Resumes tracking at `jump.anchor`, saves it at once since a jump is a deliberate move,
    /// and starts joining the chapters around it.
    func finishJump(_ jump: ReaderJump) {
        guard isJumping, jump.generation == jumpGeneration else { return }
        isJumping = false
        landing = nil
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

    /// New typography or a new width re-lays out every row, and while it settles the scroll
    /// view reports paragraphs the reader never reached, which would move the chapter and join
    /// others. So tracking holds as for a jump, on the paragraph that was at the top, and the
    /// rows stay. Nil while a jump is landing: it lands on its own target.
    func holdPlace() -> ReaderJump? {
        let anchor: ParagraphAnchor
        if !isJumping, let lastVisible {
            anchor = lastVisible
        } else if let held, held.generation == jumpGeneration {
            anchor = held.anchor
        } else {
            return nil
        }
        jumpGeneration += 1
        isJumping = true
        extendTask = nil
        held = (jumpGeneration, anchor)
        return ReaderJump(generation: jumpGeneration, anchor: anchor)
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

    func imageData(at path: String) async -> Data? {
        let source = source
        return await Task.detached(priority: .userInitiated) {
            do {
                return try source.imageData(at: path)
            } catch {
                readerLog.error("image \(path) failed to load: \(error)")
                return nil
            }
        }.value
    }

    /// The chapter's illustrations in reading order, from its loaded rows.
    func images(inChapter chapter: Int) -> [ReaderImage] {
        (loaded[chapter]?.rows ?? []).compactMap { row in
            if case .image(let image) = row.kind { image } else { nil }
        }
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
                                 rows: ReaderRow.rows(chapter: index, title: chapter.title, content: content,
                                                      imageSize: source.imageSize(at:)))
        }
        inFlight[index] = task
        return task
    }
}

/// The paged layout: chapters laid out for `PagedReaderView`, and its place, kept and saved as
/// (chapter, UTF-16 offset of the page's first character).
extension ReaderModel: PagedSource {
    var chapterCount: Int { chapters.count }

    /// Leaves the scroll for pages at the top paragraph's first character, or the place a jump
    /// is landing on.
    func switchToPaged() -> ReaderPosition {
        let place = landing ?? scrollPlace(of: lastVisible ?? initialAnchor)
        enterPaged(at: place)
        return place
    }

    /// Hands the place to the pages. Anything the scroll was still landing is dropped, and it
    /// tracks nothing until `show(place:)` brings it back.
    func enterPaged(at place: ReaderPosition) {
        jumpGeneration += 1
        isJumping = true
        extendTask = nil
        held = nil
        landing = nil
        pagedPlace = place
        currentChapter = min(max(place.chapter, 0), chapters.count - 1)
    }

    /// The pages turned to `place`, or jumped there. A turn saves 500 ms later, as a scroll does;
    /// a jump at once. In a chapter that couldn't be read nothing is saved, so the last good
    /// place survives.
    func pagedMoved(to place: ReaderPosition, jumped: Bool = false) {
        guard chapters.indices.contains(place.chapter) else { return }
        pagedPlace = place
        currentChapter = place.chapter
        trimPaged()
        guard let content = pagedContents[place.chapter] else {
            // A turn's page was laid out from its chapter's text, so a turn without it is into a
            // chapter that couldn't be read, and the save still due for the page before stands.
            // A jump can simply arrive before its chapter has loaded.
            guard jumped else { return }
            Task { [weak self] in
                guard let self, let content = await self.pagedContent(place.chapter), self.pagedPlace == place
                else { return }
                self.pending = self.progress(at: place, in: content)
                self.saveNow()
            }
            return
        }
        pending = progress(at: place, in: content)
        if jumped {
            saveNow()
            return
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// The page a turn from `place` reaches, from the layouts already made: for taps the page
    /// itself never sees. Nil at either end of the book, or before the chapter behind is laid out.
    func pagedNeighbour(of place: ReaderPosition, forward: Bool) -> ReaderPosition? {
        guard let layout = pagedLayouts[place.chapter] else { return nil }
        let index = layout.page(containing: place.offset) + (forward ? 1 : -1)
        if layout.pages.indices.contains(index) {
            return ReaderPosition(chapter: place.chapter, offset: layout.pages[index].range.lowerBound)
        }
        let chapter = place.chapter + (forward ? 1 : -1)
        guard chapters.indices.contains(chapter) else { return nil }
        if forward { return ReaderPosition(chapter: chapter, offset: 0) }
        guard let last = pagedLayouts[chapter]?.pages.last else { return nil }
        return ReaderPosition(chapter: chapter, offset: last.range.lowerBound)
    }

    func layout(chapter: Int, size: PageSize) async -> ChapterLayout? {
        guard chapters.indices.contains(chapter) else { return nil }
        let typography = preferences.typography
        // Layouts at another size or type would point taps at the wrong pages.
        if size != pagedSize || typography != pagedTypography {
            pagedSize = size
            pagedTypography = typography
            pagedLayouts = [:]
        }
        guard let content = await pagedContent(chapter) else { return nil }
        let key = PaginationKey(bookId: book.id, chapter: chapters[chapter].key, typography: typography, size: size)
        let paginator = Self.paginator
        // A detached task awaited from here would be raised to this task's priority; a global
        // queue keeps the neighbours behind the chapter being read.
        let qos: DispatchQoS.QoSClass = chapter == currentChapter ? .userInitiated : .utility
        let layout = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(returning: paginator.layout(content, key: key))
            }
        }
        if size == pagedSize, typography == pagedTypography {
            pagedLayouts[chapter] = layout
            trimPaged()
        }
        return layout
    }

    private func scrollPlace(of anchor: ParagraphAnchor) -> ReaderPosition {
        ReaderPosition(chapter: anchor.chapter,
                       offset: loaded[anchor.chapter]?.content?.offset(ofBlock: anchor.block) ?? 0)
    }

    private func progress(at place: ReaderPosition, in content: ChapterContent) -> ShioriLibrary.Progress {
        ReadingPosition.progress(bookId: book.id, chapter: chapters[place.chapter], chapterCount: chapters.count,
                                 content: content, offset: place.offset, now: .now)
    }

    /// The same loads the scroll uses, so a chapter read in both is read from the archive once.
    private func pagedContent(_ chapter: Int) async -> ChapterContent? {
        if let content = pagedContents[chapter] { return content }
        guard let content = await load(chapter, retryingFailure: true).content else { return nil }
        pagedContents[chapter] = content
        trimPaged()
        return content
    }

    /// Keeps the chapters a turn or two can reach.
    private func trimPaged() {
        let near = (currentChapter - 2)...(currentChapter + 2)
        pagedContents = pagedContents.filter { near.contains($0.key) }
        pagedLayouts = pagedLayouts.filter { near.contains($0.key) }
    }
}

extension EnvironmentValues {
    @Entry var readerModel: ReaderModel? = nil
    /// Opens the zoom viewer over the reader.
    @Entry var openReaderImage: ((ImageViewerRequest) -> Void)? = nil
}
