import SwiftUI

/// What the chrome shows about the place in the book.
struct ReaderChromeState: Equatable {
    var bookTitle: String
    var chapterTitle: String
    /// 0-based.
    var chapterIndex: Int
    var chapterCount: Int
}

/// The floating glass chrome (spec §7.7): a top bar and one bottom panel. Stub; R3 builds it.
struct ReaderChrome: View {
    let state: ReaderChromeState
    let onBack: () -> Void
    /// A 0-based chapter, sent when the slider is released or a chapter button is tapped.
    let onJump: (Int) -> Void
    let onContents: () -> Void
    let onAppearance: () -> Void
    let onDayNight: () -> Void

    init(state: ReaderChromeState, onBack: @escaping () -> Void, onJump: @escaping (Int) -> Void,
         onContents: @escaping () -> Void, onAppearance: @escaping () -> Void,
         onDayNight: @escaping () -> Void) {
        self.state = state
        self.onBack = onBack
        self.onJump = onJump
        self.onContents = onContents
        self.onAppearance = onAppearance
        self.onDayNight = onDayNight
    }

    var body: some View {
        VStack {
            HStack {
                Button("Back", action: onBack)
                Spacer()
                Text(state.bookTitle).lineLimit(1)
            }
            Spacer()
            HStack {
                Button("Contents", action: onContents)
                Button("Aa", action: onAppearance)
                Button("Night", action: onDayNight)
            }
        }
        .padding()
    }
}

/// The slim info line at the bottom of the page (spec §7.7). Stub; R3 builds it.
struct ReaderInfoFooter: View {
    let chapterTitle: String
    let chapterIndex: Int
    let chapterCount: Int

    var body: some View {
        Text(chapterTitle).font(.caption2).lineLimit(1)
    }
}
