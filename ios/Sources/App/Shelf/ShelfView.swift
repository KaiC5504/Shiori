import ShioriLibrary
import SwiftUI

struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @Environment(\.displayScale) private var displayScale
    /// Set once the opening screenful has revealed, so views met later by scrolling don't wait
    /// out a stagger delay meant for it.
    @State private var revealSettled = false
    @State private var detail: ShelfDetail?
    @Namespace private var zoom
    #if DEBUG
    @State private var demoPushed = false
    #endif
    let onOpen: (Book) -> Void

    init(onOpen: @escaping (Book) -> Void) {
        self.onOpen = onOpen
    }

    var body: some View {
        Group {
            if model.books.isEmpty {
                VStack(spacing: 0) {
                    header
                    EmptyShelf { model.selectedTab = .imports }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                ScrollView {
                    // The shelf sits outside the lazy list, so it keeps its scroll position.
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                        if let last = ShelfRing.lastRead(in: model.books) {
                            continueCard(last)
                                .staggeredReveal(revealSettled ? 0 : 1)
                                // Another book read last is a new card, which arrives with its own reveal.
                                .id(last.id)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 28)
                        }
                        SectionLabel(code: "COLLECTION / SHELF", title: "3D shelf")
                            .staggeredReveal(2)
                            .padding(.horizontal, 20)
                        SpineShelf(books: model.books, settled: revealSettled, zoom: zoom) { open($0, from: .crest) }
                            .padding(.top, 4)
                        SectionLabel(code: "COLLECTION / LIST", title: "All books")
                            .staggeredReveal(revealSettled ? 0 : 8)
                            .padding(.horizontal, 20)
                            .padding(.top, 36)
                            .padding(.bottom, 4)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.books.enumerated()), id: \.element.id) { index, item in
                                ShelfRow(item: item, zoom: zoom,
                                         open: { open($0, from: .list) },
                                         read: { onOpen($0.book) },
                                         details: { show($0, from: .list) })
                                    .staggeredReveal(revealSettled ? 0 : index + 9)
                            }
                        }
                        .padding(.horizontal, 20)
                        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: model.books.map(\.id))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        }
        .paperBackground()
        .navigationDestination(item: $detail) { route in
            BookDetailView(bookId: route.bookId)
                .modifier(ZoomOutOfCover(route: route, namespace: zoom))
        }
        .task(id: model.books.isEmpty) {
            guard !model.books.isEmpty, !revealSettled,
                  (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            revealSettled = true
        }
        #if DEBUG
        .task(id: [model.isImporting ? 1 : 0, model.books.count]) { await pushDemoDetail() }
        #endif
    }

    private var header: some View {
        ScreenHeader(code: "01 / SHELF", title: "Shelf")
            .staggeredReveal(0)
    }

    private func continueCard(_ item: BookListItem) -> some View {
        ContinueCard(item: item, zoom: zoom) { onOpen(item.book) }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
            .contextMenu {
                Button {
                    show(item, from: .card)
                } label: {
                    Label { Text("Details") } icon: { MenuIcon.image(.info, scale: displayScale) }
                }
            }
    }

    /// A tap on the crest or a row: the book's page, or the reader when "Open book directly" is on.
    private func open(_ item: BookListItem, from source: ShelfDetail.Source) {
        if model.settings.opensBookDirectly {
            onOpen(item.book)
        } else {
            show(item, from: source)
        }
    }

    private func show(_ item: BookListItem, from source: ShelfDetail.Source) {
        detail = ShelfDetail(bookId: item.id, source: source)
    }

    #if DEBUG
    /// Waits for the demo library's imports, which reorder the shelf as each book lands.
    private func pushDemoDetail() async {
        guard !demoPushed, let n = DemoLaunch.detailIndex, !model.isImporting, !model.books.isEmpty,
              (try? await Task.sleep(for: .seconds(1))) != nil,
              model.books.indices.contains(n - 1) else { return }
        demoPushed = true
        show(model.books[n - 1], from: .list)
    }
    #endif
}

/// A detail page pushed from the shelf, and which cover it grows out of.
struct ShelfDetail: Hashable {
    enum Source: Hashable {
        case card, crest, list
    }

    let bookId: UUID
    let source: Source
}

/// A cover that a detail page zooms out of, and back into on the way back.
struct CoverZoom {
    let id: ShelfDetail
    let namespace: Namespace.ID
}

