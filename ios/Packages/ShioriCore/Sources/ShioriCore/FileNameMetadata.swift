import Foundation

/// Title and author from a download's file name, for TXT files and EPUBs without a title.
/// Handles "书名(作者)", "书名（作者）" and "《书名》作者：作者".
public struct FileNameMetadata: Equatable, Sendable {
    public var title: String
    public var author: String?

    public init(title: String, author: String?) {
        self.title = title
        self.author = author
    }

    public static func parse(_ fileName: String) -> FileNameMetadata {
        let name = stripExtension(fileName).trimmingCharacters(in: .whitespaces)

        for marker in ["作者：", "作者:"] {
            if let range = name.range(of: marker) {
                let author = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let title = unquote(name[..<range.lowerBound].trimmingCharacters(in: .whitespaces))
                if !title.isEmpty {
                    return FileNameMetadata(title: title, author: author.isEmpty ? nil : author)
                }
            }
        }
        if name.hasPrefix("《"), let close = name.firstIndex(of: "》") {
            let title = String(name[name.index(after: name.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                return FileNameMetadata(title: title, author: nil)
            }
        }
        if let (title, author) = splitTrailingAuthor(name) {
            return FileNameMetadata(title: title, author: author)
        }
        return FileNameMetadata(title: name, author: nil)
    }

    /// Only drops an extension with a letter in it, so "Vol.1" keeps its number.
    private static func stripExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot > name.startIndex else { return name }
        let ext = name[name.index(after: dot)...]
        guard (1...5).contains(ext.count), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              ext.contains(where: \.isLetter) else { return name }
        return String(name[..<dot])
    }

    private static func unquote(_ s: String) -> String {
        guard s.hasPrefix("《"), s.hasSuffix("》"), s.count >= 2 else { return s }
        return String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// A trailing "(…)" or "（…）" is the author unless it looks like a volume number.
    private static func splitTrailingAuthor(_ name: String) -> (String, String)? {
        for (open, close) in [("(", ")"), ("（", "）")] {
            guard name.hasSuffix(close), let start = name.range(of: open, options: .backwards) else { continue }
            let inner = name[start.upperBound..<name.index(before: name.endIndex)]
                .trimmingCharacters(in: .whitespaces)
            let title = name[..<start.lowerBound].trimmingCharacters(in: .whitespaces)
            guard (1...20).contains(inner.count), !title.isEmpty,
                  inner.range(of: #"^\d+$|^(?i:vol|卷)"#, options: .regularExpression) == nil
            else { return nil }
            return (title, inner)
        }
        return nil
    }
}
