import SwiftUI

// Stub from the contracts commit; Task 4 replaces the body.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    init() {}

    var body: some View {
        ScrollView {
            ScreenHeader(code: "03 / SETTINGS", title: "Settings")
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .background(Tokens.paper)
    }
}
