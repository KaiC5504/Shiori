import SwiftUI

// Stub from the contracts commit; Task 2 replaces the body.
struct ShioriTabBar: View {
    @Binding var selection: AppTab

    init(selection: Binding<AppTab>) {
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage).font(.system(size: 20))
                        Text(tab.title).font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == tab ? Tokens.ink : Tokens.inkSecondary)
                }
            }
        }
        .frame(height: BarMetrics.height)
        .background(Tokens.surface, in: Capsule())
    }
}
