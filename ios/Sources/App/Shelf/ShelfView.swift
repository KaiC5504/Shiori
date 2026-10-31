import ShioriLibrary
import SwiftUI

// Stub from the contracts commit; Task 4 replaces the body.
struct ShelfView: View {
    @Environment(AppModel.self) private var model
    let onOpen: (Book) -> Void

    init(onOpen: @escaping (Book) -> Void) {
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(code: "01 / SHELF", title: "Shelf")
                ForEach(model.books) { item in
                    Button(item.book.title) { onOpen(item.book) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Tokens.paper)
    }
}
