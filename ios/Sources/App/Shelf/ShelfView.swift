import ShioriLibrary
import SwiftUI

struct ShelfView: View {
    @Environment(AppModel.self) private var model
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
                    LazyVStack(spacing: 8) {
                        header.padding(.bottom, 8)
                        ForEach(model.books) { item in
                            Button { onOpen(item.book) } label: {
                                BookRow(item: item)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(Tokens.paper)
    }

    private var header: some View {
        ScreenHeader(code: "01 / SHELF", title: "Shelf")
    }
}

private struct EmptyShelf: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Tokens.inkSecondary)
                .accessibilityHidden(true)
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
                    .background(Tokens.ink, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
