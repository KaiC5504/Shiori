import Foundation
import ZIPFoundation

public enum EPUBArchiveError: Error, Equatable {
    case missingEntry(String)
}

/// Read access to an EPUB's ZIP container. ZIPFoundation's own lookup scans the central
/// directory on every call, which is quadratic over a 5,000-chapter book, so entries are
/// indexed once up front.
public final class EPUBArchive: @unchecked Sendable {
    private let archive: Archive
    private let entries: [String: Entry]
    // Archive reads through one file handle, so calls must not overlap.
    private let lock = NSLock()

    /// Font obfuscation is the only use of encryption.xml that isn't DRM.
    private static let fontObfuscation: Set<String> = [
        "http://www.idpf.org/2008/embedding",
        "http://ns.adobe.com/pdf/enc#RC",
    ]

    public init(url: URL) throws {
        archive = try Archive(url: url, accessMode: .read)
        var entries: [String: Entry] = [:]
        for entry in archive where entry.type == .file {
            entries[entry.path] = entry
        }
        self.entries = entries
    }

    public func contains(_ path: String) -> Bool {
        entries[path] != nil
    }

    public func data(at path: String) throws -> Data {
        guard let entry = entries[path] else { throw EPUBArchiveError.missingEntry(path) }
        lock.lock()
        defer { lock.unlock() }
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry, skipCRC32: true) { data.append($0) }
        return data
    }

    public var hasDRM: Bool {
        guard let data = try? data(at: "META-INF/encryption.xml") else { return false }
        let xml = String(decoding: data, as: UTF8.self)
        let regex = try! NSRegularExpression(pattern: #"Algorithm\s*=\s*["']([^"']+)["']"#)
        let algorithms = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap {
            Range($0.range(at: 1), in: xml).map { String(xml[$0]) }
        }
        return algorithms.contains { !Self.fontObfuscation.contains($0) }
    }
}
