import ShioriLibrary
import SwiftUI

/// One continuous vertical scroll through the book. Placeholder typography until M4a and a
/// plain top bar until M4b's glass chrome.
struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let book: Book
    let showContents: Bool

    @State private var reader: ReaderModel?
    @State private var openFailed = false
    @State private var position = ScrollPosition(idType: ParagraphAnchor.self)
    @State private var showsBar = false
    @State private var showsContents = false
    @State private var viewport: CGRect = .zero

    /// Closes by setting `model.openBook = nil`.
    init(book: Book, showContents: Bool = false) {
        self.book = book
        self.showContents = showContents
    }

    var body: some View {
        ZStack {
            if let reader {
                pages(reader)
            } else if openFailed {
                Text("Couldn't open this book.")
                    .foregroundStyle(Tokens.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
            } else {
                ProgressView()
                    .tint(Tokens.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.paper.ignoresSafeArea())
        .overlay(alignment: .top) {
            if showsBar || openFailed {
                topBar
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .statusBarHidden(!(showsBar || openFailed))
        .sheet(isPresented: $showsContents) {
            if let reader {
                ContentsSheet(chapters: reader.chapters, current: reader.currentChapter) { jump(to: $0) }
            }
        }
        .task { await open() }
        .onDisappear { reader?.saveNow() }
        .onChange(of: scenePhase) { _, phase in
            // The app switcher only makes the scene inactive, and a swipe-kill from there
            // never reaches the background, so inactive has to save too.
            if phase != .active { reader?.saveNow() }
        }
    }

    private func pages(_ reader: ReaderModel) -> some View {
        ScrollView {
            ReaderColumn(reader: reader)
        }
        .scrollPosition($position, anchor: .top)
        .onChange(of: position.viewID(type: ParagraphAnchor.self)) { _, anchor in
            if let anchor { reader.visibleAnchorChanged(anchor) }
        }
        // A second, independent signal, in case `viewID` isn't updated by user scrolls.
        .onScrollTargetVisibilityChange(idType: ParagraphAnchor.self, threshold: 0.1) { visible in
            let top = visible.min { ($0.chapter, $0.block) < ($1.chapter, $1.block) }
            if let top { reader.visibleAnchorChanged(top) }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting, showsBar { setBar(false) }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
        .onTapGesture(coordinateSpace: .global) { location in tap(at: location) }
        .accessibilityAction(.magicTap) { setBar(!showsBar) }
        .accessibilityAction(named: Text("Contents")) { showsContents = true }
        .accessibilityAction(.escape) { close() }
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button {
                close()
            } label: {
                Label("Back", systemImage: "chevron.backward")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            Text(verbatim: book.title)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button {
                showsContents = true
            } label: {
                Label("Contents", systemImage: "list.bullet")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .disabled(reader == nil)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Tokens.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Tokens.line.frame(height: 1 / displayScale)
        }
    }

    private func open() async {
        guard reader == nil, !openFailed else { return }
        do {
            let reader = try await ReaderModel.open(book: book, database: model.database, paths: model.paths)
            await reader.start()
            // Set before the scroll view exists, so its first layout is already at the paragraph.
            position.scrollTo(id: reader.initialAnchor, anchor: .top)
            self.reader = reader
        } catch {
            openFailed = true
            return
        }
        if showContents {
            // A sheet asked for while the full-screen cover is still sliding in is dropped.
            try? await Task.sleep(for: .milliseconds(600))
            showsContents = true
        }
    }

    private func jump(to chapter: Int) {
        guard let reader else { return }
        Task {
            if await reader.show(chapter: chapter) {
                position.scrollTo(id: ParagraphAnchor(chapter: chapter, block: 0), anchor: .top)
            }
        }
    }

    private func close() {
        reader?.saveNow()
        model.openBook = nil
    }

    private func tap(at point: CGPoint) {
        if showsBar {
            setBar(false)
            return
        }
        let centre = viewport.insetBy(dx: viewport.width * 0.25, dy: viewport.height * 0.2)
        if centre.contains(point) { setBar(true) }
    }

    private func setBar(_ visible: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.15)) {
            showsBar = visible
        }
    }
}

/// Reads only `reader.rows`, so the scroll position changing doesn't re-render the text.
private struct ReaderColumn: View {
    let reader: ReaderModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(reader.rows) { row in
                ReaderRowView(row: row)
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 24)
        .padding(.bottom, 64)
    }
}

private struct ReaderRowView: View {
    let row: ReaderRow

    var body: some View {
        content
            .padding(.bottom, row.endsChapter ? 32 : 0)
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .title(let text):
            title(text)
        case .heading(let text, let level):
            Text(verbatim: text)
                .font(.system(size: level <= 2 ? 22 : 20, weight: .semibold, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(Tokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(verbatim: text)
                .font(.system(size: 19, design: .serif))
                .lineSpacing(8)
                .foregroundStyle(Tokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
        case .image:
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(Tokens.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 96)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.line))
                .padding(.bottom, 12)
                .accessibilityHidden(true)
        case .unreadable(let chapterTitle):
            VStack(alignment: .leading, spacing: 0) {
                if !chapterTitle.isEmpty { title(chapterTitle) }
                Text("Couldn't open this chapter.")
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .empty:
            Color.clear.frame(height: 1)
        }
    }

    private func title(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 26, weight: .bold, design: .serif))
            .lineSpacing(6)
            .foregroundStyle(Tokens.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .accessibilityAddTraits(.isHeader)
    }
}
