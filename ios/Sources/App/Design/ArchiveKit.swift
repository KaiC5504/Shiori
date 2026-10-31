import SwiftUI

// Stubs from wave 1's contracts commit; A1 gives them the archive look (spec §4.3).

struct SectionLabel: View {
    let code: String
    let title: LocalizedStringResource

    init(code: String, title: LocalizedStringResource) {
        self.code = code
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: code)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Tokens.inkSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Tokens.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SerialText: View {
    let bookId: UUID

    init(bookId: UUID) {
        self.bookId = bookId
    }

    var body: some View {
        Text(verbatim: "SH-000000")
            .font(.caption2.monospaced())
            .foregroundStyle(Tokens.inkSecondary)
    }
}

struct ArchiveCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
    }
}

extension View {
    func paperBackground() -> some View {
        background(Tokens.paper.ignoresSafeArea())
    }
}
