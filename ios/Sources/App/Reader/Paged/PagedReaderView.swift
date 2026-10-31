import ShioriLibrary
import SwiftUI

/// A place in the paged layout: the chapter and a UTF-16 offset into its plain text, which a
/// change of type or page size doesn't move.
struct ReaderPosition: Equatable, Sendable {
    var chapter: Int
    var offset: Int
}

@MainActor
protocol PagedSource: AnyObject {
    var chapterCount: Int { get }
    /// Laid out with the current typography; nil when the chapter failed to load.
    func layout(chapter: Int, size: PageSize) async -> ChapterLayout?
}

/// The paged layout (spec §7.2): Core Text pages turned by paragraph relay or Apple's curl.
/// Reads the effect, speed, tap zones and theme from `model.readerPreferences`.
///
/// `position` is the shown page's first offset, written on every turn. Set it from outside to
/// jump. A new type or page size shows the page holding the same offset and leaves `position`
/// alone, so the place doesn't creep back a page with every change.
struct PagedReaderView: View {
    let source: PagedSource
    @Binding var position: ReaderPosition
    let onMenu: () -> Void
    let onTurn: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale
    @Environment(\.self) private var environment
    @State private var chapters: PagedChapters
    @State private var shown: PagedPage?
    @State private var turns = 0
    /// The place this view last wrote, so a change from outside can be told apart from a turn.
    @State private var written: ReaderPosition?

    init(source: PagedSource, position: Binding<ReaderPosition>,
         onMenu: @escaping () -> Void, onTurn: @escaping () -> Void) {
        self.source = source
        _position = position
        self.onMenu = onMenu
        self.onTurn = onTurn
        _chapters = State(initialValue: PagedChapters(source: source))
    }

