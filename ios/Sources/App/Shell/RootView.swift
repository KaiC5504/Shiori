import ShioriLibrary
import SwiftUI

/// Three tabs, each with its own navigation stack kept alive, under the floating bar. The
/// reader covers everything, bar included.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    let selected = model.selectedTab == tab
                    NavigationStack {
                        screen(for: tab)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .safeAreaPadding(.bottom, BarMetrics.contentBottomPadding)
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(selected)
                    .accessibilityHidden(!selected)
                }
            }
            ShioriTabBar(selection: $model.selectedTab)
                .padding(.horizontal, BarMetrics.horizontalInset)
                .padding(.bottom, BarMetrics.bottomGap)
        }
        .background(Tokens.paper.ignoresSafeArea())
        .fullScreenCover(item: $model.openBook) { book in
            ReaderView(book: book, showContents: Self.demoShowsContents)
                .environment(model)
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .shelf: ShelfView(onOpen: { model.openBook = $0 })
        case .imports: ImportView()
        case .settings: SettingsView()
        }
    }

    private static var demoShowsContents: Bool {
        #if DEBUG
        DemoLaunch.showContents
        #else
        false
        #endif
    }
}
