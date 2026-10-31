import Foundation

/// Keys that recognise a new download of a book already in the library (spec §8.4).
public enum BookIdentity {
    /// SoNovel writes the source page URL as `dc:identifier`, which stays the same across downloads.
    public static func identifierKey(_ identifier: String?) -> String? {
        guard let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public static func titleAuthorKey(title: String, author: String?) -> String {
        TitleNormalizer.normalize(title) + "|" + TitleNormalizer.normalize(author ?? "")
    }
}
