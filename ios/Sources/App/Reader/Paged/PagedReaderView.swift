import ShioriLibrary
import SwiftUI

/// A place in the paged layout: the chapter and a UTF-16 offset into its plain text, which a
/// change of type or page size doesn't move.
struct ReaderPosition: Equatable, Sendable {
    var chapter: Int
    var offset: Int
}

@MainActor
protocol PagedSource: AnyObject {
    var chapterCount: Int { get }
    /// Laid out with the current typography; nil when the chapter failed to load.
    func layout(chapter: Int, size: PageSize) async -> ChapterLayout?
}

// Stub from the wave 3 contracts commit; C2 implements it.
/// The paged layout (spec §7.2): Core Text pages turned by paragraph relay or Apple's curl.
/// Reads the effect, speed, tap zones and theme from `model.readerPreferences`.
struct PagedReaderView: View {
    let source: PagedSource
    @Binding var position: ReaderPosition
    let onMenu: () -> Void
    let onTurn: () -> Void

    init(source: PagedSource, position: Binding<ReaderPosition>,
         onMenu: @escaping () -> Void, onTurn: @escaping () -> Void) {
        self.source = source
        _position = position
        self.onMenu = onMenu
        self.onTurn = onTurn
    }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { onMenu() }
    }
}
