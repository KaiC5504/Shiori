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

    /// Placeholders until M2's folded-paper icons.
    var systemImage: String {
        switch self {
        case .shelf: "books.vertical"
        case .imports: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }
}

/// The floating bar's geometry (spec §5.1). Widths always come from the screen.
enum BarMetrics {
    static let height: CGFloat = 64
    static let bottomGap: CGFloat = 12
    static let horizontalInset: CGFloat = 16
    /// What every tab's content reserves at the bottom so its last row clears the bar.
    static let contentBottomPadding: CGFloat = height + bottomGap + 20
}
