import Foundation

/// Filters a book's chapter titles for the contents search (spec §7.8).
public enum ChapterSearch {
    /// 0-based indices of matching chapters; "" matches all. A number (Arabic, full-width or
    /// Chinese, alone or as 第N章) lists the chapter at position N first, then the titles
    /// numbered 第N章/节/回, then every title containing the text, each group in book order.
    public static func matches(_ query: String, titles: [String]) -> [Int] {
        Index(titles: titles).matches(query)
    }

    /// The titles folded and numbered once, so searching as you type only scans them.
    public struct Index: Sendable {
        private let folded: [String]
        private let numbers: [Int?]

        public init(titles: [String]) {
            folded = titles.map(TitleNormalizer.normalize)
            numbers = folded.map(ChapterSearch.chapterNumber(in:))
        }

        public func matches(_ query: String) -> [Int] {
            let needle = TitleNormalizer.normalize(query)
            guard !needle.isEmpty else { return Array(folded.indices) }
            var listed = [Bool](repeating: false, count: folded.count)
            var result: [Int] = []
            func add(_ index: Int) {
                guard !listed[index] else { return }
                listed[index] = true
                result.append(index)
            }
            if let n = ChapterSearch.queryNumber(needle) {
                if n >= 1, n <= folded.count { add(n - 1) }
                for (index, number) in numbers.enumerated() where number == n { add(index) }
            }
            for (index, title) in folded.enumerated() where title.contains(needle) { add(index) }
            return result
        }
    }

    private static let chapterUnits: Set<Character> = ["章", "节", "回", "话", "集"]
    private static let digits: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]

    private static func isNumeral(_ character: Character) -> Bool {
        (character.isASCII && character.isWholeNumber) || digits[character] != nil
            || units[character] != nil || character == "万"
    }

    /// The N of the first 第N章/节/回/话/集 in a folded title. 第N卷 is a volume and is skipped.
    static func chapterNumber(in title: String) -> Int? {
        var rest = Substring(title)
        while let mark = rest.firstIndex(of: "第") {
            let after = rest.index(after: mark)
            let numeral = rest[after...].prefix(while: isNumeral)
            if !numeral.isEmpty, numeral.endIndex < rest.endIndex,
               chapterUnits.contains(rest[numeral.endIndex]) {
                return number(numeral)
            }
            rest = rest[after...]
        }
        return nil
    }

    /// A folded query read as a chapter number: "12", "十二", "第12章" or "第十二".
    static func queryNumber(_ needle: String) -> Int? {
        var text = Substring(needle)
        if text.first == "第" { text = text.dropFirst() }
        if let last = text.last, chapterUnits.contains(last) { text = text.dropLast() }
        return number(text)
    }

    /// Arabic digits, or a Chinese numeral up to the 万s: 十二, 三千六百二十五, 一百零五, 二〇二四.
    static func number<S: StringProtocol>(_ text: S) -> Int? {
        guard !text.isEmpty, text.count <= 18 else { return nil }
        if text.allSatisfy({ $0.isASCII && $0.isWholeNumber }) { return Int(text) }
        guard text.allSatisfy(isNumeral) else { return nil }
        // Written digit by digit, like a year: 二〇二四.
        if !text.contains(where: { units[$0] != nil || $0 == "万" }) {
            return text.reduce(0) { value, character in value * 10 + (digits[character] ?? 0) }
        }
        var total = 0
        var section = 0
        var digit: Int?
        for character in text {
            if let value = digits[character] {
                // 零 only marks a gap: 一千零十 is 1010, not 1000 + 0 × 10.
                digit = value == 0 ? nil : value
            } else if let unit = units[character] {
                // A unit with no digit before it counts once: 十二 is 12.
                section += (digit ?? 1) * unit
                digit = nil
            } else if character == "万" {
                let part = section + (digit ?? 0)
                total += (part == 0 ? 1 : part) * 10_000
                section = 0
                digit = nil
            } else {
                return nil
            }
        }
        return total + section + (digit ?? 0)
    }
}
