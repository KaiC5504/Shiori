import ShioriLibrary
import SwiftUI

// Stub from the wave 3 contracts commit; D1 implements it.
/// A book's detail page (spec §6.5), pushed in the Shelf tab's stack.
struct BookDetailView: View {
    let bookId: UUID

    @Environment(AppModel.self) private var model

    var body: some View {
        let item = model.books.first { $0.id == bookId }
        Button(item?.book.title ?? "") {
            if let item { model.openBook = item.book }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
    }
}
