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
