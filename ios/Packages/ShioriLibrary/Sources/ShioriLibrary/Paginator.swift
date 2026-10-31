import CoreGraphics
import CoreText
import Foundation

/// Paginates one chapter at a time with Core Text (spec §7.3): never the whole book, so a
/// 4,834-chapter book opens as fast as one chapter lays out. Thread-safe.
public final class Paginator: Sendable {
    private let cache: PaginationCache

    public init(cache: PaginationCache) {
        self.cache = cache
    }

    public func layout(_ content: ChapterContent, key: PaginationKey) -> ChapterLayout {
        // A book update or a TXT re-split can change a chapter behind the same key.
        if let cached = cache.layout(for: key), cached.content == content { return cached }
        let layout = Self.paginate(content, typography: key.typography, size: key.size)
        cache.store(layout, for: key)
        return layout
    }

    static func paginate(_ content: ChapterContent, typography: ReaderTypography, size: PageSize) -> ChapterLayout {
        let text = TypographyAttributes.attributed(content, typography)
        let margins = TypographyAttributes.margins(typography)
        let width = CGFloat(size.width - margins.left - margins.right)
        let height = CGFloat(size.height - margins.top - margins.bottom)
        let textRect = CGRect(x: margins.left, y: margins.top, width: max(width, 0), height: max(height, 0))
        // Core Text's y axis points up, so the path starts at the bottom margin.
        let box = CGRect(x: margins.left, y: margins.bottom, width: textRect.width, height: textRect.height)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let length = text.length

        func finish(_ pages: [Page], _ frames: [CTFrame]) -> ChapterLayout {
            ChapterLayout(content: content, attributedText: text, size: size, textRect: textRect,
                          pages: pages, frames: frames)
        }

        guard width >= CGFloat(typography.size), height >= CGFloat(typography.size) else {
            // A view's first layout pass can report a zero size. Cutting a page per character
            // would cost seconds for nothing, so it gets one page until the real size arrives.
            let empty = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                                 CGPath(rect: .zero, transform: nil), nil)
            return finish([Page(index: 0, range: 0..<length)], [empty])
        }

        let path = CGPath(rect: box, transform: nil)
        var pages: [Page] = []
        var frames: [CTFrame] = []
        var start = 0
        repeat {
            var frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            var count = CTFrameGetVisibleStringRange(frame).length
            if count == 0, start < length {
                // A line taller than the page gets a page of its own and overflows the bottom margin.
                let typesetter = CTFramesetterGetTypesetter(framesetter)
                count = min(max(CTTypesetterSuggestLineBreak(typesetter, start, Double(width)), 1), length - start)
                let overflow = CGRect(x: box.minX, y: box.maxY - 100_000, width: box.width, height: 100_000)
                frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: count),
                                                 CGPath(rect: overflow, transform: nil), nil)
            }
            pages.append(Page(index: pages.count, range: start..<(start + count)))
            frames.append(frame)
            start += count
        } while start < length
        return finish(pages, frames)
    }
}
