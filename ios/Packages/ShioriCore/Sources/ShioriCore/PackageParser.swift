import Foundation

/// Reads the OPF package document: metadata, manifest and spine.
public enum PackageParser {
    private struct Item {
        var path: String
        var mediaType: String
        var properties: Set<Substring>
    }

    public static func parse(_ data: Data, packagePath: String) throws -> EPUBPackage {
        let root: XMLTreeElement
        do {
            root = try XMLTree.parse(data)
        } catch let error as XMLTreeError {
            throw EPUBError.malformedPackage(error.message)
        }
        guard root.name == "package" else { throw EPUBError.malformedPackage("root is <\(root.name)>") }

        let metadataElement = root.children.first { $0.name == "metadata" }
        let metadata = metadataElement?.children ?? []
        let text = { (e: XMLTreeElement) in e.textContent.trimmingCharacters(in: .whitespacesAndNewlines) }

        let identifiers = metadata.filter { $0.name == "identifier" }
        let uniqueId = root.attribute("unique-identifier")
        let identifier = (identifiers.first { $0.attribute("id") == uniqueId } ?? identifiers.first)
            .map(text).flatMap { $0.isEmpty ? nil : $0 }

        let metas = metadataElement?.descendants("meta") ?? []
        let isFixedLayout = metas.contains {
            $0.attribute("property") == "rendition:layout" && text($0) == "pre-paginated"
        }

        var items: [String: Item] = [:]
        var itemOrder: [String] = []
        for element in root.children.first(where: { $0.name == "manifest" })?.children ?? [] where element.name == "item" {
            guard let id = element.attribute("id"), let href = element.attribute("href") else { continue }
            items[id] = Item(path: EPUBPath.resolve(href, relativeTo: packagePath),
                             mediaType: element.attribute("media-type") ?? "",
                             properties: Set((element.attribute("properties") ?? "").split(separator: " ")))
            itemOrder.append(id)
        }
        let ordered = itemOrder.compactMap { items[$0] }

        let coverId = metas.first { $0.attribute("name") == "cover" }?.attribute("content")
        let coverPath = ordered.first { $0.properties.contains("cover-image") }?.path
            ?? coverId.flatMap { items[$0]?.path }

        let spineElement = root.children.first { $0.name == "spine" }
        let ncxPath = spineElement?.attribute("toc").flatMap { items[$0]?.path }
            ?? ordered.first { $0.mediaType == "application/x-dtbncx+xml" }?.path

        let spine = (spineElement?.children ?? [])
            .filter { $0.name == "itemref" && $0.attribute("linear") != "no" }
            .compactMap { $0.attribute("idref").flatMap { items[$0]?.path } }
        guard !spine.isEmpty else { throw EPUBError.noSpine }

        return EPUBPackage(
            metadata: EPUBMetadata(
                title: metadata.first { $0.name == "title" }.map(text) ?? "",
                creators: metadata.filter { $0.name == "creator" }.map(text).filter { !$0.isEmpty },
                identifier: identifier,
                language: metadata.first { $0.name == "language" }.map(text),
                isFixedLayout: isFixedLayout),
            spine: spine,
            coverPath: coverPath,
            navPath: ordered.first { $0.properties.contains("nav") }?.path,
            ncxPath: ncxPath)
    }
}
