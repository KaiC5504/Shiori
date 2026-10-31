import Foundation

/// Paths inside an EPUB archive. Hrefs are URL references relative to the document that
/// holds them; archive paths are plain, decoded and rooted at the archive.
public enum EPUBPath {
    /// Resolves `href` against the folder of `documentPath`, dropping any fragment.
    public static func resolve(_ href: String, relativeTo documentPath: String) -> String {
        let raw = split(href).path
        // Decode after the fragment is gone, so an encoded "#" stays part of the name.
        let decoded = raw.removingPercentEncoding ?? raw
        var parts: [Substring] = []
        if !decoded.hasPrefix("/") {
            parts = documentPath.split(separator: "/", omittingEmptySubsequences: true).dropLast()
        }
        for part in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": _ = parts.popLast()
            default: parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }

    public static func split(_ href: String) -> (path: String, fragment: String?) {
        guard let hash = href.firstIndex(of: "#") else { return (href, nil) }
        let fragment = String(href[href.index(after: hash)...])
        return (String(href[..<hash]), fragment.isEmpty ? nil : fragment)
    }
}
