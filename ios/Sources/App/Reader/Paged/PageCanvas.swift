import CoreText
import ShioriCore
import ShioriLibrary
import UIKit

/// A page the paged layout can show: one page of a laid-out chapter, or the only page of a
/// chapter that couldn't be opened (`layout` nil).
struct PagedPage: Sendable {
    let chapter: Int
    let index: Int
    let layout: ChapterLayout?

    /// The page's first UTF-16 offset, the place `ReaderPosition` keeps.
    var offset: Int { layout?.pages[index].range.lowerBound ?? 0 }

    /// The page's plain text, without the placeholders pictures leave in it.
    var text: String? {
        guard let layout else { return nil }
        let range = layout.pages[index].range
        let text = (layout.content.plainText as NSString)
            .substring(with: NSRange(location: range.lowerBound, length: range.count))
        return text.replacingOccurrences(of: "\u{FFFC}", with: "")
    }
}

extension PagedPage: Equatable {
    // A new layout of the same chapter is a different page, even at the same index.
    static func == (a: PagedPage, b: PagedPage) -> Bool {
        a.chapter == b.chapter && a.index == b.index && a.layout === b.layout
    }
}

/// The reader's colours resolved for drawing, so pages can be drawn off the main actor.
struct PageStyle: Equatable, @unchecked Sendable {
    var paper: CGColor
    var ink: CGColor
    var secondaryInk: CGColor
    /// What a chapter that failed to load says, in the reader's language.
    var failure: String
    var scale: CGFloat

    static func == (a: PageStyle, b: PageStyle) -> Bool {
        CFEqual(a.paper, b.paper) && CFEqual(a.ink, b.ink) && CFEqual(a.secondaryInk, b.secondaryInk)
            && a.failure == b.failure && a.scale == b.scale
    }
}

struct PageTaps: Equatable {
    var layout: TapZoneLayout
    var bothSidesForward: Bool

    func action(at point: CGPoint, in size: CGSize) -> TapAction {
        TapZones.action(x: Double(point.x), y: Double(point.y), width: Double(size.width),
                        height: Double(size.height), layout: layout, bothSidesForward: bothSidesForward)
    }
}

enum PageRenderer {
    /// The page's text on a clear sheet the size of the page box. Safe off the main actor.
    static func image(of page: PagedPage, size: CGSize, style: PageStyle) -> CGImage? {
        let scale = max(style.scale, 1)
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // A bitmap context is already y-up like Core Text, so the frame draws without a flip.
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = .identity
        if let layout = page.layout {
            // Pins the layout's top to the page's while a new size is still being laid out.
            context.translateBy(x: 0, y: size.height - CGFloat(layout.size.height))
            context.setFillColor(style.ink)
            CTFrameDraw(layout.frame(forPage: page.index), context)
        } else {
            drawFailure(style, in: context, size: size)
        }
        return context.makeImage()
    }

    private static func drawFailure(_ style: PageStyle, in context: CGContext, size: CGSize) {
        guard let font = CTFontCreateUIFontForLanguage(.system, 17, nil) else { return }
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            let setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                                  value: pointer)
            return CTParagraphStyleCreate([setting], 1)
        }
        let text = NSAttributedString(string: style.failure, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.secondaryInk,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let width = size.width * 0.8
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        let box = CGRect(x: (size.width - width) / 2, y: ((size.height - fit.height) / 2).rounded(),
                         width: width, height: fit.height.rounded(.up))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: box, transform: nil), nil)
        CTFrameDraw(frame, context)
    }
}

/// One page on the theme's paper (spec §7.2): the curl's pages, and the relay's page at rest.
/// It's the page's accessibility element, labelled with the page's text, which is also where
/// the UI tests read the 〔N·P〕 markers.
final class PageCanvas: UIView {
    private(set) var page: PagedPage?
    /// The text as drawn, which the relay cuts into paragraphs.
    private(set) var image: CGImage?
    private var style: PageStyle?
    private var pageFrame: CGRect = .zero
    private let ink = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(ink)
        isAccessibilityElement = true
        accessibilityTraits = [.staticText, .causesPageTurn]
        accessibilityIdentifier = "paged.page"
    }

    required init?(coder: NSCoder) { nil }

    /// Off while the relay moves the text as paragraphs; the paper stays.
    var showsText: Bool {
        get { !ink.isHidden }
        set { CATransaction.withoutActions { ink.isHidden = !newValue } }
    }

    /// `pageFrame` is the page box (the size the chapter was laid out at) in this view.
    /// `prerendered` skips drawing when the caller already has this page's image.
    func show(_ page: PagedPage?, style: PageStyle, in pageFrame: CGRect, prerendered: CGImage? = nil) {
        backgroundColor = UIColor(cgColor: style.paper)
        if page != self.page || style != self.style || pageFrame.size != self.pageFrame.size || image == nil {
            image = prerendered ?? page.flatMap { PageRenderer.image(of: $0, size: pageFrame.size, style: style) }
            accessibilityLabel = page.map { $0.text ?? style.failure }
        }
        self.page = page
        self.style = style
        self.pageFrame = pageFrame
        let scale = max(style.scale, 1)
        CATransaction.withoutActions {
            ink.contents = image
            ink.contentsScale = scale
            // Sized from the image rather than the frame, so nothing is ever stretched.
            ink.frame = CGRect(origin: pageFrame.origin,
                               size: image.map { CGSize(width: CGFloat($0.width) / scale,
                                                        height: CGFloat($0.height) / scale) } ?? .zero)
        }
    }
}

extension CATransaction {
    static func withoutActions(_ changes: () -> Void) {
        begin()
        setDisableActions(true)
        changes()
        commit()
    }
}
