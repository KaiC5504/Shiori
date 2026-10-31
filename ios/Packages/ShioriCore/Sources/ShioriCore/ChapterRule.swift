import Foundation

/// A TXT heading rule. A line is a heading when the rule's pattern matches the whole trimmed line.
public struct ChapterRule: Codable, Hashable, Sendable {
    public var id: String
    public var pattern: String
    /// Volume lines group the chapters after them instead of starting a chapter.
    public var isVolume: Bool

    public init(id: String, pattern: String, isVolume: Bool) {
        self.id = id
        self.pattern = pattern
        self.isVolume = isVolume
    }

    private static let zhNumber = "[0-9０-９零〇一二两三四五六七八九十百千万]+"
    // The unit must be followed by a separator or the end of the line, so
    // sentences like "第一节课是数学课。" are not headings.
    private static let zhTail = #"(?:[\s:：·、.．\-—].{0,40})?$"#

    /// Tried in this order; the first rule that matches a line wins. The splitter only applies
    /// `numbered` when no line matches `zh-chapter` or `en-chapter`.
    public static let presets: [ChapterRule] = [
        ChapterRule(id: "zh-chapter", pattern: "^第\(zhNumber)[章回节话集]" + zhTail, isVolume: false),
        ChapterRule(id: "zh-volume", pattern: "^第\(zhNumber)[卷部]" + zhTail, isVolume: true),
        ChapterRule(id: "en-chapter", pattern: #"^(?i:chapter)\s*\d+.{0,60}$"#, isVolume: false),
        ChapterRule(id: "numbered", pattern: #"^\d{1,5}[.、．]\s*\S.{0,40}$"#, isVolume: false),
    ]
}
