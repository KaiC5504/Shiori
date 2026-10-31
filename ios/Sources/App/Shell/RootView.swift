import ShioriLibrary
import SwiftUI

/// Three tabs, each with its own navigation stack kept alive, under the floating bar. The
/// reader covers everything, bar included. App-wide settings enter the environment here.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var systemLocale
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        let settings = model.settings
        let accent = Tokens.accent(settings.accent)
        content
            .preferredColorScheme(settings.colorScheme)
            .environment(\.locale, settings.locale ?? systemLocale)
            .environment(\.accent, accent)
            .tint(accent)
            .environment(\.motionReduced, systemReduceMotion || settings.reduceMotion)
            .environment(\.hapticsEnabled, settings.haptics)
            .onOpenURL { url in
                Task { await model.handleIncoming(url) }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if DemoLaunch.showsIcons {
            IconGalleryView()
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        @Bindable var model = model
        return ZStack(alignment: .bottom) {
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
            VStack(spacing: 10) {
                if let toast = model.toast {
                    ImportToast(toast: toast, open: { open(toast) })
                        .padding(.horizontal, BarMetrics.horizontalInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ShioriTabBar(selection: $model.selectedTab)
                    .padding(.horizontal, BarMetrics.horizontalInset)
            }
            // Down into the home indicator's band, as iOS's own floating tab bar sits; the gap
            // alone still applies on iPhones without one.
            .padding(.bottom, max(bottomInset - 14, BarMetrics.bottomGap))
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
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

    private func open(_ toast: Toast) {
        model.toast = nil
        if let id = toast.bookId, let item = model.books.first(where: { $0.id == id }) {
            model.openBook = item.book
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
