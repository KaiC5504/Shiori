import ShioriCore
import ShioriLibrary
import SwiftUI
import UIKit

/// One slot of the spine shelf: a book built from flat faces, each moved into place by its own
/// `visualEffect` from the slot's scroll position, so scrolling never re-runs a body.
struct SpineBook: View {
    let item: BookListItem
    /// 1-based position among the featured books, for the NO.001 spine numbers.
    let number: Int
    let marked: Bool
    let metrics: ShelfMetrics
    /// Always posed as the crest, for a shelf of one book that has no row to scroll.
    let pinned: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.motionReduced) private var reduced
    @State private var image: UIImage?
    @State private var palette: BookPalette

    init(item: BookListItem, number: Int, marked: Bool, metrics: ShelfMetrics, pinned: Bool = false) {
        self.item = item
        self.pinned = pinned
        self.number = number
        self.marked = marked
        self.metrics = metrics
        let key = CoverThumbnails.key(item.book)
        _image = State(initialValue: item.book.hasCover
            ? CoverThumbnails.cached(key, height: metrics.coverHeight) : nil)
        _palette = State(initialValue: BookPalettes.cached(key) ?? BookPalette(bookId: item.id))
    }

    var body: some View {
        let block = BookBlock(bookId: item.id, chapterCount: item.book.chapterCount, metrics: metrics)
        let shadow = BookPose.shadowSize(block)
        let ribbon = BookPose.ribbonSize(block, rise: metrics.ribbonRise)
        ZStack(alignment: .topLeading) {
            face(.shadow, block) {
                Ellipse()
                    .fill(EllipticalGradient(colors: [palette.shade.opacity(0.75), palette.shade.opacity(0)]))
                    .frame(width: shadow.width, height: shadow.height)
            }
            face(.top, block) { TopFace(palette: palette, block: block) }
            face(.cover, block) {
                CoverFace(book: item.book, image: image, number: number, palette: palette, block: block)
            }
            face(.coverShade, block) {
                palette.shade.frame(width: block.depth, height: block.height)
            }
            if marked {
                face(.ribbon, block) {
                    RibbonShape()
                        .fill(Tokens.ribbon)
                        .frame(width: ribbon.width, height: ribbon.height)
                }
            }
            face(.spine, block) { SpineFace(book: item.book, number: number, palette: palette, block: block) }
            face(.spineShade, block) {
                palette.shade.frame(width: block.thickness, height: block.height)
            }
        }
        .frame(width: metrics.pitch, height: metrics.stageHeight, alignment: .topLeading)
        .task(id: CoverThumbnails.key(item.book)) { await loadCover() }
    }

    private func face<Content: View>(_ face: BookFace, _ block: BookBlock,
                                     @ViewBuilder content: () -> Content) -> some View {
        let metrics = metrics
        let pinned = pinned
        return content()
            .frame(width: metrics.pitch, height: metrics.stageHeight, alignment: .topLeading)
            .visualEffect { effect, proxy in
                let row = NamedCoordinateSpace.scrollView(axis: .horizontal)
                let offset = pinned ? 0 : proxy.bounds(of: row).map { proxy.size.width / 2 - $0.midX }
                    ?? proxy.frame(in: row).midX - metrics.viewport / 2
                let pose = BookPose(offset: offset, block: block, metrics: metrics)
                return effect
                    .transformEffect(pose.transform(face))
                    .opacity(pose.opacity(face))
            }
    }

    // Slots keep their place as the ring turns, so the book in this one can change under it.
    private func loadCover() async {
        let key = CoverThumbnails.key(item.book)
        image = item.book.hasCover ? CoverThumbnails.cached(key, height: metrics.coverHeight) : nil
        palette = BookPalettes.cached(key) ?? BookPalette(bookId: item.id)
        guard item.book.hasCover,
              let loaded = await CoverThumbnails.load(from: model.paths.bookDirectory(item.id), key: key,
                                                      height: metrics.coverHeight, scale: displayScale)
        else { return }
        let tone = await BookPalettes.palette(for: key, image: loaded)
        guard loaded !== image || (tone != nil && tone != palette) else { return }
        withAnimation(Motion.animation(.easeOut(duration: 0.25), reduced: reduced)) {
            image = loaded
            if let tone { palette = tone }
        }
    }
}

private struct SpineFace: View {
    let book: Book
    let number: Int
    let palette: BookPalette
    let block: BookBlock

