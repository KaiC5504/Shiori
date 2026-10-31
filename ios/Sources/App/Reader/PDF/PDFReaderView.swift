import os
import PDFKit
import ShioriCore
import ShioriLibrary
import SwiftUI

private let pdfLog = Logger(subsystem: "com.kaichuan.shiori", category: "pdf")

/// The PDF reader (spec §7.12): the file's own pages under the same floating chrome as the
/// text reader. The place is the page index, kept in `Progress.chapterIndex`. Closes by
/// setting `model.openBook = nil`.
struct PDFReaderView: View {
    let book: Book

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionReduced) private var reduced
    @Environment(\.accent) private var accent
    @Environment(\.hapticsEnabled) private var hapticsEnabled
    // App-wide rather than per book, like the reader's other preferences.
    @AppStorage("pdf.layout") private var layout = PDFPageLayout.vertical
    @AppStorage("pdf.cropsMargins") private var cropsMargins = false

    @State private var opened: OpenedPDF?
    @State private var openFailed = false
    /// 0-based, the page on screen.
    @State private var page = 0
    @State private var lastSavedPage: Int?
    @State private var showsChrome = false
    @State private var sheet: PDFSheet?
    @State private var pages = PDFPagesController()
    @State private var tracker: ReadingSessionTracker?
    /// Every page's measured content, once all are measured.
    @State private var margins: [Int: CGRect]?
    @State private var turns = 0
    /// Bumped on each page change while the chrome is hidden, to flash the page badge.
    @State private var badge = 0
    @State private var showsBadge = false

    var body: some View {
        ZStack {
            if let opened {
                PDFPagesView(document: opened.document, layout: layout,
                             contentRects: cropsMargins ? margins : nil, startPage: opened.startPage,
                             controller: pages, onPageChange: pageChanged, onSettle: settled, onTap: tap)
                    .ignoresSafeArea()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pdf.pages")
                    .accessibilityAction(.magicTap) { setChrome(!showsChrome) }
                    .accessibilityAction(.escape) { close() }
                if showsBadge, !showsChrome, model.readerPreferences.showsInfoFooter {
                    pageBadge(opened)
                }
            } else if openFailed {
                failure
            } else {
                ProgressView()
                    .tint(Tokens.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.paper.ignoresSafeArea())
        .overlay {
            if showsChrome, let opened {
                chrome(opened)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(model.readerPreferences.hidesStatusBar && !(showsChrome || openFailed))
        .sheet(item: $sheet) { kind in
            Group {
                if let opened {
                    switch kind {
                    case .thumbnails:
                        PDFThumbnailGrid(renderer: opened.renderer, current: page) { go(to: $0) }
                    case .outline:
                        PDFOutlineSheet(rows: opened.outline, current: currentRow(opened)?.id) { jump(to: $0) }
                    }
                }
            }
            .environment(\.accent, accent)
            .environment(\.motionReduced, reduced)
            .environment(\.hapticsEnabled, hapticsEnabled)
        }
        .shioriHaptic(.impact(weight: .light), trigger: turns)
        .task { await open() }
        .task(id: page) {
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
            save()
        }
        .task(id: cropsMargins && opened != nil) { await measureMargins() }
        .task(id: badge) {
            guard badge > 0 else { return }
            withAnimation(Motion.animation(.easeOut(duration: 0.2), reduced: reduced)) { showsBadge = true }
            guard (try? await Task.sleep(for: .seconds(1.4))) != nil else { return }
            withAnimation(Motion.animation(.easeOut(duration: 0.3), reduced: reduced)) { showsBadge = false }
        }
        .onAppear { keepAwake(model.readerPreferences.keepsScreenAwake) }
        .onChange(of: model.readerPreferences.keepsScreenAwake) { _, keeps in keepAwake(keeps) }
        .onDisappear {
            save()
            tracker?.stop()
            keepAwake(false)
        }
        .onChange(of: scenePhase) { _, phase in
            // The app switcher only makes the scene inactive, and a swipe-kill from there never
            // reaches the background, so inactive saves too.
            if phase != .active {
                save()
                tracker?.pause()
            }
        }
    }

    private func chrome(_ opened: OpenedPDF) -> some View {
        PDFChrome(
            title: book.title, page: page, pageCount: opened.pageCount,
            section: { page in PDFOutlineRow.row(containing: page, in: opened.outline)?.title },
            hasOutline: !opened.outline.isEmpty,
            layout: $layout, cropsMargins: $cropsMargins,
            isCropping: cropsMargins && margins == nil,
            onBack: close,
            onJump: { go(to: $0) },
            onThumbnails: { sheet = .thumbnails },
            onContents: { sheet = .outline })
    }

    /// The place, briefly, after a page turn with the chrome hidden; the chrome reads it out.
    private func pageBadge(_ opened: OpenedPDF) -> some View {
        Text(verbatim: "\(page + 1) / \(opened.pageCount)")
            .font(.system(size: 12, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Tokens.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(Tokens.paper.opacity(0.5)), in: .capsule)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .transition(reduced ? .opacity : .opacity.combined(with: .offset(y: 8)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var failure: some View {
        Text("Couldn't open this book.")
            .foregroundStyle(Tokens.inkSecondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                Button(action: close) {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Tokens.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 8)
            }
    }

    private func open() async {
        guard opened == nil, !openFailed else { return }
        let url = model.paths.bookDirectory(book.id).appending(path: "original.pdf")
        let database = model.database
        let bookId = book.id
        let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedPDF? in
            guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { return nil }
            return LoadedPDF(document: document, saved: try? database.progress(bookId: bookId))
        }.value
        guard let loaded else {
            pdfLog.error("opening a PDF failed")
            openFailed = true
            return
        }
        let count = loaded.document.pageCount
        // An updated PDF can have fewer pages than the saved place.
        let start = min(max(loaded.saved?.chapterIndex ?? 0, 0), count - 1)
        lastSavedPage = loaded.saved?.chapterIndex ?? start
        page = start
        opened = OpenedPDF(document: loaded.document, outline: PDFOutlineRow.rows(of: loaded.document),
                           renderer: PDFPageRenderer(url: url), startPage: start)
        tracker = ReadingSessionTracker(database: model.database, bookId: book.id)
        #if DEBUG
        if DemoLaunch.showsChrome { showsChrome = true }
        if DemoLaunch.pdf == "thumbs" {
            // A sheet asked for while the full-screen cover is still sliding in is dropped.
            try? await Task.sleep(for: .milliseconds(600))
            sheet = .thumbnails
        }
        #endif
    }

    private func save() {
        guard let opened, page != lastSavedPage else { return }
        let progress = ShioriLibrary.Progress(
            bookId: book.id, chapterIndex: page, keyTitle: "", keyOccurrence: 0, offset: 0,
            fraction: Double(page + 1) / Double(opened.pageCount), updatedAt: .now)
        do {
            try model.database.save(progress)
            lastSavedPage = page
        } catch {
            pdfLog.error("saving progress failed: \(error)")
        }
    }

    /// Measures every page once, from the cache where it can, and only then crops, so the pages
    /// change size once rather than under the reader's finger.
    private func measureMargins() async {
        guard cropsMargins, margins == nil, let opened else { return }
        var found = PDFMargins.load(contentHash: book.contentHash)
        let missing = (0..<opened.pageCount).filter { found[$0] == nil }
        for index in missing {
            if Task.isCancelled { break }
            found[index] = await opened.renderer.contentRect(index)
        }
        if !missing.isEmpty { PDFMargins.save(found, contentHash: book.contentHash) }
        guard !Task.isCancelled, found.count >= opened.pageCount else { return }
        margins = found
    }

    private func pageChanged(_ index: Int) {
        guard index != page else { return }
        page = index
        tracker?.ping(chapterIndex: index)
        if !showsChrome { badge += 1 }
        // A swipe turns one page; in a scroll, pages pass too often to tick each one.
        if layout == .pages { turns += 1 }
    }

    /// PDFKit landed after opening or a relayout. A page other than the one asked for is
    /// shown, but not saved: it came from layout, not from reading.
    private func settled(on index: Int) {
        guard index != page else { return }
        page = index
        lastSavedPage = index
    }

    private func go(to index: Int) {
        guard let opened, index >= 0, index < opened.pageCount else { return }
        page = index
        pages.go(toPage: index)
        tracker?.ping(chapterIndex: index)
    }

    private func jump(to row: PDFOutlineRow) {
        if let destination = row.destination {
            if let target = row.page { page = target }
            pages.go(to: destination)
        } else if let target = row.page {
            go(to: target)
        }
    }

    private func turn(by step: Int) {
        guard let opened else { return }
        let target = page + step
        guard target >= 0, target < opened.pageCount else { return }
        page = target
        pages.turn(forward: step > 0)
        tracker?.ping(chapterIndex: target)
        turns += 1
        badge += 1
    }

    private func tap(at point: CGPoint, in size: CGSize) {
        tracker?.ping(chapterIndex: page)
        if showsChrome {
            setChrome(false)
            return
        }
        let preferences = model.readerPreferences
        switch TapZones.action(x: point.x, y: point.y, width: size.width, height: size.height,
                               layout: preferences.tapLayout, bothSidesForward: preferences.bothSidesForward) {
        case .menu: setChrome(true)
        case .back: turn(by: -1)
        case .forward: turn(by: 1)
        }
    }

    private func currentRow(_ opened: OpenedPDF) -> PDFOutlineRow? {
        PDFOutlineRow.row(containing: page, in: opened.outline)
    }

    private func setChrome(_ visible: Bool) {
        withAnimation(Motion.animation(.spring(duration: 0.3, bounce: 0.15), reduced: reduced)) {
            showsChrome = visible
            if visible { showsBadge = false }
        }
    }

    private func keepAwake(_ keeps: Bool) {
        UIApplication.shared.isIdleTimerDisabled = keeps
    }

    private func close() {
        save()
        tracker?.stop()
        model.openBook = nil
    }
}

private struct OpenedPDF {
    let document: PDFDocument
    let outline: [PDFOutlineRow]
    let renderer: PDFPageRenderer
    let startPage: Int

    var pageCount: Int { document.pageCount }
}

/// Carries the document off the loading task; nothing else touches it until then.
private struct LoadedPDF: @unchecked Sendable {
    let document: PDFDocument
    let saved: ShioriLibrary.Progress?
}

private enum PDFSheet: Identifiable {
    case thumbnails, outline

    var id: Self { self }
}
