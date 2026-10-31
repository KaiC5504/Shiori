import Foundation

/// Filters a book's chapter titles for the contents search (spec §7.8).
public enum ChapterSearch {
    // Stub from the wave 3 contracts commit; R2 implements it.
    /// 0-based indices of matching chapters, in book order; "" matches all.
    public static func matches(_ query: String, titles: [String]) -> [Int] {
        Array(titles.indices)
    }
}