    var body: some View {
        let t = block.thickness
        let gap = (t * 0.16).rounded()
        let titleSize = (t * 0.4).rounded()
        let authorSize = (t * 0.3).rounded()
        let author = book.author.flatMap { $0.isEmpty ? nil : $0 }
        // What the number, rules, dot and padding take; the title gets the rest.
        let fixed = t * 0.72 + t * 0.34 + t * 0.14 + gap * 5 + 1
        let authorLength = author == nil ? 0 : min(block.height * 0.24, authorSize * 1.04 * 4)
        VStack(spacing: gap) {
            Text(verbatim: String(format: "%02ld", number))
                .font(.system(size: t * 0.28, weight: .medium, design: .monospaced))
            Rectangle()
                .frame(width: t * 0.46, height: 0.75)
                .opacity(0.5)
            VerticalText(text: book.title, size: titleSize, weight: .bold,
                         length: block.height - fixed - authorLength)
            Spacer(minLength: 0)
            if let author {
                VerticalText(text: author, size: authorSize, weight: .medium, length: authorLength)
                    .opacity(0.72)
            }
            Rectangle()
                .frame(width: t * 0.14, height: t * 0.14)
        }
        .foregroundStyle(palette.ink)
        .padding(.vertical, t * 0.36)
        .frame(width: t, height: block.height)
        .clipped()
        .background {
            LinearGradient(colors: [palette.boardLight, palette.board], startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .leading) {
            palette.ink.opacity(0.12).frame(width: 0.75)
        }
    }
}

/// The front cover: an archive board with the shelf number, the cover art (or the title set in
/// type when the book has none) and the serial.
private struct CoverFace: View {
    let book: Book
    let image: UIImage?
    let number: Int
    let palette: BookPalette
    let block: BookBlock

    var body: some View {
        let w = block.depth, h = block.height
        let inset = (w * 0.08).rounded()
        let code = Font.system(size: max(6, w * 0.058), weight: .medium, design: .monospaced)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: String(format: "NO.%03ld", number))
                .font(code)
                .tracking(1)
                .opacity(0.75)
                .frame(height: h * 0.1, alignment: .bottomLeading)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w - inset * 2, height: h * 0.76)
                    .clipped()
                    .padding(.top, h * 0.025)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(palette.ink.opacity(0.35))
                    .frame(height: 0.75)
                    .padding(.top, h * 0.03)
                Text(verbatim: book.title)
                    .font(.system(size: w * 0.13, weight: .bold))
                    .lineLimit(5)
                    .minimumScaleFactor(0.75)
                    .padding(.top, h * 0.05)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if image == nil, let author = book.author, !author.isEmpty {
                    Text(verbatim: author)
                        .font(.system(size: w * 0.072, weight: .medium))
                        .lineLimit(1)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Text(verbatim: BookSerial.make(book.id))
                    .font(.system(size: max(5, w * 0.048), weight: .regular, design: .monospaced))
                    .tracking(0.8)
                    .lineLimit(1)
                    .opacity(0.6)
            }
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, inset)
        .padding(.bottom, h * 0.04)
        .frame(width: w, height: h, alignment: .topLeading)
        .background(palette.board)
        // The hinge, a groove beside the spine.
        .overlay(alignment: .leading) {
            palette.shade.opacity(0.3)
                .frame(width: max(1, w * 0.02))
                .padding(.leading, w * 0.035)
        }
    }
}

/// The top of the book: the page block between the two boards, the spine along the front.
private struct TopFace: View {
    let palette: BookPalette
    let block: BookBlock

    var body: some View {
        let board = max(1, block.thickness * 0.07)
        HStack(spacing: 0) {
            palette.board.frame(width: board)
            palette.pages
            palette.board.frame(width: board)
        }
        .overlay(alignment: .bottom) {
            palette.boardLight.frame(height: board * 1.5)
        }
        .frame(width: block.thickness, height: block.depth)
    }
}

/// Spine lettering. Chinese and Japanese titles stack upright one character per row, with
/// vertical punctuation; Latin titles run rotated, reading top to bottom.
private struct VerticalText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let length: CGFloat

    var body: some View {
        let font = Font.system(size: size, weight: weight)
        let row = size * 1.04
        if Self.upright(text) {
            VStack(spacing: 0) {
                ForEach(Array(Self.glyphs(text, fitting: Int(max(length, 0) / row)).enumerated()),
                        id: \.offset) { _, glyph in
                    Text(verbatim: glyph)
                        .font(font)
                        .frame(height: row)
                }
            }
        } else {
            Text(verbatim: text)
                .font(font)
                .lineLimit(1)
                .frame(width: max(length, 0), height: size * 1.3, alignment: .leading)
                .rotationEffect(.degrees(90))
                .frame(width: size * 1.3, height: max(length, 0))
        }
    }

    static func upright(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF: true
            default: false
            }
        }
    }

    static func glyphs(_ text: String, fitting count: Int) -> [String] {
        let all = text.filter { !$0.isWhitespace }.map { String(vertical[$0] ?? $0) }
        guard all.count > count else { return all }
        return Array(all.prefix(max(count - 1, 0))) + ["︙"]
    }

    private static let vertical: [Character: Character] = [
        "，": "︐", "、": "︑", "。": "︒", "：": "︓", "；": "︔", "！": "︕", "？": "︖",
        "（": "︵", "）": "︶", "《": "︽", "》": "︾", "「": "﹁", "」": "﹂", "『": "﹃", "』": "﹄",
        "【": "︻", "】": "︼", "…": "︙", "—": "︱", ":": "︓", "!": "︕", "?": "︖", "(": "︵", ")": "︶",
    ]
}

/// The last-read bookmark: a ribbon with a swallowtail end.
private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.7))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
