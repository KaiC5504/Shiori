import ShioriCore
import ShioriLibrary
import SwiftUI

/// The book in the reader's own type and paper, under the floating chrome a centre tap shows:
/// one continuous vertical scroll, or pages (`PagedReaderView`), as `readerPreferences.layout`
/// says. Taps at the sides move a screen or turn a page.
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
    /// The pages' place. The paged view writes it on every turn; writing it here is a jump.
    @State private var pagedPosition = ReaderPosition(chapter: 0, offset: 0)
    /// The layout on screen, which follows the preference once the place has been handed over.
    @State private var shownLayout = ReaderLayout.scroll
    @State private var pageNumber: PagedPageNumber?
    @State private var showsChrome = false
    @State private var sheet: ReaderSheet?
    @State private var viewport: CGRect = .zero
    @State private var safeArea = EdgeInsets()
    @State private var footerHeight: CGFloat = 0
    @State private var tracker: ReadingSessionTracker?
    @State private var viewing: ImageViewerRequest?
    @State private var scroll = ScrollTracking()
    @State private var turns = 0

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
                switch shownLayout {
                case .scroll:
                    pages(reader)
                    edgeFades(preferences)
                case .paged:
                    paged(reader)
                }
                veil(theme.paper)
                if preferences.showsInfoFooter { footer(reader) }
                BrightnessEdge(preferences: preferences, onTap: { tap(at: $0) }, onSwipe: { forward in
                    if shownLayout == .paged, !showsChrome, sheet == nil { step(forward: forward) }
                })
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
        .statusBarHidden(preferences.hidesStatusBar && !(showsChrome || openFailed))
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
        .fullScreenCover(item: $viewing) { request in
            ImageViewer(request: request)
                .environment(\.readerModel, reader)
        }
        .environment(\.readerModel, reader)
        .environment(\.openReaderImage) { viewing = $0 }
        .task { await open() }
        .onAppear {
            if scenePhase == .active { ReaderScreen.hold(preferences) }
        }
        .onDisappear {
            reader?.saveNow()
            // A full-screen cover hides the reader too, and looking at a picture is still reading.
            guard viewing == nil else { return }
            tracker?.stop()
            ReaderScreen.release()
        }
        .onChange(of: scenePhase) { _, phase in
            // The app switcher only makes the scene inactive, and a swipe-kill from there
            // never reaches the background, so inactive has to save too.
            if phase != .active {
                reader?.saveNow()
                tracker?.pause()
                ReaderScreen.release()
            } else {
                ReaderScreen.hold(model.readerPreferences)
                if let reader { tracker?.ping(chapterIndex: reader.currentChapter) }
            }
        }
        .onChange(of: preferences.brightness) { holdScreen() }
        .onChange(of: preferences.keepsScreenAwake) { holdScreen() }
        .onChange(of: preferences.layout) { _, layout in switchLayout(to: layout) }
        .shioriHaptic(.selection, trigger: turns)
    }

    private func holdScreen() {
        if scenePhase == .active { ReaderScreen.hold(model.readerPreferences) }
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
            if let anchor {
                reader.visibleAnchorChanged(anchor)
                tracker?.ping(chapterIndex: anchor.chapter)
            }
        }
        .onChange(of: model.readerPreferences.typography) { keepPlace(in: reader) }
        .onChange(of: viewport.width) { keepPlace(in: reader) }
        .onScrollPhaseChange { _, phase in
            scroll.phase = phase
            if phase == .interacting { scroll.unanchored = false }
            // A tap's scroll counts until it is pinned to a paragraph again (see `settleTurn`).
            reader.scrollPhaseChanged(isScrolling: phase != .idle || scroll.landing != nil || scroll.unanchored)
            if phase == .interacting, showsChrome { setChrome(false) }
        }
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in scroll.geometry = geometry }
        // Not a second tracking signal: only read once, to pin a tap's scroll.
        .onScrollTargetVisibilityChange(idType: ParagraphAnchor.self, threshold: 0.01) { scroll.visible = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
        .onTapGesture(coordinateSpace: .global) { location in tap(at: location) }
        .accessibilityAction(.magicTap) { setChrome(!showsChrome) }
        .accessibilityAction(named: Text("Contents")) { sheet = .contents }
        .accessibilityAction(named: Text("Appearance")) { openAppearance() }
        .accessibilityAction(.escape) { close() }
    }

    /// The pages turn on their own taps and swipes and write `pagedPosition`; saving and the
    /// session follow each turn.
    private func paged(_ reader: ReaderModel) -> some View {
        PagedReaderView(source: reader, position: $pagedPosition,
                        onMenu: { showMenu(reader) }, onTurn: { pageTurned(reader) })
            .safeAreaPadding(.bottom, bottomCover - safeArea.bottom)
            .onPreferenceChange(PagedPageNumberKey.self) { number in pageNumber = number }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
            .overlay {
                // With the chrome or the Aa sheet up, a tap on the page closes them instead of
                // turning, and a swipe closes the chrome as scrolling does.
                if showsChrome || sheet != nil {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture(coordinateSpace: .global) { location in tap(at: location) }
                        .gesture(DragGesture(minimumDistance: 12).onEnded { _ in
                            if showsChrome { setChrome(false) }
                        })
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
            .accessibilityAction(.magicTap) { setChrome(!showsChrome) }
            .accessibilityAction(named: Text("Contents")) { sheet = .contents }
            .accessibilityAction(named: Text("Appearance")) { openAppearance() }
            .accessibilityAction(.escape) { close() }
    }

    /// Paper over a layout switch, clearing as the new layout shows, so neither has to animate.
    private func veil(_ paper: Color) -> some View {
        paper
            .ignoresSafeArea()
            .keyframeAnimator(initialValue: 0.0, trigger: shownLayout) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(1.0)
                    LinearKeyframe(0.0, duration: reduced ? 0.15 : 0.3)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
        .environment(\.readerChapterTitle) { [chapters = reader.chapters] index in
            chapters.indices.contains(index) ? chapters[index].title : nil
        }
    }

    private func footer(_ reader: ReaderModel) -> some View {
        let margins = TypographyAttributes.margins(model.readerPreferences.typography)
        // The page in the chapter while paged (spec §7.7), the chapter in the book while scrolling.
        let place = shownLayout == .paged
            ? (pageNumber?.page ?? 0, pageNumber?.pages ?? 0)
            : (reader.currentChapter + 1, reader.chapters.count)
        return ReaderInfoFooter(chapterTitle: chapterTitle(reader), place: place.0, count: place.1,
                                showsBattery: model.readerPreferences.showsBattery)
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

    /// How far the solid paper reaches up from the bottom edge: the home indicator's band, or
    /// the footer where it stands taller.
    private var bottomCover: CGFloat {
        model.readerPreferences.showsInfoFooter ? max(safeArea.bottom, footerLift + footerHeight + 4) : safeArea.bottom
    }

    /// Paper over the safe areas, fading out across the margins, so text scrolling off the
    /// page leaves softly and never runs under the island or the footer.
    private func edgeFades(_ preferences: ReaderPreferences) -> some View {
        let margins = TypographyAttributes.margins(preferences.typography)
        let paper = preferences.theme.paper
        return VStack(spacing: 0) {
            Self.fade(paper, solid: safeArea.top, fading: margins.top, from: .top)
            Spacer(minLength: 0)
            Self.fade(paper, solid: bottomCover, fading: margins.bottom, from: .bottom)
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
        // A downloaded Apple font is only registered for the running app; without this the
        // first layout would fall back to the system font.
        await FontDownloads.shared.activate(model.readerPreferences.typography.fontFamily)
        do {
            let reader = try await ReaderModel.open(book: book, database: model.database, paths: model.paths,
                                                    preferences: model.readerPreferences)
            let jump = await reader.start()
            // Set before the scroll view exists, so its first layout is already at the paragraph.
            position.scrollTo(id: reader.initialAnchor, anchor: .top)
            let layout = model.readerPreferences.layout
            if layout == .paged {
                // The saved character rather than its paragraph, so the same page comes back.
                pagedPosition = reader.initialPlace
                reader.enterPaged(at: reader.initialPlace)
            }
            shownLayout = layout
            self.reader = reader
            tracker = ReadingSessionTracker(database: model.database, bookId: book.id)
            // The first screen counts as reading before any scroll or tap.
            tracker?.ping(chapterIndex: reader.currentChapter)
            if layout == .scroll, let jump { await land(jump, in: reader) }
        } catch {
            openFailed = true
            return
        }
        #if DEBUG
        if DemoLaunch.showsChrome { showsChrome = true }
        #endif
        if let chapter = model.openChapter {
            model.openChapter = nil
            jump(to: chapter)
        }
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
        if shownLayout == .paged {
            guard reader.chapters.indices.contains(chapter) else { return }
            let place = ReaderPosition(chapter: chapter, offset: 0)
            pagedPosition = place
            reader.pagedMoved(to: place, jumped: true)
            tracker?.ping(chapterIndex: chapter)
            return
        }
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
        // A jump scrolls to a paragraph, which anchors the position again.
        if scroll.unanchored {
            scroll.unanchored = false
            reader.scrollPhaseChanged(isScrolling: scroll.phase != .idle)
        }
        reader.finishJump(jump)
        // A short drag that came to rest during the hold won't move viewID again, so catch it up.
        if let anchor = position.viewID(type: ParagraphAnchor.self) { reader.visibleAnchorChanged(anchor) }
    }

    private func close() {
        reader?.saveNow()
        tracker?.stop()
        // Now rather than on disappear, so the brightness is back while the reader slides away.
        ReaderScreen.release()
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
        if let reader { tracker?.ping(chapterIndex: reader.currentChapter) }
        // Only the Aa sheet lets taps through to the page; one closes it like a tap outside.
        if sheet != nil {
            sheet = nil
            return
        }
        if showsChrome {
            setChrome(false)
            return
        }
        let preferences = model.readerPreferences
        let action = TapZones.action(x: point.x - viewport.minX, y: point.y - viewport.minY,
                                     width: viewport.width, height: viewport.height,
                                     layout: preferences.tapLayout, bothSidesForward: preferences.bothSidesForward)
        if shownLayout == .paged, action != .menu {
            step(forward: action == .forward)
            return
        }
        switch action {
        case .menu: setChrome(true)
        case .forward: turn(by: 1)
        case .back: turn(by: -1)
        }
    }

    private func showMenu(_ reader: ReaderModel) {
        tracker?.ping(chapterIndex: reader.currentChapter)
        setChrome(true)
    }

    /// The paged view has already written the new page into `pagedPosition`.
    private func pageTurned(_ reader: ReaderModel) {
        reader.pagedMoved(to: pagedPosition)
        tracker?.ping(chapterIndex: pagedPosition.chapter)
    }

    /// A page turn for a tap the page never sees, on the brightness strip over its left edge.
    /// It lands without the turn's motion, as a jump does.
    private func step(forward: Bool) {
        guard let reader, let place = reader.pagedNeighbour(of: pagedPosition, forward: forward) else { return }
        pagedPosition = place
        turns += 1
        reader.pagedMoved(to: place)
    }

    /// Hands the place over when the Aa sheet changes the layout: the scroll's top paragraph
    /// becomes the page holding its first character, and a page's first character the
    /// paragraph at the top of the scroll.
    private func switchLayout(to layout: ReaderLayout) {
        guard let reader else { return }
        switch layout {
        case .paged:
            guard shownLayout == .scroll else {
                // Back before the scroll had shown: the pages never left, and keep their place.
                reader.enterPaged(at: pagedPosition)
                return
            }
            scroll.landing?.cancel()
            pagedPosition = reader.switchToPaged()
            pageNumber = nil
            shownLayout = .paged
        case .scroll:
            guard shownLayout == .paged else { return }
            let place = pagedPosition
            Task {
                guard let jump = await reader.show(place: place), model.readerPreferences.layout == .scroll else {
                    return
                }
                // Fresh and at rest, as on opening: the last scroll's offsets mean nothing to this one.
                scroll = ScrollTracking()
                reader.scrollPhaseChanged(isScrolling: false)
                // Set before the scroll view exists, so its first layout is already at the paragraph.
                position.scrollTo(id: jump.anchor, anchor: .top)
                shownLayout = .scroll
                // Its first placement measures none of the paragraphs above the target, and under
                // the Aa sheet it came to rest paragraphs short. Placing it again once it has laid
                // out, as `keepPlace` does after new type, puts the paragraph at the top.
                try? await Task.sleep(for: .milliseconds(100))
                position.scrollTo(id: jump.anchor, anchor: .top)
                await land(jump, in: reader)
            }
        }
    }

    /// Moves the text a screen less one line, so the line that was last is now first. Only from
    /// rest: while a jump or hold lands, or the text is moving, the offset isn't a place yet.
    private func turn(by direction: CGFloat) {
        guard let reader, !reader.isSettling, scroll.phase == .idle, let geometry = scroll.geometry else { return }
        let insets = geometry.contentInsets
        let lineHeight = ReaderStyle(model.readerPreferences).lineHeight
        // The insets hold the safe areas and the margins; the footer can reach a little higher.
        let page = geometry.containerSize.height - insets.top - insets.bottom - (bottomCover - safeArea.bottom)
        let step = max(page - lineHeight, lineHeight)
        let top = -insets.top
        let bottom = max(top, geometry.contentSize.height + insets.bottom - geometry.containerSize.height)
        let target = min(max(geometry.contentOffset.y + direction * step, top), bottom)
        guard abs(target - geometry.contentOffset.y) > 1 else { return }
        scroll.landing?.cancel()
        reader.scrollPhaseChanged(isScrolling: true)
        if reduced {
            position.scrollTo(y: target)
        } else {
            withAnimation(.smooth(duration: 0.35)) { position.scrollTo(y: target) }
        }
        turns += 1
        scroll.unanchored = true
        scroll.landing = Task { await settleTurn(in: reader) }
    }

    /// A scroll to an offset leaves the position holding no paragraph, so nothing tracks or saves
    /// the new place, and a chapter joining above would push the text down under the reader. Once
    /// the scroll is at rest, this pins the position to the paragraph at the top again, as if the
    /// reader had scrolled there, and lets chapters join above. If the scroll view already named
    /// one, or a jump has taken over, it leaves the position alone.
    private func settleTurn(in reader: ReaderModel) async {
        try? await Task.sleep(for: .milliseconds(reduced ? 80 : 400))
        var waits = 0
        while scroll.phase != .idle, waits < 40, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            waits += 1
        }
        guard !Task.isCancelled else { return }
        scroll.landing = nil
        if !reader.isSettling, position.viewID(type: ParagraphAnchor.self) == nil, let top = scroll.topVisible {
            position.scrollTo(id: top, anchor: .top)
            // Marks the paragraph as where the reader is rather than where to scroll.
            position.isPositionedByUser = true
            // Pinning doesn't report a new viewID, so the place is handed over here to be saved.
            reader.visibleAnchorChanged(top)
            tracker?.ping(chapterIndex: top.chapter)
        }
        reader.scrollPhaseChanged(isScrolling: scroll.phase != .idle || scroll.unanchored)
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

/// What a tap needs to move the text. It is written on every scroll frame, so it is a plain
/// reference: those writes never re-render the reader.
private final class ScrollTracking {
    var geometry: ScrollGeometry?
    var phase: ScrollPhase = .idle
    var visible: [ParagraphAnchor] = []
    /// A tap's scroll that hasn't been pinned to a paragraph yet.
    var landing: Task<Void, Never>?
    /// After a tap's scroll the position isn't anchored to a paragraph (pinning doesn't take),
    /// so a chapter joining above would push the text down. It counts as scrolling, which only
    /// stops joins above, until a finger moves the text and the scroll view anchors it again.
    var unanchored = false

    var topVisible: ParagraphAnchor? {
        visible.min { ($0.chapter, $0.block) < ($1.chapter, $1.block) }
    }
}
