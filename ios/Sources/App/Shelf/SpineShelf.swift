import ShioriLibrary
import SwiftUI

/// The 3D spine shelf (spec §6.2): the featured books stand in a row that snaps book by book,
/// and the one at the centre, the crest, comes forward and turns to show its cover. Tapping
/// the crest opens it; tapping another book brings it to the crest.
struct SpineShelf: View {
    let books: [BookListItem]
    /// Set once the opening reveal has played, so slots met later don't wait out a stagger.
    let settled: Bool
    let open: (BookListItem) -> Void

    @Environment(\.motionReduced) private var reduced
    @State private var crest: Int?
    @State private var width: CGFloat = 0
    @State private var scrolling = false
    @State private var ticks = 0

    init(books: [BookListItem], settled: Bool, open: @escaping (BookListItem) -> Void) {
        self.books = books
        self.settled = settled
        self.open = open
        _crest = State(initialValue: ShelfRing(books).home)
    }

    var body: some View {
        let ring = ShelfRing(books)
        let current = ring.item(at: crest ?? ring.home)
        VStack(alignment: .leading, spacing: 6) {
            if width > 0 {
                row(ring, ShelfMetrics(width: width, reduced: reduced), current: current)
            } else {
                Color.clear.frame(height: ShelfMetrics(width: 390, reduced: reduced).stageHeight)
            }
            if let current {
                CrestCaption(item: current, open: { open(current) })
                    .padding(.horizontal, 20)
                    .staggeredReveal(settled ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: ring.ids) { crest = ring.home }
        .shioriHaptic(.selection, trigger: ticks)
    }

    private func row(_ ring: ShelfRing, _ metrics: ShelfMetrics, current: BookListItem?) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<ring.slotCount, id: \.self) { slot in
                    let index = ring.index(at: slot)
                    let item = ring.books[index]
                    SpineBook(item: item, number: index + 1, marked: item.id == ring.lastReadId, metrics: metrics)
                        .staggeredReveal(settled ? 0 : min(abs(slot - ring.home), 8) + 2)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, (metrics.viewport - metrics.pitch) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $crest, anchor: .center)
        .onScrollPhaseChange { _, phase in scrolling = phase.isScrolling }
        .onChange(of: crest) {
            if scrolling { ticks += 1 }
        }
        .frame(height: metrics.stageHeight)
        .background { ShelfBoard(metrics: metrics) }
        .contentShape(Rectangle())
        .onTapGesture { location in
            tap(at: location.x, ring: ring, metrics: metrics)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("3D shelf"))
        .accessibilityValue(Text(verbatim: current?.book.title ?? ""))
        .accessibilityAdjustableAction { direction in
            guard let crest else { return }
            switch direction {
            case .increment: self.crest = min(crest + 1, ring.slotCount - 1)
            case .decrement: self.crest = max(crest - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityAction {
            if let current { open(current) }
        }
    }

    // The books are drawn well away from their slots' layout frames (the crest spans several),
    // so a tap is mapped back to a book through the same layout the poses use.
    private func tap(at x: CGFloat, ring: ShelfRing, metrics: ShelfMetrics) {
        guard let crest, let item = ring.item(at: crest) else { return }
        let offset = x - metrics.viewport / 2
        if abs(offset) <= metrics.crestWidth / 2 + metrics.pitch * 0.3 {
            open(item)
            return
        }
        let steps = max(1, Int(((abs(offset) - metrics.spread / 2) / metrics.pitch).rounded()))
        let target = crest + (offset < 0 ? -steps : steps)
        guard (0..<ring.slotCount).contains(target) else { return }
        withAnimation(Motion.animation(.smooth(duration: 0.5), reduced: reduced)) {
            self.crest = target
        }
    }
}

/// Which book stands in which slot. The featured books run as a ring around the home slot,
/// where the most recently read one starts, so there are books on both sides of the crest. With
/// fewer books than the featured count the ring repeats them, so the shelf still looks full.
struct ShelfRing {
    // Spec §6.2's default; the setting for it comes with the shelf filter.
    static let featuredCount = 30

    let books: [BookListItem]
    let slotCount: Int
    let home: Int
    let lastReadId: UUID?

    init(_ all: [BookListItem]) {
        books = Array(all.prefix(Self.featuredCount))
        slotCount = books.count > 1 ? max(Self.featuredCount, books.count) : books.count
        home = slotCount / 2
        lastReadId = all
            .compactMap { item in item.progress.map { (item.id, $0.updatedAt) } }
            .max { $0.1 < $1.1 }?.0
    }

    var ids: [UUID] { books.map(\.id) }

    func index(at slot: Int) -> Int {
        let n = max(books.count, 1)
        return ((slot - home) % n + n) % n
    }

    func item(at slot: Int) -> BookListItem? {
        books.isEmpty ? nil : books[index(at: slot)]
    }
}

/// The shelf board the books stand on: its top running back behind them, a front edge, and a
/// soft falloff below.
private struct ShelfBoard: View {
    let metrics: ShelfMetrics

    var body: some View {
        let back = (metrics.coverWidth * ShelfMetrics.depthY).rounded()
        VStack(spacing: 0) {
            Tokens.line.opacity(0.4).frame(height: back)
            Tokens.line.frame(height: 1)
            LinearGradient(colors: [Tokens.line.opacity(0.5), Tokens.line.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
        }
        .padding(.top, metrics.baseline - back)
        .frame(height: metrics.stageHeight, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The crest book's title, author and reading status, which change with the crest.
private struct CrestCaption: View {
    let item: BookListItem
    let open: () -> Void

    @Environment(\.motionReduced) private var reduced

    var body: some View {
        Button(action: open) {
            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    // Holds two title lines open, so the list below doesn't jump as titles change.
                    lines(title: "\n", detail: Text(verbatim: " "))
                        .hidden()
                    lines(title: item.book.title, detail: detail)
                        .id(item.id)
                        .transition(transition)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NorthEastArrow()
                    .stroke(Tokens.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 13)
                    .padding(.bottom, 4)
            }
            .contentShape(Rectangle())
            .animation(Motion.animation(Motion.reveal, reduced: reduced), value: item.id)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func lines(title: String, detail: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.title2.bold())
                .foregroundStyle(Tokens.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            detail
                .font(.subheadline)
                .foregroundStyle(Tokens.inkSecondary)
                .lineLimit(1)
        }
    }

    private var detail: some View {
        HStack(spacing: 0) {
            if let author = item.book.author, !author.isEmpty {
                Text(verbatim: author)
                Text(verbatim: " · ")
            }
            ReadingStatusText(state: ReadingState(item), compact: false)
        }
    }

    private var transition: AnyTransition {
        reduced ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
}

/// The "go to it" arrow beside the crest's title.
private struct NorthEastArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.7))
        return path
    }
}