extension View {
    @ViewBuilder
    func coverZoomSource(_ zoom: CoverZoom?) -> some View {
        if let zoom {
            matchedTransitionSource(id: zoom.id, in: zoom.namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 4))
            }
        } else {
            self
        }
    }
}

/// Under reduced motion the page arrives with the default push instead.
private struct ZoomOutOfCover: ViewModifier {
    let route: ShelfDetail
    let namespace: Namespace.ID
    @Environment(\.motionReduced) private var reduced

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduced {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: route, in: namespace))
        }
    }
}

/// One list row. A tap opens the book's page (or the reader); the round button and a long press
/// hold Continue, Details, Re-detect chapters for TXT books, and Remove (confirmed first).
private struct ShelfRow: View {
    let item: BookListItem
    let zoom: Namespace.ID
    let open: (BookListItem) -> Void
    let read: (BookListItem) -> Void
    let details: (BookListItem) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { open(item) } label: {
                BookRow(item: item, zoom: CoverZoom(id: ShelfDetail(bookId: item.id, source: .list), namespace: zoom))
            }
            .buttonStyle(PressableButtonStyle())
            VStack(spacing: 8) {
                Menu {
                    actions
                } label: {
                    IconView(.more, size: 18)
                        .frame(width: 36, height: 36)
                        .background(Tokens.surface, in: Circle())
                        .overlay { Circle().strokeBorder(Tokens.line, lineWidth: 0.5) }
                        .contentShape(Circle())
                }
                .menuIndicator(.hidden)
                .accessibilityLabel(Text("More"))
                ReadingStatusText(state: ReadingState(item), compact: true)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Tokens.inkSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 44)
        }
        .padding(.horizontal, 8)
        // Paper rather than clear, so the long-press preview lifts a solid row.
        .background(Tokens.paper)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
        .contextMenu { actions }
        .confirmationDialog(Text("Remove “\(item.book.title)”?"), isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task { await model.removeBook(item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its reading progress is deleted too. The watched folder won't add it back.")
        }
        // The inner padding lines the cover up with the header's edge.
        .padding(.horizontal, -8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.line)
                .frame(height: 1 / displayScale)
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            read(item)
        } label: {
            Label {
                item.progress == nil ? Text("Start reading") : Text("Continue")
            } icon: {
                MenuIcon.image(.play, scale: displayScale)
            }
        }
        Button {
            details(item)
        } label: {
            Label { Text("Details") } icon: { MenuIcon.image(.info, scale: displayScale) }
        }
        Divider()
        if item.book.format == .txt {
            Button {
                Task { await model.resplit(item.id) }
            } label: {
                Label { Text("Re-detect chapters") } icon: { MenuIcon.image(.refresh, scale: displayScale) }
            }
        }
        Button(role: .destructive) {
            confirmingRemoval = true
        } label: {
            Label { Text("Remove from library") } icon: { MenuIcon.image(.delete, scale: displayScale) }
        }
    }
}

/// Shiori's own icons for system menus, which only take images.
@MainActor
private enum MenuIcon {
    private static var cache: [String: Image] = [:]

    static func image(_ icon: ShioriIcon, scale: CGFloat) -> Image {
        let key = "\(icon.rawValue)@\(scale)"
        if let image = cache[key] { return image }
        let renderer = ImageRenderer(content: IconView(icon, size: 24))
        renderer.scale = scale
        // Template, so the menu tints it like its text (red for Remove).
        let image = renderer.uiImage.map { Image(uiImage: $0.withRenderingMode(.alwaysTemplate)) }
            ?? Image(uiImage: UIImage())
        cache[key] = image
        return image
    }
}

private struct EmptyShelf: View {
    let onImport: () -> Void
    @Environment(\.accent) private var accent
    @State private var lifted = false

    var body: some View {
        VStack(spacing: 12) {
            IconView(.shelf, active: lifted, size: 48)
                .onAppear { lifted = true }
            Text("Your shelf is empty")
                .font(.title3.bold())
                .foregroundStyle(Tokens.ink)
            Text("Import EPUB or TXT books to start reading.")
                .font(.subheadline)
                .foregroundStyle(Tokens.inkSecondary)
                .multilineTextAlignment(.center)
            Button(action: onImport) {
                Text("Import books")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Tokens.paper)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 8)
        }
        .staggeredReveal(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
