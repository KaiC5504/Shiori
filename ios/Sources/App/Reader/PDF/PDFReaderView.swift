import ShioriLibrary
import SwiftUI

// Stub from the wave 3 contracts commit; P1 implements it.
/// The PDF reader (spec §7.12). Closes by setting `model.openBook = nil`.
struct PDFReaderView: View {
    let book: Book

    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Back") { model.openBook = nil }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.paper.ignoresSafeArea())
    }
}
