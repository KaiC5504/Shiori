import CoreGraphics
import Foundation

enum AppTab: CaseIterable, Hashable {
    case shelf, imports, settings

    var title: LocalizedStringResource {
        switch self {
        case .shelf: "Shelf"
        case .imports: "Import"
        case .settings: "Settings"
        }
    }

    var icon: ShioriIcon {
        switch self {
        case .shelf: .shelf
        case .imports: .import
        case .settings: .settings
        }
    }
}

/// The floating bar's geometry (spec §5.1). Widths always come from the screen.
enum BarMetrics {
    static let height: CGFloat = 64
    /// Used where there's no home indicator; with one, RootView lowers the bar into its band.
    static let bottomGap: CGFloat = 12
    static let horizontalInset: CGFloat = 16
    /// What every tab's content reserves at the bottom so its last row clears the bar.
    static let contentBottomPadding: CGFloat = height + bottomGap + 8
}
