import Foundation

public enum FontWeightChoice: String, Codable, CaseIterable, Sendable {
    case regular, medium, bold
}

public struct Margins: Codable, Hashable, Sendable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var bottom: Double

    public init(left: Double, right: Double, top: Double, bottom: Double) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }
}

/// Reader typography (spec §7.4). Ranges are the controls' limits; values outside them are clamped by the UI.
public struct ReaderTypography: Codable, Hashable, Sendable {
    /// nil is the system font.
    public var fontFamily: String?
    /// 10...27 pt.
    public var size: Double
    public var weight: FontWeightChoice
    /// -0.5...3 pt.
    public var letterSpacing: Double
    /// 1.3...2.2, a multiple of the font size.
    public var lineHeight: Double
    /// Each 0...80 pt.
    public var margins: Margins
    /// One value drives all four margins.
    public var marginsLinked: Bool
    /// 0...32 pt; nil keeps the book's own spacing.
    public var paragraphGap: Double?
    /// A 2 em indent on each paragraph's first line.
    public var firstLineIndent: Bool
    public var justify: Bool

    public init(fontFamily: String?, size: Double, weight: FontWeightChoice, letterSpacing: Double,
                lineHeight: Double, margins: Margins, marginsLinked: Bool, paragraphGap: Double?,
                firstLineIndent: Bool, justify: Bool) {
        self.fontFamily = fontFamily
        self.size = size
        self.weight = weight
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.margins = margins
        self.marginsLinked = marginsLinked
        self.paragraphGap = paragraphGap
        self.firstLineIndent = firstLineIndent
        self.justify = justify
    }

    public static let `default` = ReaderTypography(
        fontFamily: nil, size: 18, weight: .regular, letterSpacing: 0, lineHeight: 1.7,
        margins: Margins(left: 24, right: 24, top: 16, bottom: 16), marginsLinked: false,
        paragraphGap: 12, firstLineIndent: true, justify: true)
}
