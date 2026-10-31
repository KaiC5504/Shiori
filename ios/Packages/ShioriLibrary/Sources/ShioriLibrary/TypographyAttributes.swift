import CoreGraphics
import CoreText
import Foundation

/// Turns a chapter into the attributed string the paginator lays out. Its string is exactly
/// `ChapterContent.plainText`, so every page range is a range of reading-position offsets.
public enum TypographyAttributes {
    /// Han glyph shapes and fallback fonts follow Simplified Chinese whatever the phone's language.
    static let language = "zh-Hans"
    static let headingScale = 1.3

    public static func attributed(_ content: ChapterContent, _ t: ReaderTypography) -> NSAttributedString {
        let text = NSMutableAttributedString(string: content.plainText)
        let styles = Styles(t)
        for (index, block) in content.blocks.enumerated() {
            let start = content.offset(ofBlock: index)
            let end = index + 1 < content.blocks.count ? content.offset(ofBlock: index + 1) : text.length
            // The joining "\n" takes its block's attributes, so each paragraph is styled whole.
            text.setAttributes(styles.attributes(for: block), range: NSRange(location: start, length: end - start))
        }
        return text
    }

    /// The font family if it's installed, else the system font, at the typography's weight.
    public static func font(_ t: ReaderTypography, heading: Bool = false) -> CTFont {
        let size = CGFloat(max(t.size, 1) * (heading ? headingScale : 1))
        let weight = weightTrait(heading ? .bold : t.weight)
        if let family = t.fontFamily, let font = installed(family: family, size: size, weight: weight) {
            return font
        }
        let system = CTFontCreateUIFontForLanguage(.system, size, language as CFString)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        guard weight != 0 else { return system }
        let traits = [kCTFontTraitsAttribute as String: [kCTFontWeightTrait as String: weight]]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(system), traits as CFDictionary)
        let weighted = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if weight >= weightTrait(.bold), !CTFontGetSymbolicTraits(weighted).contains(.traitBold) {
            return CTFontCreateCopyWithSymbolicTraits(system, size, nil, .traitBold, .traitBold) ?? weighted
        }
        return weighted
    }

    /// Linked margins all take the left value.
    public static func margins(_ t: ReaderTypography) -> Margins {
        guard t.marginsLinked else { return t.margins }
        let value = t.margins.left
        return Margins(left: value, right: value, top: value, bottom: value)
    }

    private static func installed(family: String, size: CGFloat, weight: Double) -> CTFont? {
        let attributes: [String: Any] = [
            kCTFontFamilyNameAttribute as String: family,
            kCTFontTraitsAttribute as String: [kCTFontWeightTrait as String: weight],
        ]
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
        // Core Text substitutes a default font for a missing family rather than failing.
        return CTFontCopyFamilyName(font) as String == family ? font : nil
    }

    private static func weightTrait(_ weight: FontWeightChoice) -> Double {
        switch weight {
        case .regular: 0
        case .medium: 0.23
        case .bold: 0.4
        }
    }

    private struct Styles {
        let heading: [NSAttributedString.Key: Any]
        let indented: [NSAttributedString.Key: Any]
        let flush: [NSAttributedString.Key: Any]
        let image: [NSAttributedString.Key: Any]
        let indents: Bool

        init(_ t: ReaderTypography) {
            let size = CGFloat(max(t.size, 1))
            let lineHeight = CGFloat(max(t.lineHeight, 1))
            let gap = CGFloat(t.paragraphGap ?? t.size * 0.6)
            let alignment: CTTextAlignment = t.justify ? .justified : .natural
            var base: [NSAttributedString.Key: Any] = [.ctLanguage: TypographyAttributes.language]
            if t.letterSpacing != 0 { base[.ctKern] = t.letterSpacing }

            func with(_ font: CTFont, _ style: CTParagraphStyle, inkFromContext: Bool = true) -> [NSAttributedString.Key: Any] {
                var attributes = base
                attributes[.ctFont] = font
                attributes[.ctParagraphStyle] = style
                // The view sets the ink colour on the context, so a theme change needs no relayout.
                if inkFromContext { attributes[.ctInkFromContext] = true }
                return attributes
            }

            let body = TypographyAttributes.font(t)
            let headingSize = size * CGFloat(TypographyAttributes.headingScale)
            heading = with(TypographyAttributes.font(t, heading: true),
                           Self.style(.natural, indent: 0, lineHeight: headingSize * lineHeight, after: max(gap, size)))
            indented = with(body, Self.style(alignment, indent: 2 * size, lineHeight: size * lineHeight, after: gap))
            flush = with(body, Self.style(alignment, indent: 0, lineHeight: size * lineHeight, after: gap))
            // A one-line placeholder until illustrations are drawn; clear so U+FFFC's glyph never shows.
            var placeholder = with(body, Self.style(.center, indent: 0, lineHeight: size * lineHeight, after: gap),
                                   inkFromContext: false)
            placeholder[.ctInk] = CGColor(gray: 0, alpha: 0)
            image = placeholder
            indents = t.firstLineIndent
        }

        func attributes(for block: ChapterBlock) -> [NSAttributedString.Key: Any] {
            switch block {
            case .heading: heading
            // Text that already starts with ideographic spaces would otherwise be indented twice.
            case .paragraph(let text): indents && text.first?.isWhitespace != true ? indented : flush
            case .image: image
            }
        }

        private static func style(_ alignment: CTTextAlignment, indent: CGFloat, lineHeight: CGFloat,
                                  after: CGFloat) -> CTParagraphStyle {
            withUnsafePointer(to: alignment) { alignment in
                withUnsafePointer(to: indent) { indent in
                    withUnsafePointer(to: lineHeight) { lineHeight in
                        withUnsafePointer(to: after) { after in
                            let float = MemoryLayout<CGFloat>.size
                            let settings = [
                                CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                                        value: alignment),
                                CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: float, value: indent),
                                // Equal minimum and maximum give every line the same height, whatever the fallback font.
                                CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: float, value: lineHeight),
                                CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: float, value: lineHeight),
                                CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: float, value: after),
                            ]
                            return CTParagraphStyleCreate(settings, settings.count)
                        }
                    }
                }
            }
        }
    }
}

private extension NSAttributedString.Key {
    static let ctFont = NSAttributedString.Key(kCTFontAttributeName as String)
    static let ctParagraphStyle = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)
    static let ctKern = NSAttributedString.Key(kCTKernAttributeName as String)
    static let ctLanguage = NSAttributedString.Key(kCTLanguageAttributeName as String)
    static let ctInk = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    static let ctInkFromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
}
