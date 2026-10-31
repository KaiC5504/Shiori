import Foundation

/// The comparison form of a title or name: full-width forms folded (NFKC), whitespace
/// collapsed, lowercased. Only used for matching, never shown.
public enum TitleNormalizer {
    public static func normalize(_ s: String) -> String {
        s.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}
