import ShioriLibrary
import SwiftUI

// Stub from the contracts commit; Task 5 replaces the body.
struct ReaderView: View {
    @Environment(AppModel.self) private var model
    let book: Book
    let showContents: Bool

    /// Closes by setting `model.openBook = nil`.
    init(book: Book, showContents: Bool = false) {
        self.book = book
        self.showContents = showContents
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: book.title).font(.title2.bold())
            Button("Back") { model.openBook = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.paper.ignoresSafeArea())
    }
}
