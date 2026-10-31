import Foundation

/// Turns the spine into chapters, titled from the contents.
public enum EPUBChapterList {
    private struct Match {
        var depth: Int
        var title: String
        var volume: String?
    }

    public static func build(spine: [String], toc: [TOCEntry]) -> [ChapterEntry] {
        var matches: [String: Match] = [:]

        // A spine item takes the deepest entry pointing at it; at equal depth the first
        // in reading order wins, which pre-order traversal gives for free.
        func visit(_ entry: TOCEntry, depth: Int, volume: String?) {
            if !entry.path.isEmpty, !entry.title.isEmpty,
               matches[entry.path].map({ depth > $0.depth }) ?? true {
                matches[entry.path] = Match(depth: depth, title: entry.title, volume: volume)
            }
            for child in entry.children {
                visit(child, depth: depth + 1, volume: volume ?? entry.title)
            }
        }
        for entry in toc { visit(entry, depth: 0, volume: nil) }

        var previousVolume: String?
        return spine.enumerated().map { index, path in
            if let match = matches[path] {
                previousVolume = match.volume
                return ChapterEntry(index: index, path: path, title: match.title, volume: match.volume)
            }
            return ChapterEntry(index: index, path: path, title: "", volume: previousVolume)
        }
    }
}
