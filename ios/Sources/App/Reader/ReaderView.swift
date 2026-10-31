import ShioriLibrary
import SwiftUI

/// One continuous vertical scroll through the book in the reader's own type and paper, under
/// the floating chrome a centre tap shows.
struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionReduced) private var reduced
    @Environment(\.locale) private var locale
    let book: Book
    let showContents: Bool

    @State private var reader: ReaderModel?
    @State private var openFailed = false
    @State private var position = ScrollPosition(idType: ParagraphAnchor.self)
    @State private var showsChrome = false
    @State private var sheet: ReaderSheet?
    @State private var viewport: CGRect = .zero
    @State private var safeArea = EdgeInsets()
    @State private var footerHeight: CGFloat = 0

    /// Closes by setting `model.openBook = nil`.
    init(book: Book, showContents: Bool = false) {
        self.book = book
        self.showContents = showContents
    }

    var body: some View {
        let preferences = model.readerPreferences
        let theme = preferences.theme
        ZStack {
            if let reader {
                pages(reader)
                edgeFades(preferences)
                if preferences.showsInfoFooter { footer(reader) }
            } else if openFailed {
                failure(theme)
            } else {
                ProgressView()
                    .tint(theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paper.ignoresSafeArea())
        .overlay {
            if showsChrome, let reader {
                chrome(reader)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
        .statusBarHidden(!(showsChrome || openFailed))
        .preferredColorScheme(theme.colorScheme)
        .sheet(item: $sheet) { kind in
            switch kind {
            case .contents:
                if let reader {
                    ContentsSheet(chapters: reader.chapters, current: reader.currentChapter) { jump(to: $0) }
                }
            case .appearance:
                AppearanceSheet()
                    .environment(model)
                    .presentationDetents([.medium, .large])
                    // Undimmed and scrollable at medium, so every change shows on the page above.
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
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
        let margins = TypographyAttributes.margins(model.readerPreferences.typography)
        return ScrollView {
            ReaderColumn(reader: reader, preferences: model.readerPreferences)
        }
        // A paragraph scrolled to the top comes to rest below the top margin.
        .safeAreaPadding(.top, margins.top)
        .safeAreaPadding(.bottom, margins.bottom)
        .scrollPosition($position, anchor: .top)
        // One signal only: a second one disagrees with it at chapter breaks and flips the
        // current chapter back and forth.
        .onChange(of: position.viewID(type: ParagraphAnchor.self)) { _, anchor in
            if let anchor { reader.visibleAnchorChanged(anchor) }
        }
        .onChange(of: model.readerPreferences.typography) { keepPlace(in: reader) }
        .onChange(of: viewport.width) { keepPlace(in: reader) }
        .onScrollPhaseChange { _, phase in
            reader.scrollPhaseChanged(isScrolling: phase != .idle)
            if phase == .interacting, showsChrome { setChrome(false) }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
        .onTapGesture(coordinateSpace: .global) { location in tap(at: location) }
        .accessibilityAction(.magicTap) { setChrome(!showsChrome) }
        .accessibilityAction(named: Text("Contents")) { sheet = .contents }
        .accessibilityAction(named: Text("Appearance")) { openAppearance() }
        .accessibilityAction(.escape) { close() }
    }

    private func chrome(_ reader: ReaderModel) -> some View {
        ReaderChrome(
            state: ReaderChromeState(bookTitle: book.title, chapterTitle: chapterTitle(reader),
                                     chapterIndex: reader.currentChapter, chapterCount: reader.chapters.count),
            onBack: close,
            onJump: { jump(to: $0) },
            onContents: { sheet = .contents },
            onAppearance: openAppearance,
            onDayNight: toggleDayNight)
    }

    private func footer(_ reader: ReaderModel) -> some View {
        let margins = TypographyAttributes.margins(model.readerPreferences.typography)
        return ReaderInfoFooter(chapterTitle: chapterTitle(reader), chapterIndex: reader.currentChapter,
                                chapterCount: reader.chapters.count)
            .foregroundStyle(model.readerPreferences.theme.inkSecondary)
            .padding(.leading, margins.left)
            .padding(.trailing, margins.right)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            .padding(.bottom, footerLift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .opacity(showsChrome ? 0 : 1)
            .allowsHitTesting(false)
            // The chrome reads out the same place; here it would only interrupt the text.
            .accessibilityHidden(true)
    }

    /// The footer sits in the home indicator's band, just above the indicator.
    private var footerLift: CGFloat { max(safeArea.bottom - 14, 6) }

    /// Paper over the safe areas, fading out across the margins, so text scrolling off the
    /// page leaves softly and never runs under the island or the footer.
    private func edgeFades(_ preferences: ReaderPreferences) -> some View {
        let margins = TypographyAttributes.margins(preferences.typography)
        let paper = preferences.theme.paper
        let bottom = preferences.showsInfoFooter
            ? max(safeArea.bottom, footerLift + footerHeight + 4)
            : safeArea.bottom
        return VStack(spacing: 0) {
            Self.fade(paper, solid: safeArea.top, fading: margins.top, from: .top)
            Spacer(minLength: 0)
            Self.fade(paper, solid: bottom, fading: margins.bottom, from: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func fade(_ paper: Color, solid: CGFloat, fading: CGFloat, from edge: VerticalEdge) -> some View {
        let height = max(solid + fading, 0)
        let stops: [Gradient.Stop] = [
            .init(color: paper, location: 0),
            .init(color: paper, location: height > 0 ? solid / height : 1),
            .init(color: paper.opacity(0), location: 1),
        ]
        return LinearGradient(stops: stops, startPoint: edge == .top ? .top : .bottom,
                              endPoint: edge == .top ? .bottom : .top)
            .frame(height: height)
    }

    private func failure(_ theme: ReaderTheme) -> some View {
        Text("Couldn't open this book.")
            .foregroundStyle(theme.inkSecondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                Button(action: close) {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 8)
            }
    }

    private func chapterTitle(_ reader: ReaderModel) -> String {
        let index = reader.currentChapter
        guard reader.chapters.indices.contains(index) else { return "" }
        return ContentsSheet.titleString(of: reader.chapters[index], at: index, locale: locale)
    }

    private func open() async {
        guard reader == nil, !openFailed else { return }
        do {
            let reader = try await ReaderModel.open(book: book, database: model.database, paths: model.paths)
            let jump = await reader.start()
            // Set before the scroll view exists, so its first layout is already at the paragraph.
            position.scrollTo(id: reader.initialAnchor, anchor: .top)
            self.reader = reader
            if let jump { await land(jump, in: reader) }
        } catch {
            openFailed = true
            return
        }
        #if DEBUG
        if DemoLaunch.showsChrome { showsChrome = true }
        #endif
        if showContents {
            // A sheet asked for while the full-screen cover is still sliding in is dropped.
            try? await Task.sleep(for: .milliseconds(600))
            sheet = .contents
        }
        #if DEBUG
        if DemoLaunch.showsAppearance {
            try? await Task.sleep(for: .milliseconds(600))
            sheet = .appearance
        }
        if let chapter = DemoLaunch.jumpTo {
            try? await Task.sleep(for: .milliseconds(600))
            jump(to: chapter)
        }
        #endif
    }

    private func jump(to chapter: Int) {
        guard let reader else { return }
        Task {
            guard let jump = await reader.show(chapter: chapter) else { return }
            position.scrollTo(id: jump.anchor, anchor: .top)
            await land(jump, in: reader)
        }
    }

    /// Puts the paragraph that was at the top back there once the new type has laid out.
    private func keepPlace(in reader: ReaderModel) {
        guard let hold = reader.holdPlace() else { return }
        position.scrollTo(id: hold.anchor, anchor: .top)
        Task { await land(hold, in: reader) }
    }

    /// `scrollTo` only takes effect at the next layout, so tracking resumes a few frames later.
    private func land(_ jump: ReaderJump, in reader: ReaderModel) async {
        try? await Task.sleep(for: .milliseconds(300))
        reader.finishJump(jump)
    }

    private func close() {
        reader?.saveNow()
        model.openBook = nil
    }

    private func openAppearance() {
        // The chrome would cover the page the sheet's changes show on.
        setChrome(false)
        sheet = .appearance
    }

    private func toggleDayNight() {
        withAnimation(Motion.animation(.easeInOut(duration: 0.35), reduced: reduced)) {
            model.readerPreferences.toggleDayNight()
        }
    }

    private func tap(at point: CGPoint) {
        // Only the Aa sheet lets taps through to the page; one closes it like a tap outside.
        if sheet != nil {
            sheet = nil
            return
        }
        if showsChrome {
            setChrome(false)
            return
        }
        let centre = viewport.insetBy(dx: viewport.width * 0.25, dy: viewport.height * 0.2)
        if centre.contains(point) { setChrome(true) }
    }

    private func setChrome(_ visible: Bool) {
        withAnimation(Motion.animation(.spring(duration: 0.3, bounce: 0.15), reduced: reduced)) {
            showsChrome = visible
        }
    }
}

private enum ReaderSheet: Identifiable {
    case contents, appearance

    var id: Self { self }
}
