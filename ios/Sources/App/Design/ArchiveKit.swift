import ShioriCore
import SwiftUI

/// The archive section label (spec §4.3): a mono code, a hairline that draws itself out to a
/// small square dot, then the bold section title.
struct SectionLabel: View {
    let code: String
    let title: LocalizedStringResource

    @Environment(\.motionReduced) private var reduced
    @State private var drawn = false

    init(code: String, title: LocalizedStringResource) {
        self.code = code
        self.title = title
    }

    var body: some View {
        let full = drawn || reduced
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(verbatim: code)
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Tokens.inkSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Rectangle()
                    .fill(Tokens.line)
                    .frame(height: 1)
                    .scaleEffect(x: full ? 1 : 0, anchor: .leading)
                    .animation(.easeOut(duration: 0.5), value: drawn)
                Rectangle()
                    .fill(Tokens.ink)
                    .frame(width: 3, height: 3)
                    .scaleEffect(full ? 1 : 0)
                    .animation(Motion.lens.delay(0.4), value: drawn)
            }
            .opacity(reduced && !drawn ? 0 : 1)
            .animation(.easeInOut(duration: 0.15), value: drawn)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Tokens.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { drawn = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isHeader)
    }
}

/// A book's "SH-123456" serial, shown above its title.
struct SerialText: View {
    let bookId: UUID

    init(bookId: UUID) {
        self.bookId = bookId
    }

    var body: some View {
        Text(verbatim: BookSerial.make(bookId))
            .font(.system(.caption2, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Tokens.inkSecondary)
            .lineLimit(1)
            // Archive flavour, not information: VoiceOver would read it digit by digit.
            .accessibilityHidden(true)
    }
}

struct ArchiveCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        content
            .background(Tokens.surface)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Tokens.line, lineWidth: 1) }
            .containerShape(shape)
    }
}

extension View {
    /// Solid paper, with the faint drafting grid behind the top of the screen (spec §4.3).
    func paperBackground() -> some View {
        background { PaperBackdrop() }
    }
}

private struct PaperBackdrop: View {
    var body: some View {
        DraftingGrid(spacing: 100)
            .stroke(Tokens.line.opacity(0.35), lineWidth: 1)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.3),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 280)
            .ignoresSafeArea(edges: [.top, .horizontal])
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Tokens.paper)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct DraftingGrid: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Centred horizontally, so the lines fall symmetrically on any width.
        var x = rect.midX - (rect.midX / spacing).rounded(.down) * spacing
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}
