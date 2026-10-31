import ShioriLibrary
import SwiftUI

// Stub from the wave 3 contracts commit; R2 implements it.
/// The contents rows grouped by volume: a ForEach of Sections, for a List (the sheet) or a
/// LazyVStack (the detail page).
struct ContentsSections: View {
    let chapters: [Chapter]
    let current: Int?
    let query: String
    let reversed: Bool
    let onSelect: (Int) -> Void

    init(chapters: [Chapter], current: Int?, query: String, reversed: Bool,
         onSelect: @escaping (Int) -> Void) {
        self.chapters = chapters
        self.current = current
        self.query = query
        self.reversed = reversed
        self.onSelect = onSelect
    }

    var body: some View {
        let indices = reversed ? Array(chapters.indices.reversed()) : Array(chapters.indices)
        ForEach(indices, id: \.self) { index in
            Button {
                onSelect(index)
            } label: {
                ContentsSheet.title(of: chapters[index], at: index)
                    .foregroundStyle(Tokens.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
}
