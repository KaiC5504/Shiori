import CoreText
import ShioriLibrary
import SwiftUI

/// The scroll layout's type and ink. Fonts come from `TypographyAttributes`, so the scroll
/// and the paged engine pick the same face for the same settings.
struct ReaderStyle: Equatable {
    let typography: ReaderTypography
    let theme: ReaderTheme
    let nightTextBrightness: Double
    let body: Font
    let heading: Font
    let ink: Color
    let secondaryInk: Color
    let size: CGFloat
    let headingSize: CGFloat

    @MainActor init(_ preferences: ReaderPreferences) {
        let t = preferences.typography
        typography = t
        theme = preferences.theme
        nightTextBrightness = preferences.nightTextBrightness
        let headingFont = TypographyAttributes.font(t, heading: true)
        body = Font(TypographyAttributes.font(t))
        heading = Font(headingFont)
        ink = preferences.textColor
        secondaryInk = preferences.theme.inkSecondary
        size = CGFloat(max(t.size, 1))
        headingSize = CTFontGetSize(headingFont)
    }

    var lineHeight: CGFloat { size * CGFloat(max(typography.lineHeight, 1)) }
    var headingLineHeight: CGFloat { headingSize * CGFloat(max(typography.lineHeight, 1)) }
    /// The importer keeps no spacing from the book, so "as in the book" gets the same gap
    /// the paged engine gives it.
    var paragraphGap: CGFloat { CGFloat(typography.paragraphGap ?? typography.size * 0.6) }
    var chapterGap: CGFloat { max(32, size * 2.5) }

    // Fonts and colours are rebuilt on every pass, and fresh ones never compare equal, so
    // equality is on what they're made from; otherwise every row would redraw per chapter join.
    static func == (a: ReaderStyle, b: ReaderStyle) -> Bool {
        a.typography == b.typography && a.theme == b.theme && a.nightTextBrightness == b.nightTextBrightness
    }
}

/// Reads only the rows and the reader preferences, so the scroll position changing doesn't
/// re-render the text.
struct ReaderColumn: View {
    let reader: ReaderModel
    let preferences: ReaderPreferences

    var body: some View {
        let style = ReaderStyle(preferences)
        let margins = TypographyAttributes.margins(style.typography)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(reader.rows) { row in
                ReaderRowView(row: row, style: style)
                    .equatable()
            }
        }
        .scrollTargetLayout()
        .padding(.leading, margins.left)
        .padding(.trailing, margins.right)
        .padding(.bottom, 64)
    }
}

/// One `Text` per paragraph and title: the scroll position, and the UI tests, address them
/// one by one.
private struct ReaderRowView: View, Equatable {
    let row: ReaderRow
    let style: ReaderStyle

    var body: some View {
        content
            .padding(.bottom, row.endsChapter ? style.chapterGap : 0)
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .title(let text):
            title(text)
        case .heading(let text, _):
            heading(text)
                .padding(.top, style.paragraphGap)
                .padding(.bottom, max(style.paragraphGap, style.size))
        case .paragraph(let text):
            paragraph(text)
        case .image:
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(style.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 96)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(style.secondaryInk.opacity(0.35)))
                .padding(.bottom, style.paragraphGap)
                .accessibilityHidden(true)
        case .unreadable(let chapterTitle):
            VStack(alignment: .leading, spacing: 0) {
                if !chapterTitle.isEmpty { title(chapterTitle) }
                Text("Couldn't open this chapter.")
                    .font(style.body)
                    .foregroundStyle(style.secondaryInk)
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .empty:
            Color.clear.frame(height: 1)
        }
    }

    // SwiftUI's Text can't justify (AttributedString.TextAlignment has no justified case),
    // so `justify` only reaches the paged engine; Han text is near-even without it.
    private func paragraph(_ text: String) -> some View {
        // Two ideographic spaces are the 2 em indent; text that already starts with spaces
        // keeps its own, as in the paged engine.
        let indents = style.typography.firstLineIndent && text.first?.isWhitespace != true
        return Text(verbatim: indents ? "\u{3000}\u{3000}" + text : text)
            .font(style.body)
            .kerning(CGFloat(style.typography.letterSpacing))
            .lineHeight(.exact(points: style.lineHeight))
            .foregroundStyle(style.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, style.paragraphGap)
            .accessibilityLabel(Text(verbatim: text))
    }

    private func heading(_ text: String) -> some View {
        Text(verbatim: text)
            .font(style.heading)
            .kerning(CGFloat(style.typography.letterSpacing))
            .lineHeight(.exact(points: style.headingLineHeight))
            .foregroundStyle(style.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func title(_ text: String) -> some View {
        heading(text)
            .padding(.bottom, max(style.paragraphGap, style.size) * 1.5)
    }
}
