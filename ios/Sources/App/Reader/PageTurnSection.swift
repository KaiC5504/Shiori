import SwiftUI

// Stub from the wave 3 contracts commit; C2 implements it.
/// PAGE TURN in the Aa sheet: Scroll, Paragraph relay or Curl, and relay's speed.
struct PageTurnSection: View {
    @Bindable var preferences: ReaderPreferences

    init(preferences: ReaderPreferences) {
        _preferences = Bindable(preferences)
    }

    var body: some View {
        EmptyView()
    }
}
