import os
import ShioriLibrary
import SwiftUI

private let log = Logger(subsystem: "com.kaichuan.shiori", category: "shelf")

/// The way back into the last book read (spec §5.3). It always opens the reader, whatever "Open
/// book directly" says.
struct ContinueCard: View {
    let item: BookListItem
    let zoom: Namespace.ID
    let open: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @ScaledMetric(relativeTo: .body) private var coverWidth: CGFloat = 60
    @State private var chapter: ChapterLine = .loading
    @State private var framed = false

    var body: some View {
        Button(action: open) {
            card
        }
        .buttonStyle(PressableButtonStyle())
        .task(id: Place(item.progress)) { await loadChapter() }
        .onAppear {
            guard !framed else { return }
            withAnimation(Motion.animation(Motion.reveal, reduced: reduced).delay(reduced ? 0 : 0.25)) {
                framed = true
            }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        let shown = framed || reduced
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BookCover(book: item.book, width: coverWidth)
                    .coverZoomSource(CoverZoom(id: ShelfDetail(bookId: item.id, source: .card), namespace: zoom))
                VStack(alignment: .leading, spacing: 4) {
                    SerialText(bookId: item.id)
                    Text(verbatim: item.book.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    place
                        .font(.subheadline)
                        .foregroundStyle(Tokens.inkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Track(fraction: shown ? fraction : 0)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize()
                ContinueCapsule()
            }
        }
        .padding(16)
        .background(Tokens.surface, in: shape)
        .overlay { shape.strokeBorder(Tokens.line, lineWidth: 1) }
        .overlay {
            // The marks close in on the corners as the card arrives.
            CornerMarks(cornerRadius: 8, arm: 12)
                .strokeBorder(Tokens.inkSecondary, lineWidth: 1.5)
                .padding(shown ? 0 : -6)
                .opacity(shown ? 1 : 0)
                .accessibilityHidden(true)
        }
        .contentShape(shape)
    }

    @ViewBuilder
    private var place: some View {
        if item.book.format == .pdf, let progress = item.progress {
            Text("Page \(progress.chapterIndex + 1)")
        } else {
            switch chapter {
            case .loading:
                // Holds the line open, so the card doesn't grow when the title lands.
                Text(verbatim: " ")
            case .title(let title):
                Text(verbatim: title)
                    .transition(.opacity)
            case .number(let number):
                Text("Chapter \(number)")
                    .transition(.opacity)
            }
        }
    }

    private var fraction: Double {
        min(max(item.progress?.fraction ?? 0, 0), 1)
    }

    private func loadChapter() async {
        guard let progress = item.progress, item.book.format != .pdf else { return }
        let database = model.database, bookId = item.id, index = progress.chapterIndex
        let title = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                return try database.chapter(bookId: bookId, index: index)?.title
            } catch {
                log.error("loading the Continue card's chapter failed: \(error)")
                return nil
            }
        }.value
        guard !Task.isCancelled else { return }
        let line: ChapterLine = title.flatMap { $0.isEmpty ? nil : .title($0) } ?? .number(index + 1)
        withAnimation(Motion.animation(.easeOut(duration: 0.2), reduced: reduced)) { chapter = line }
    }
}

private extension ContinueCard {
    enum ChapterLine: Equatable {
        case loading
        case title(String)
        case number(Int)
    }

    /// What the chapter title depends on: a re-split can rename the chapter at the same index.
    struct Place: Equatable {
        let index: Int?
        let keyTitle: String?
        let keyOccurrence: Int?

        init(_ progress: ShioriLibrary.Progress?) {
            index = progress?.chapterIndex
            keyTitle = progress?.keyTitle
            keyOccurrence = progress?.keyOccurrence
        }
    }

    struct Track: View {
        let fraction: Double
        @Environment(\.accent) private var accent

        var body: some View {
            Rectangle()
                .fill(Tokens.line)
                .frame(height: 2)
                .overlay {
                    Rectangle()
                        .fill(accent)
                        .scaleEffect(x: fraction, y: 1, anchor: .leading)
                }
                .accessibilityHidden(true)
        }
    }

    struct ContinueCapsule: View {
        @Environment(\.accent) private var accent

        var body: some View {
            HStack(spacing: 6) {
                PlayGlyph()
                    .fill(Tokens.paper)
                    .frame(width: 8, height: 9)
                Text("Continue")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Tokens.paper)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(accent, in: Capsule())
        }
    }

    struct PlayGlyph: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    /// The archive frame's corner brackets (reference 06's progress card), each one bending
    /// around its rounded corner.
    struct CornerMarks: InsettableShape {
        var cornerRadius: CGFloat
        var arm: CGFloat
        var inset: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let r = rect.insetBy(dx: inset, dy: inset)
            let radius = max(0, cornerRadius - inset)
            let reach = radius + arm
            let corners: [(CGPoint, CGVector, CGVector)] = [
                (CGPoint(x: r.minX, y: r.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0)),
                (CGPoint(x: r.maxX, y: r.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
                (CGPoint(x: r.maxX, y: r.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0)),
                (CGPoint(x: r.minX, y: r.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
            ]
            var path = Path()
            for (corner, from, to) in corners {
                let end = CGPoint(x: corner.x + to.dx * reach, y: corner.y + to.dy * reach)
                path.move(to: CGPoint(x: corner.x + from.dx * reach, y: corner.y + from.dy * reach))
                path.addArc(tangent1End: corner, tangent2End: end, radius: radius)
                path.addLine(to: end)
            }
            return path
        }

        func inset(by amount: CGFloat) -> CornerMarks {
            var marks = self
            marks.inset += amount
            return marks
        }
    }
}
