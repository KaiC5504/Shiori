import ShioriLibrary
import SwiftUI

// Stub from the contracts commit; Task 3 replaces the body.
struct ImportView: View {
    @Environment(AppModel.self) private var model

    init() {}

    var body: some View {
        ScrollView {
            ScreenHeader(code: "02 / IMPORT", title: "Import")
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .background(Tokens.paper)
    }
}
