import SwiftUI

/// Stub from wave 1's contracts commit; B2 builds the card.
struct WatchedFolderCard: View {
    init() {}

    var body: some View {
        ArchiveCard {
            Text("Watched folder")
                .foregroundStyle(Tokens.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
    }
}
