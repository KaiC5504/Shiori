#if canImport(FoundationXML)
import FoundationXML
#endif
import Foundation

/// A minimal element tree. OPF, NCX and nav files are at most a few MB even for a
/// 5,000-chapter book, and their nesting is far easier to read from a tree than from
/// parser callbacks.
final class XMLTreeElement {
    enum Content {
        case text(String)
        case element(XMLTreeElement)
    }

    /// The local name: `dc:title` is stored as `title`.
    let name: String
    let attributes: [String: String]
    private(set) var content: [Content] = []
    private(set) var children: [XMLTreeElement] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    fileprivate func append(_ child: XMLTreeElement) {
        content.append(.element(child))
        children.append(child)
    }

    fileprivate func append(text: String) {
        if case .text(let previous) = content.last {
            content[content.count - 1] = .text(previous + text)
        } else {
            content.append(.text(text))
        }
    }

    var textContent: String {
        content.map {
            switch $0 {
            case .text(let s): s
            case .element(let e): e.textContent
            }
        }.joined()
    }

    /// Looks an attribute up by its qualified name, else by local name (`type` finds `epub:type`).
    func attribute(_ name: String) -> String? {
        if let value = attributes[name] { return value }
        return attributes.first { $0.key.hasSuffix(":" + name) }?.value
    }

    func firstDescendant(_ name: String) -> XMLTreeElement? {
        for child in children {
            if child.name == name { return child }
            if let found = child.firstDescendant(name) { return found }
        }
        return nil
    }

    func descendants(_ name: String) -> [XMLTreeElement] {
        var result: [XMLTreeElement] = []
        collect(name, into: &result)
        return result
    }

    private func collect(_ name: String, into result: inout [XMLTreeElement]) {
        for child in children {
            if child.name == name { result.append(child) }
            child.collect(name, into: &result)
        }
    }
}

struct XMLTreeError: Error, Equatable {
    var message: String
}

enum XMLTree {
    static func parse(_ data: Data) throws -> XMLTreeElement {
        let parser = XMLParser(data: data)
        // External DTDs (NCX files name one) would mean a network fetch; Shiori makes none.
        parser.shouldResolveExternalEntities = false
        let builder = Builder()
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw XMLTreeError(message: parser.parserError.map { "\($0)" } ?? "no root element")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLTreeElement?
        private var stack: [XMLTreeElement] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            let element = XMLTreeElement(name: local, attributes: attributeDict)
            if let parent = stack.last {
                parent.append(element)
            } else if root == nil {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.append(text: string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.append(text: String(decoding: CDATABlock, as: UTF8.self))
        }
    }
}
