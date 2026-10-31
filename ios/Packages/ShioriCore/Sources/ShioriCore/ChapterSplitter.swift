import Foundation

public struct TextChapter: Equatable, Sendable {
    /// "" for text that sits under no heading, such as a preface.
    public var title: String
    public var volume: String?
    /// Trimmed, non-empty lines joined with "\n"; the heading line is not included.
    public var body: String
}

public enum ChapterSplitter {
    /// Windows TXT files indent paragraphs with full-width spaces (U+3000), which
    /// `.whitespaces` covers along with tabs and no-break spaces.
    private static let trimmed = CharacterSet.whitespaces

    public static func split(_ text: String, rules: [ChapterRule], fallbackLength: Int = 20_000) -> [TextChapter] {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: trimmed) }
            .filter { !$0.isEmpty }

        let compiled = rules.compactMap { rule in
            (try? NSRegularExpression(pattern: rule.pattern)).map { (regex: $0, isVolume: rule.isVolume) }
        }
        func headingKind(_ line: String) -> Bool? {
            let whole = NSRange(line.startIndex..., in: line)
            for rule in compiled where rule.regex.firstMatch(in: line, range: whole)?.range == whole {
                return rule.isVolume
            }
            return nil
        }

        var chapters: [TextChapter] = []
        var volume: String?
        var sectionTitle: String?
        var sectionVolume: String?
        var body: [String] = []
        var sawHeading = false

        func flush() {
            if sectionTitle != nil || !body.isEmpty {
                chapters.append(TextChapter(title: sectionTitle ?? "", volume: sectionVolume,
                                            body: body.joined(separator: "\n")))
            }
            body = []
        }

        for line in lines {
            switch headingKind(line) {
            case true?:
                sawHeading = true
                flush()
                volume = line
                sectionTitle = nil
                sectionVolume = volume
            case false?:
                sawHeading = true
                flush()
                sectionTitle = line
                sectionVolume = volume
            case nil:
                body.append(line)
            }
        }
        guard sawHeading else { return parts(of: lines, maxLength: fallbackLength) }
        flush()
        return chapters
    }

    /// Cuts heading-less text into untitled parts at line boundaries.
    private static func parts(of lines: [String], maxLength: Int) -> [TextChapter] {
        var parts: [TextChapter] = []
        var current: [String] = []
        var length = 0
        for line in lines {
            let added = line.count + (current.isEmpty ? 0 : 1)
            if !current.isEmpty, length + added > maxLength {
                parts.append(TextChapter(title: "", volume: nil, body: current.joined(separator: "\n")))
                current = []
                length = 0
            }
            length += line.count + (current.isEmpty ? 0 : 1)
            current.append(line)
        }
        if !current.isEmpty {
            parts.append(TextChapter(title: "", volume: nil, body: current.joined(separator: "\n")))
        }
        return parts
    }
}
