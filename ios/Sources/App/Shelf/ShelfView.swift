import ShioriLibrary
import SwiftUI

struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    /// Set once the first rows have arrived, so rows met later by scrolling don't wait out a
    /// stagger delay meant for the opening screenful.
    @State private var revealSettled = false
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
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.bottom, 28)
                        SectionLabel(code: "COLLECTION / SHELF", title: "All books")
                            .staggeredReveal(1)
                            .padding(.bottom, 4)
                        ForEach(Array(model.books.enumerated()), id: \.element.id) { index, item in
                            ShelfRow(item: item, open: open)
                                .staggeredReveal(revealSettled ? 0 : index + 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .animation(Motion.animation(Motion.reveal, reduced: reduced), value: model.books.map(\.id))
                }
            }
        }
        .paperBackground()
        .task(id: model.books.isEmpty) {
            guard !model.books.isEmpty, !revealSettled,
                  (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            revealSettled = true
        }
    }

    private var header: some View {
        ScreenHeader(code: "01 / SHELF", title: "Shelf")
            .staggeredReveal(0)
    }

    private func open(_ item: BookListItem) {
        guard item.book.format != .pdf else {
            withAnimation(Motion.animation(Motion.reveal, reduced: reduced)) {
                model.toast = Toast(id: UUID(), message: "PDF reading arrives in a later build.", bookId: nil)
            }
            return
        }
        onOpen(item.book)
    }
}

/// One shelf row with its long-press menu: Remove (confirmed first) and, for TXT books,
/// Re-detect chapters.
private struct ShelfRow: View {
    let item: BookListItem
    let open: (BookListItem) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @State private var confirmingRemoval = false

    var body: some View {
        Button { open(item) } label: {
            BookRow(item: item)
                .padding(.horizontal, 8)
                // Paper rather than clear, so the long-press preview lifts a solid row.
                .background(Tokens.paper)
        }
        .buttonStyle(PressableButtonStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
        .contextMenu {
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
