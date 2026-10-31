import Foundation
import ZIPFoundation

/// Entry names in ZIPs made on Chinese Windows, which writes them in GBK without the UTF-8
/// flag (spec §8.3).
enum ZIPNames {
    private static let cp437 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))

    static func path(of entry: Entry) -> String {
        // ZIPFoundation reads the name as UTF-8 when the flag is set and as CP437 otherwise,
        // and the two agree only on ASCII, so a match means there's nothing to fix.
        let utf8 = entry.path(using: .utf8)
        if !utf8.isEmpty, entry.path == utf8 { return utf8 }
        // CP437 maps every byte to its own character, so this gives back the raw name.
        guard let raw = entry.path(using: cp437).data(using: cp437) else { return entry.path }
        return decode(raw)
    }

    /// UTF-8 when the bytes are valid UTF-8, else GB18030 (a superset of GBK), else CP437,
    /// the ZIP format's own default.
    static func decode(_ raw: Data) -> String {
        if let utf8 = String(data: raw, encoding: .utf8) { return utf8 }
        if let gb = String(data: raw, encoding: TextDecoding.gb18030) { return gb }
        return String(data: raw, encoding: cp437) ?? String(decoding: raw, as: UTF8.self)
    }
}
