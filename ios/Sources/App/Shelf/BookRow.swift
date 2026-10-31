import ShioriLibrary
import SwiftUI

struct BookRow: View {
    let item: BookListItem
    @ScaledMetric(relativeTo: .body) private var coverWidth: CGFloat = 44

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CoverPlaceholder(title: item.book.title)
                    .frame(width: coverWidth, height: coverWidth * 4 / 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.book.title)
                        .font(.headline)
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let author = item.book.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(Tokens.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                status
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize()
            }
            ProgressLine(fraction: item.progress?.fraction ?? 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if let progress = item.progress {
            Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
        } else {
            Text("Unread")
        }
    }
}

private struct CoverPlaceholder: View {
    let title: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Tokens.line)
            .overlay {
                Text(verbatim: title.first.map(String.init) ?? "")
                    .font(.system(.title3, design: .serif).bold())
                    .foregroundStyle(Tokens.inkSecondary)
            }
            .accessibilityHidden(true)
    }
}

private struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 2)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Tokens.ink)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .accessibilityHidden(true)
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}
