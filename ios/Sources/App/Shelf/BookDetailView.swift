import os
import ShioriCore
import ShioriLibrary
import SwiftUI

/// A book's detail page (spec §6.5), pushed in the Shelf tab's stack. The facts, the reading
/// card and every chapter share one scroll, under a floating Start reading / Continue capsule.
struct BookDetailView: View {
    let bookId: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The book as last seen, so the page still draws while it pops after a removal.
    @State private var lastSeen: BookListItem?
    @State private var chapters: [Chapter] = []
    @State private var reading = ReadingFacts()
    @State private var reversed = false
    @State private var pageWidth: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var scrolledPastHeader = false
    @State private var authorShown: String?
    @State private var viewingCover = false
    @State private var coverFrame = FrameBox()

    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "detail")
    /// 2026-10-31 in every language, like an archive date stamp.
    private static let importDate = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

    init(bookId: UUID) {
        self.bookId = bookId
    }

    var body: some View {
        let live = model.books.first { $0.id == bookId }
        Group {
            if let item = live ?? lastSeen {
                page(item)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $authorShown) { AuthorBooksView(author: $0) }
        .onChange(of: live, initial: true) { _, item in
            if let item {
                lastSeen = item
            } else if lastSeen != nil {
                dismiss()
            }
        }
    }

    private func page(_ item: BookListItem) -> some View {
        let book = item.book
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(book)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                ReadingCard(item: item, facts: reading)
                    .staggeredReveal(4)
                    .padding(.top, 32)
                if book.format != .pdf {
                    HStack(alignment: .bottom, spacing: 16) {
                        SectionLabel(code: "02 / CONTENTS / \(book.chapterCount)", title: "Contents")
                        OrderToggle(reversed: $reversed)
                    }
                    .staggeredReveal(5)
                    .padding(.top, 40)
                    .padding(.bottom, 8)
                    if !chapters.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ContentsSections(chapters: chapters, current: current(item), query: "",
                                             reversed: reversed) { index in
                                open(book, at: index)
                            }
                            .currentLabel("Last read")
                        }
                        .staggeredReveal(6)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > headerHeight * 0.6
        } action: { _, past in
            scrolledPastHeader = past
        }
        .safeAreaBar(edge: .top) {
            ShelfPageBar(code: scrolledPastHeader ? BookSerial.make(book.id) : "01 / SHELF / DETAIL",
                         title: scrolledPastHeader ? Text(verbatim: book.title) : Text("Book details"),
                         headingID: scrolledPastHeader)
        }
        .safeAreaBar(edge: .bottom) {
            StartCapsule(resumes: item.progress != nil) { open(book, at: nil) }
        }
        .fullScreenCover(isPresented: $viewingCover) {
            CoverViewer(book: book, source: coverFrame.rect, onClose: { setViewingCover(false) })
                .environment(model)
                .presentationBackground(.clear)
        }
        .task(id: book) { await loadChapters(book) }
        .task(id: item.progress) { await loadReading(item) }
    }

    private func header(_ book: Book) -> some View {
        let coverWidth = min(max((pageWidth - 40) * 0.34, 96), 220)
        return HStack(alignment: .top, spacing: 18) {
            Button { setViewingCover(true) } label: {
                BookCover(book: book, width: coverWidth)
            }
            .buttonStyle(PressableButtonStyle())
            // The viewer's copy stands in for it while open, so the cover seems to lift off the page.
            .opacity(viewingCover ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { coverFrame.rect = $0 }
            .accessibilityHidden(true)
            .staggeredReveal(0)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: book.title)
                    .font(.title.weight(.heavy))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(5)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .staggeredReveal(1)
                if let name = book.author, !name.isEmpty {
                    authorLink(name)
                        .padding(.top, 12)
                        .staggeredReveal(2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if book.format == .pdf {
                        Text(verbatim: "PDF")
                    } else {
                        Text("\(book.chapterCount) chapters")
                    }
                    Text("Imported \(book.addedAt.formatted(Self.importDate))")
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Tokens.inkSecondary)
                .padding(.top, 14)
                .staggeredReveal(3)
                SerialStamp(bookId: book.id)
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func authorLink(_ name: String) -> some View {
        Button { authorShown = name } label: {
            HStack(spacing: 4) {
                Text(verbatim: name)
                    .font(.headline)
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                IconView(.forward, size: 14)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Books by \(name)"))
    }

    private func current(_ item: BookListItem) -> Int? {
        item.progress.map { ReadingPosition.chapterIndex(for: $0, in: chapters) }
    }

    private func open(_ book: Book, at chapter: Int?) {
        model.openChapter = chapter
        model.openBook = book
    }

    /// Without the system's slide, so the viewer's own flight out of the cover is the motion.
    private func setViewingCover(_ shown: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { viewingCover = shown }
    }

    private func loadChapters(_ book: Book) async {
        guard book.format != .pdf else { return }
        let database = model.database
        let bookId = book.id
        let result = await Task.detached(priority: .userInitiated) {
            Result { try database.chapters(bookId: bookId) }
        }.value
        switch result {
        case .success(let loaded): chapters = loaded
        case .failure(let error): Self.log.error("loading the contents failed: \(error)")
        }
    }

    private func loadReading(_ item: BookListItem) async {
        let database = model.database
        let bookId = item.id
        let index = item.book.format == .pdf ? nil : item.progress?.chapterIndex
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                ReadingFacts(chapter: try index.flatMap { try database.chapter(bookId: bookId, index: $0) },
                             seconds: try database.readingSeconds(bookId: bookId))
            }
        }.value
        switch result {
        case .success(let facts): reading = facts
        case .failure(let error): Self.log.error("loading the reading card failed: \(error)")
        }
    }
}

private struct ReadingFacts: Equatable, Sendable {
    var chapter: Chapter?
    var seconds = 0
}

/// Holds the cover's on-screen frame without redrawing the page on every scroll step.
private final class FrameBox {
    var rect: CGRect = .zero
}

/// The floating top row of a page pushed on the Shelf: a round glass back button and a
/// centred two-line heading, which rises into place whenever `headingID` changes.
struct ShelfPageBar: View {
    let code: String?
    let title: Text?
    let headingID: Bool

    @Environment(\.motionReduced) private var reduced

    init(code: String?, title: Text?, headingID: Bool) {
        self.code = code
        self.title = title
        self.headingID = headingID
    }

    var body: some View {
        HStack(spacing: 10) {
            GlassBackButton()
            ZStack {
                if code != nil || title != nil {
                    VStack(spacing: 2) {
                        if let code {
                            Text(verbatim: code)
                                .font(.system(.caption2, design: .monospaced))
                                .tracking(1.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Tokens.inkSecondary)
                                .accessibilityHidden(true)
                        }
                        if let title {
                            title
                                .font(.headline)
                                .foregroundStyle(Tokens.ink)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    .lineLimit(1)
                    .id(headingID)
                    .transition(reduced ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(Motion.animation(Motion.reveal, reduced: reduced), value: headingID)
            // Balances the back button so the heading stays centred.
            Color.clear
                .frame(width: GlassBackButton.size, height: GlassBackButton.size)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

struct GlassBackButton: View {
    static let size: CGFloat = 46

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            IconView(.back, size: 22)
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Tokens.paper.opacity(0.35)).interactive(), in: .circle)
        .accessibilityLabel(Text("Back"))
    }
}

/// "Reading: <chapter>" with the whole-book line and the reading time, framed by corner
/// brackets like a photo mount in an archive.
private struct ReadingCard: View {
    let item: BookListItem
    let facts: ReadingFacts

    @Environment(\.locale) private var locale
    @Environment(\.motionReduced) private var reduced
    @State private var framed = false

    var body: some View {
        let fraction = item.progress?.fraction ?? 0
        ArchiveCard {
            VStack(alignment: .leading, spacing: 14) {
                headline
                    .font(.title3.bold())
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 14) {
                    WholeBookLine(fraction: fraction)
                    Text("Whole book \(fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale)))")
                        .monospacedDigit()
                        .fixedSize()
                }
                if facts.seconds > 0 {
                    Text("Reading time \(duration)")
                        .monospacedDigit()
                }
            }
            .font(.footnote)
            .foregroundStyle(Tokens.inkSecondary)
            .padding(20)
        }
        .overlay {
            CornerBrackets(arm: 14)
                .stroke(Tokens.ink, lineWidth: 1.5)
                .padding(-5)
                .scaleEffect(framed || reduced ? 1 : 1.05)
                .opacity(framed ? 1 : 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            withAnimation(Motion.animation(Motion.reveal, reduced: reduced).delay(reduced ? 0 : 0.3)) {
                framed = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var headline: some View {
        if let progress = item.progress {
            Text("Reading: \(place(progress))")
        } else {
            Text("Unread")
        }
    }

    private func place(_ progress: ShioriLibrary.Progress) -> String {
        // A PDF keeps its page in chapterIndex.
        if item.book.format == .pdf { return localized("Page \(progress.chapterIndex + 1)") }
        if let chapter = facts.chapter, chapter.index == progress.chapterIndex {
            return ContentsSheet.titleString(of: chapter, at: chapter.index, locale: locale)
        }
        return localized("Chapter \(progress.chapterIndex + 1)")
    }

    private var duration: String {
        let minutes = max(facts.seconds, 60) / 60
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }

    /// In the in-app language rather than the phone's, which a String built here would get.
    private func localized(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}

private struct WholeBookLine: View {
    let fraction: Double

    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced
    @State private var drawn = 0.0

    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 2)
            .overlay {
                Rectangle()
                    .fill(accent)
                    .scaleEffect(x: drawn, y: 1, anchor: .leading)
            }
            .onAppear {
                guard !reduced else {
                    drawn = Self.clamped(fraction)
                    return
                }
                withAnimation(.easeOut(duration: 0.8).delay(0.4)) { drawn = Self.clamped(fraction) }
            }
            .onChange(of: fraction) { _, new in
                withAnimation(reduced ? nil : Motion.reveal) { drawn = Self.clamped(new) }
            }
            .accessibilityHidden(true)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct CornerBrackets: Shape {
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}

/// The book's SH- serial in a small box that lands like a rubber stamp.
private struct SerialStamp: View {
    let bookId: UUID

    @Environment(\.motionReduced) private var reduced
    @State private var landed = false

    var body: some View {
        Text(verbatim: BookSerial.make(bookId))
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(Tokens.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay { Rectangle().strokeBorder(Tokens.ink, lineWidth: 1.2) }
            .rotationEffect(.degrees(landed || reduced ? -2 : -9))
            .scaleEffect(landed || reduced ? 1 : 1.6)
            .opacity(landed ? 0.88 : 0)
            .onAppear {
                let thump = Animation.spring(response: 0.3, dampingFraction: 0.6)
                withAnimation(Motion.animation(thump, reduced: reduced).delay(reduced ? 0.1 : 0.45)) {
                    landed = true
                }
            }
            // Archive flavour, not information: VoiceOver would read it digit by digit.
            .accessibilityHidden(true)
    }
}

private struct OrderToggle: View {
    @Binding var reversed: Bool

    @Environment(\.motionReduced) private var reduced

    var body: some View {
        // Not in withAnimation: that would animate thousands of rows changing places.
        Button { reversed.toggle() } label: {
            ZStack {
                if reversed {
                    Text("Reversed")
                        .transition(reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.7)))
                } else {
                    Text("In order")
                        .transition(reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Tokens.ink)
            .animation(Motion.animation(Motion.press, reduced: reduced), value: reversed)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .background(Tokens.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(Tokens.line, lineWidth: 0.5) }
            .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .shioriHaptic(.selection, trigger: reversed)
    }
}

/// The accent-filled glass capsule that floats over the contents.
private struct StartCapsule: View {
    let resumes: Bool
    let action: () -> Void

    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced
    @State private var risen = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // IconView draws in ink; the mask recolours it to sit on the accent.
                Tokens.paper
                    .frame(width: 18, height: 18)
                    .mask { IconView(.play, size: 18) }
                    .accessibilityHidden(true)
                if resumes {
                    Text("Continue")
                } else {
                    Text("Start reading")
                }
            }
            .font(.headline)
            .foregroundStyle(Tokens.paper)
            .padding(.horizontal, 32)
            .frame(minWidth: 200, minHeight: 54)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(accent).interactive(), in: .capsule)
        .offset(y: risen || reduced ? 0 : 40)
        .opacity(risen ? 1 : 0)
        .padding(.bottom, 4)
        .onAppear {
            withAnimation(Motion.animation(Motion.reveal, reduced: reduced).delay(reduced ? 0 : 0.2)) {
                risen = true
            }
        }
    }
}
