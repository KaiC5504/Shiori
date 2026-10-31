import Foundation
import ShioriCore
import SwiftSoup

/// Turns chapter XHTML into blocks. It parses as HTML, not XML: real chapter files carry
/// `&nbsp;` and tags that aren't well-formed, which a strict XML parser would reject.
public enum XHTMLContentParser {
    public static func blocks(from html: String, documentPath: String) throws -> [ChapterBlock] {
        // A BOM before `<?xml` would otherwise become body text.
        let document = try SwiftSoup.parse(html.hasPrefix("\u{FEFF}") ? String(html.dropFirst()) : html)
        guard let body = document.body() else { return [] }
        var collector = Collector(documentPath: documentPath)
        collector.visitChildren(of: body)
        collector.flush()
        return collector.blocks
    }

    private static let blockTags: Set<String> = [
        "p", "div", "li", "ul", "ol", "dl", "dt", "dd", "blockquote", "section", "article", "aside",
        "header", "footer", "nav", "main", "figure", "figcaption", "table", "thead", "tbody", "tfoot",
        "tr", "td", "th", "pre", "hr", "center", "address",
    ]
    private static let skippedTags: Set<String> = ["script", "style", "head", "title", "noscript"]

    /// Walks the tree once, gathering inline text into a pending paragraph that block
    /// boundaries and `<br>` cut.
    private struct Collector {
        let documentPath: String
        var blocks: [ChapterBlock] = []
        var pending = ""

        init(documentPath: String) {
            self.documentPath = documentPath
        }

        mutating func flush() {
            let text = XHTMLContentParser.clean(pending)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            pending = ""
        }

        mutating func visitChildren(of element: Element) {
            for node in element.getChildNodes() { visit(node) }
        }

        mutating func visit(_ node: Node) {
            if let text = node as? TextNode {
                pending += text.getWholeText()
                return
            }
            guard let element = node as? Element else { return }
            let tag = element.tagName().lowercased()
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush()
                let text = XHTMLContentParser.clean(XHTMLContentParser.inlineText(of: element))
                if !text.isEmpty { blocks.append(.heading(text, level: Int(String(tag.last!)) ?? 2)) }
            case "br":
                flush()
            case "img", "image":
                flush()
                let href = [ "src", "xlink:href", "href"].lazy
                    .compactMap { try? element.attr($0) }
                    .first { !$0.isEmpty }
                if let href, !href.hasPrefix("data:"), !href.contains("://") {
                    blocks.append(.image(path: EPUBPath.resolve(href, relativeTo: documentPath)))
                }
            case _ where XHTMLContentParser.skippedTags.contains(tag):
                return
            case _ where XHTMLContentParser.blockTags.contains(tag):
                flush()
                visitChildren(of: element)
                flush()
            default:
                visitChildren(of: element)
            }
        }
    }

    /// Text of an element with `<br>` read as a space, for headings.
    private static func inlineText(of element: Element) -> String {
        var text = ""
        for node in element.getChildNodes() {
            if let t = node as? TextNode {
                text += t.getWholeText()
            } else if let e = node as? Element {
                text += e.tagName().lowercased() == "br" ? " " : inlineText(of: e)
            }
        }
        return text
    }

    /// Collapses runs of ASCII whitespace and no-break spaces to one space, then trims those
    /// and the full-width spaces web novels indent paragraphs with. Drops stray BOMs and
    /// zero-width spaces, which would otherwise make an invisible paragraph.
    static func clean(_ raw: String) -> String {
        var out = String.UnicodeScalarView()
        var inSpace = false
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\u{FEFF}", "\u{200B}":
                continue
            case " ", "\t", "\n", "\r", "\u{0C}", "\u{00A0}":
                inSpace = true
            default:
                if inSpace, !out.isEmpty { out.append(" ") }
                inSpace = false
                out.append(scalar)
            }
        }
        return String(out).trimmingCharacters(in: CharacterSet(charactersIn: " \u{3000}"))
    }
}
