import ShioriLibrary
import SwiftUI

struct BookRow: View {
    let item: BookListItem
    /// The cover a detail page pushed from this row zooms out of.
    let zoom: CoverZoom?
    @ScaledMetric(relativeTo: .body) private var coverWidth: CGFloat = 52

    init(item: BookListItem, zoom: CoverZoom? = nil) {
        self.item = item
        self.zoom = zoom
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCover(book: item.book, width: coverWidth)
                .coverZoomSource(zoom)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    SerialText(bookId: item.id)
                        .accessibilityHidden(true)
                    if item.showsUpdatedBadge {
                        UpdatedBadge(addedChapters: item.book.lastUpdateAddedChapters)
                            .transition(.opacity)
                    }
                }
                Text(verbatim: item.book.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let author = item.book.author {
                    Text(verbatim: author)
                        .font(.subheadline)
                        .foregroundStyle(Tokens.inkSecondary)
                        .lineLimit(1)
                }
                ProgressLine(fraction: item.progress?.fraction ?? 0)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Where the reader stands in a book (spec §6.3: Unread, Chapter N, Finished; a PDF has pages).
enum ReadingState: Equatable {
    case unread
    case reading(chapter: Int, of: Int, fraction: Double)
    case page(Int, fraction: Double)
    case finished

    init(_ item: BookListItem) {
        guard let progress = item.progress else {
            self = .unread
            return
        }
        if progress.fraction >= 0.995 {
            self = .finished
        } else if item.book.format == .pdf {
            // A PDF keeps its page in chapterIndex.
            self = .page(progress.chapterIndex + 1, fraction: progress.fraction)
        } else {
            self = .reading(chapter: progress.chapterIndex + 1, of: item.book.chapterCount, fraction: progress.fraction)
        }
    }
}

/// `compact` is the list's "12/18" or "Page 12"; otherwise "Chapter 12 · 62%" or "Page 12 · 62%".
struct ReadingStatusText: View {
    let state: ReadingState
    let compact: Bool

    var body: some View {
        switch state {
        case .unread:
            Text("Unread")
        case .finished:
            Text("Finished")
        case let .reading(chapter, total, fraction):
            if compact {
                Text(verbatim: "\(chapter)/\(total)")
                    .monospacedDigit()
                    .accessibilityLabel(Text("Chapter \(chapter)"))
            } else {
                HStack(spacing: 0) {
                    Text("Chapter \(chapter)")
                    Text(verbatim: " · ")
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                }
            }
        case let .page(page, fraction):
            if compact {
                Text("Page \(page)")
                    .monospacedDigit()
            } else {
                HStack(spacing: 0) {
                    Text("Page \(page)")
                    Text(verbatim: " · ")
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                }
            }
        }
    }
}

/// Marks a book an update changed since it was last opened (spec §8.4).
private struct UpdatedBadge: View {
    let addedChapters: Int?
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 4) {
            Text("Updated")
            if let addedChapters, addedChapters > 0 {
                Text(verbatim: "+\(addedChapters)")
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(accent.opacity(0.12), in: Capsule())
        .overlay { Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 0.5) }
    }
}

private struct ProgressLine: View {
    let fraction: Double
    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced

    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 2)
            .overlay {
                Rectangle()
                    .fill(accent)
                    .scaleEffect(x: min(max(fraction, 0), 1), y: 1, anchor: .leading)
            }
            .animation(Motion.animation(Motion.reveal, reduced: reduced), value: fraction)
            .accessibilityHidden(true)
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.motionReduced) private var reduced

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.animation(Motion.press, reduced: reduced), value: configuration.isPressed)
    }
}
