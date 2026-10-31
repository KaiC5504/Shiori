import Foundation

/// Reads an EPUB's contents from the EPUB 2 NCX or the EPUB 3 nav document.
public enum TOCParser {
    public static func ncx(_ data: Data, basePath: String) throws -> [TOCEntry] {
        let root = try tree(data)
        guard let navMap = root.firstDescendant("navMap") else { return [] }
        return navPoints(in: navMap, basePath: basePath)
    }

    /// Throws when the file is not well-formed or has no `toc` nav, so callers can fall back to the NCX.
    public static func nav(_ data: Data, basePath: String) throws -> [TOCEntry] {
        let root = try tree(data)
        let toc = root.descendants("nav").first {
            ($0.attribute("type") ?? "").split(separator: " ").contains("toc")
        }
        guard let toc else { throw EPUBError.malformedPackage("no toc nav") }
        guard let list = toc.firstDescendant("ol") else { return [] }
        return listItems(in: list, basePath: basePath)
    }

    private static func tree(_ data: Data) throws -> XMLTreeElement {
        do {
            return try XMLTree.parse(data)
        } catch let error as XMLTreeError {
            throw EPUBError.malformedPackage(error.message)
        }
    }

    private static func navPoints(in parent: XMLTreeElement, basePath: String) -> [TOCEntry] {
        parent.children.filter { $0.name == "navPoint" }.map { point in
            let label = point.children.first { $0.name == "navLabel" }?.firstDescendant("text")
            let src = point.children.first { $0.name == "content" }?.attribute("src") ?? ""
            return entry(title: label?.textContent ?? "", href: src, basePath: basePath,
                         children: navPoints(in: point, basePath: basePath))
        }
    }

    private static func listItems(in list: XMLTreeElement, basePath: String) -> [TOCEntry] {
        list.children.filter { $0.name == "li" }.map { item in
            let label = item.children.first { $0.name == "a" || $0.name == "span" }
            let href = label?.name == "a" ? label?.attribute("href") ?? "" : ""
            let children = item.children.first { $0.name == "ol" }.map { listItems(in: $0, basePath: basePath) } ?? []
            return entry(title: label?.textContent ?? "", href: href, basePath: basePath, children: children)
        }
    }

    private static func entry(title: String, href: String, basePath: String, children: [TOCEntry]) -> TOCEntry {
        let fragment = EPUBPath.split(href).fragment
        return TOCEntry(title: collapseWhitespace(title),
                        path: href.isEmpty ? "" : EPUBPath.resolve(href, relativeTo: basePath),
                        fragment: fragment,
                        children: children)
    }

    static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
