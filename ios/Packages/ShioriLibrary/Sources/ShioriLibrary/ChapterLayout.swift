import CoreGraphics
import CoreText
import Foundation

public struct PageSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }
}

public struct Page: Equatable, Sendable {
    public var index: Int
    /// UTF-16 offsets into the chapter's `plainText`, the same space as `Progress.offset`.
    public var range: Range<Int>

    public init(index: Int, range: Range<Int>) {
        self.index = index
        self.range = range
    }
}

public struct PageLine {
    public let line: CTLine
    /// The baseline origin in Core Text's page coordinates (origin bottom-left, y up), the
    /// space `frame(forPage:)` draws in: for `CTLineDraw` after the same flip.
    public let origin: CGPoint
    public let range: Range<Int>
    /// The `ChapterContent` block the line belongs to.
    public let block: Int
    /// The line's glyph box in page coordinates with a top-left origin, as UIKit lays out views.
    public let bounds: CGRect
}

public struct PageParagraph {
    public let block: Int
    public let lines: [PageLine]

    public var bounds: CGRect {
        lines.reduce(CGRect.null) { $0.union($1.bounds) }
    }
}

/// One chapter laid out for one typography and page size. Drawing uses these same frames,
/// so what was measured is what's shown. Text takes its colour from the context's fill colour.
///
/// To draw a page in a view of `size`: set the text matrix to identity, flip the context
/// (translate by the height, scale y by -1), then `CTFrameDraw(frame(forPage:), context)`.
public final class ChapterLayout: @unchecked Sendable {
    public let content: ChapterContent
    public let attributedText: NSAttributedString
    public let size: PageSize
    /// The area inside the margins, with a top-left origin.
    public let textRect: CGRect
    /// Never empty; they tile `0..<plainText.utf16.count` in order.
    public let pages: [Page]
    private let frames: [CTFrame]

    init(content: ChapterContent, attributedText: NSAttributedString, size: PageSize, textRect: CGRect,
         pages: [Page], frames: [CTFrame]) {
        self.content = content
        self.attributedText = attributedText
        self.size = size
        self.textRect = textRect
        self.pages = pages
        self.frames = frames
    }

    /// Offsets past either end land on the first or last page.
    public func page(containing offset: Int) -> Int {
        var low = 0
        var high = pages.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if pages[mid].range.lowerBound <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    public func frame(forPage index: Int) -> CTFrame {
        frames[clamped(index)]
    }

    public func lines(onPage index: Int) -> [PageLine] {
        let frame = frames[clamped(index)]
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        // Line origins are relative to the path's box, which sits inside the margins.
        let box = CTFrameGetPath(frame).boundingBox
        return zip(lines, origins).map { line, relative in
            let origin = CGPoint(x: box.minX + relative.x, y: box.minY + relative.y)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let range = CTLineGetStringRange(line)
            let start = range.location
            return PageLine(line: line, origin: origin, range: start..<(start + range.length),
                            block: content.block(containing: start),
                            bounds: CGRect(x: origin.x, y: CGFloat(size.height) - origin.y - ascent,
                                           width: CGFloat(width), height: ascent + descent))
        }
    }

    /// The page's lines grouped by the block they belong to, top to bottom.
    public func paragraphs(onPage index: Int) -> [PageParagraph] {
        var groups: [PageParagraph] = []
        var current: [PageLine] = []
        for line in lines(onPage: index) {
            if let last = current.last, last.block != line.block {
                groups.append(PageParagraph(block: last.block, lines: current))
                current = []
            }
            current.append(line)
        }
        if let last = current.last { groups.append(PageParagraph(block: last.block, lines: current)) }
        return groups
    }

    private func clamped(_ index: Int) -> Int {
        min(max(index, 0), frames.count - 1)
    }
}
