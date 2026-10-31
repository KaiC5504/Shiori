import Foundation

public enum EPUBError: Error, Equatable, Sendable {
    case missingContainer
    case malformedPackage(String)
    case noSpine
}
