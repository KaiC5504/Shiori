import Foundation

/// Reads `META-INF/container.xml`, which names the package (OPF) file.
public enum ContainerParser {
    public static func rootfilePath(from data: Data) throws -> String {
        guard let root = try? XMLTree.parse(data),
              let path = root.descendants("rootfile").lazy
                .compactMap({ $0.attribute("full-path") })
                .first(where: { !$0.isEmpty })
        else { throw EPUBError.missingContainer }
        return path
    }
}
