import Foundation

/// Identifies a chapter across re-imports and re-splits of the same book, where indexes
/// shift (spec §7.3): the normalised title plus how many earlier chapters share it.
public struct ChapterKey: Hashable, Codable, Sendable {
    public var title: String
    public var occurrence: Int

    public init(title: String, occurrence: Int) {
        self.title = title
        self.occurrence = occurrence
    }
}

public enum ChapterKeys {
    public static func make(titles: [String]) -> [ChapterKey] {
        var seen: [String: Int] = [:]
        return titles.map { raw in
            let title = TitleNormalizer.normalize(raw)
            let occurrence = seen[title, default: 0]
            seen[title] = occurrence + 1
            return ChapterKey(title: title, occurrence: occurrence)
        }
    }
}
