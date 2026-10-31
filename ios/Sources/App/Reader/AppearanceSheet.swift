import SwiftUI

/// The Aa sheet: type and paper, applied to the page behind it as they change. Stub; R2
/// builds it. Reads and writes `AppModel.readerPreferences`.
struct AppearanceSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.readerPreferences
        Form {
            Stepper(value: $preferences.typography.size, in: 10...27) {
                Text("Text size")
            }
        }
    }
}
