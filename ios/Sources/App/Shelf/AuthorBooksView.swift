import ShioriLibrary
import SwiftUI

/// Every book on the shelf by one author, opened from the detail page's author link. A row
/// pushes that book's detail page, which grows out of the row.
struct AuthorBooksView: View {
    let author: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var detail: UUID?
    @State private var scrolled = false
    @Namespace private var zoom

    init(author: String) {
        self.author = author
    }

    var body: some View {
        let books = model.books.filter { $0.book.author == author }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(code: "01 / SHELF / AUTHOR", title: "Books by \(author)")
                    .padding(.bottom, 20)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, item in
                        row(item)
                            .staggeredReveal(index + 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 60
        } action: { _, past in
            scrolled = past
        }
        .safeAreaBar(edge: .top) {
            ShelfPageBar(code: nil, title: scrolled ? Text("Books by \(author)") : nil, headingID: scrolled)
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $detail) { id in
            BookDetailView(bookId: id)
                .navigationTransition(.zoom(sourceID: id, in: zoom))
        }
        .onChange(of: books.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    private func row(_ item: BookListItem) -> some View {
        Button { detail = item.id } label: {
            BookRow(item: item)
                .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .matchedTransitionSource(id: item.id, in: zoom)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.line)
                .frame(height: 1 / displayScale)
        }
    }
}