    var body: some View {
        let preferences = model.readerPreferences
        GeometryReader { proxy in
            // The paper and the curling page fill the screen; the text keeps to the safe area.
            let insets = proxy.safeAreaInsets
            let pageFrame = CGRect(x: insets.leading, y: insets.top, width: proxy.size.width,
                                   height: proxy.size.height)
            ZStack {
                if let shown {
                    stage(shown, pageFrame: pageFrame, preferences: preferences)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .animation(Motion.animation(.easeInOut(duration: 0.25), reduced: reduced), value: stageKind(preferences))
            .task(id: LayoutKey(size: PageSize(proxy.size), typography: preferences.typography)) {
                await relayout(to: PageSize(proxy.size))
            }
        }
        .background(preferences.theme.paper.ignoresSafeArea())
        .onChange(of: position) { _, place in
            guard place != written else { return }
            // Otherwise a jump back to the page last turned to would look like that turn.
            written = place
            chapters.retry(place.chapter)
            Task { await present() }
        }
        .shioriHaptic(.selection, trigger: turns)
        .preference(key: PagedPageNumberKey.self, value: shown.map(PagedPageNumber.init))
    }

    @ViewBuilder
    private func stage(_ page: PagedPage, pageFrame: CGRect, preferences: ReaderPreferences) -> some View {
        let style = pageStyle(preferences)
        let taps = PageTaps(layout: preferences.tapLayout, bothSidesForward: preferences.bothSidesForward)
        switch stageKind(preferences) {
        case .curl:
            CurlPages(page: page, style: style, pageFrame: pageFrame, taps: taps, chapters: chapters,
                      onTurn: turned, onMenu: onMenu)
        case .relay:
            RelayTurn(page: page, style: style, pageFrame: pageFrame,
                      motion: reduced ? .crossfade : .relay(preferences.speed), taps: taps, chapters: chapters,
                      onTurn: turned, onMenu: onMenu)
        }
    }

    /// Under Reduce Motion every effect is the relay's crossfade. Paper turn (M9) is the relay
    /// until it ships.
    private func stageKind(_ preferences: ReaderPreferences) -> StageKind {
        preferences.effect == .curl && !reduced ? .curl : .relay
    }

    private func pageStyle(_ preferences: ReaderPreferences) -> PageStyle {
        var failure: LocalizedStringResource = "Couldn't open this chapter."
        failure.locale = locale
        return PageStyle(paper: preferences.theme.paper.resolve(in: environment).cgColor,
                         ink: preferences.textColor.resolve(in: environment).cgColor,
                         secondaryInk: preferences.theme.inkSecondary.resolve(in: environment).cgColor,
                         failure: String(localized: failure), scale: displayScale)
    }

    private func relayout(to size: PageSize) async {
        // A first layout pass can report no size at all.
        guard size.width >= 1, size.height >= 1 else { return }
        chapters.reset(size: size)
        await present()
    }

    /// Shows the page holding `position`, once its chapter is laid out at the current size.
    private func present() async {
        while true {
            guard let place = clamped(position) else { return }
            // Nil when a newer size or type took over; its own present() shows the page.
            guard let slot = await chapters.slot(for: place.chapter) else { return }
            // A turn or a jump while the chapter laid out moved the place; show that one instead.
            guard clamped(position) == place else { continue }
            shown = chapters.page(in: place.chapter, slot: slot, containing: place.offset)
            chapters.prefetch(around: place.chapter)
            return
        }
    }

    private func clamped(_ place: ReaderPosition) -> ReaderPosition? {
        let count = chapters.chapterCount
        guard count > 0 else { return nil }
        return ReaderPosition(chapter: min(max(place.chapter, 0), count - 1), offset: max(place.offset, 0))
    }

    private func turned(to page: PagedPage) {
        if page.chapter != shown?.chapter { chapters.prefetch(around: page.chapter) }
        let place = ReaderPosition(chapter: page.chapter, offset: page.offset)
        shown = page
        written = place
        position = place
        turns += 1
        onTurn()
    }

    private enum StageKind {
        case relay, curl
    }

    private struct LayoutKey: Equatable {
        var size: PageSize
        var typography: ReaderTypography
    }
}

/// The shown page's place in its chapter, for the footer's "page / pages" (spec §7.7). Read it
/// with `onPreferenceChange(PagedPageNumberKey.self)`.
struct PagedPageNumber: Equatable {
    /// 1-based.
    var page: Int
    var pages: Int

    init(_ shown: PagedPage) {
        page = shown.index + 1
        pages = shown.layout?.pages.count ?? 1
    }
}

struct PagedPageNumberKey: PreferenceKey {
    static let defaultValue: PagedPageNumber? = nil

    static func reduce(value: inout PagedPageNumber?, nextValue: () -> PagedPageNumber?) {
        value = nextValue() ?? value
    }
}

/// The chapters' layouts at the current page size and type, and how pages follow one another
/// across them. Only the shown chapter and its neighbours are kept; the source has its own cache.
@MainActor
final class PagedChapters {
    enum Slot {
        case ready(ChapterLayout)
        case failed
    }

    private let source: PagedSource
    private var size: PageSize?
    /// Bumped by every reset, so a layout that finishes for an old size or type is dropped.
    private var generation = 0
    private var slots: [Int: Slot] = [:]
    private var loads: [Int: Task<ChapterLayout?, Never>] = [:]

    init(source: PagedSource) {
        self.source = source
    }

    var chapterCount: Int { source.chapterCount }

    func reset(size: PageSize) {
        generation += 1
        self.size = size
        slots = [:]
        loads = [:]
    }

    /// Nil when a reset overtook the layout.
    func slot(for chapter: Int) async -> Slot? {
        if let slot = slots[chapter] { return slot }
        guard let size else { return nil }
        let generation = generation
        let task: Task<ChapterLayout?, Never>
        if let running = loads[chapter] {
            task = running
        } else {
            let source = source
            task = Task { await source.layout(chapter: chapter, size: size) }
            loads[chapter] = task
        }
        let layout = await task.value
        guard generation == self.generation else { return nil }
        loads[chapter] = nil
        let slot = layout.map(Slot.ready) ?? .failed
        slots[chapter] = slot
        return slot
    }

    /// A jump to a chapter that failed reads it again.
    func retry(_ chapter: Int) {
        if case .failed = slots[chapter] { slots[chapter] = nil }
    }

    /// Lays out the chapters either side ahead of the turn that reaches them, and lets go of
    /// the rest.
    func prefetch(around chapter: Int) {
        slots = slots.filter { abs($0.key - chapter) <= 1 }
        for neighbour in [chapter + 1, chapter - 1] {
            load(neighbour)
        }
    }

    func page(in chapter: Int, slot: Slot, containing offset: Int) -> PagedPage {
        switch slot {
        case .ready(let layout): PagedPage(chapter: chapter, index: layout.page(containing: offset), layout: layout)
        case .failed: PagedPage(chapter: chapter, index: 0, layout: nil)
        }
    }

    /// The page a turn from `page` reaches, if it's at hand. Nil at either end of the book, and
    /// while the next chapter is still being laid out, which this starts.
    func cachedNeighbour(of page: PagedPage, forward: Bool) -> PagedPage? {
        if let layout = page.layout {
            let index = page.index + (forward ? 1 : -1)
            if layout.pages.indices.contains(index) {
                return PagedPage(chapter: page.chapter, index: index, layout: layout)
            }
        }
        let chapter = page.chapter + (forward ? 1 : -1)
        guard let slot = slots[chapter] else {
            load(chapter)
            return nil
        }
        return Self.edge(of: chapter, slot, first: forward)
    }

    /// The page a turn from `page` reaches, waiting for its chapter's layout if need be.
    func neighbour(of page: PagedPage, forward: Bool) async -> PagedPage? {
        if let near = cachedNeighbour(of: page, forward: forward) { return near }
        let chapter = page.chapter + (forward ? 1 : -1)
        guard (0..<chapterCount).contains(chapter), let slot = await slot(for: chapter) else { return nil }
        return Self.edge(of: chapter, slot, first: forward)
    }

    private func load(_ chapter: Int) {
        guard (0..<chapterCount).contains(chapter), slots[chapter] == nil, loads[chapter] == nil else { return }
        Task { _ = await slot(for: chapter) }
    }

    /// A chapter's first page going forward into it, its last going back.
    private static func edge(of chapter: Int, _ slot: Slot, first: Bool) -> PagedPage {
        switch slot {
        case .ready(let layout): PagedPage(chapter: chapter, index: first ? 0 : layout.pages.count - 1, layout: layout)
        case .failed: PagedPage(chapter: chapter, index: 0, layout: nil)
        }
    }
}
