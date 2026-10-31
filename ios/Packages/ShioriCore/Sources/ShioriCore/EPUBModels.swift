import Foundation

public enum EPUBError: Error, Equatable, Sendable {
    case missingContainer
    case malformedPackage(String)
    case noSpine
}

public struct EPUBMetadata: Equatable, Sendable {
    public var title: String
    public var creators: [String]
    public var identifier: String?
    public var language: String?
    public var isFixedLayout: Bool
}

public struct EPUBPackage: Equatable, Sendable {
    public var metadata: EPUBMetadata
    /// Archive paths of the linear spine items, in reading order.
    public var spine: [String]
    public var coverPath: String?
    public var navPath: String?
    public var ncxPath: String?
}

public struct TOCEntry: Equatable, Sendable {
    public var title: String
    /// Archive path, or "" for a heading that links nowhere (a nav `span`).
    public var path: String
    public var fragment: String?
    public var children: [TOCEntry]
}

public struct ChapterEntry: Equatable, Sendable {
    /// Position in the spine.
    public var index: Int
    public var path: String
    /// "" when no contents entry points at this spine item.
    public var title: String
    public var volume: String?
}
