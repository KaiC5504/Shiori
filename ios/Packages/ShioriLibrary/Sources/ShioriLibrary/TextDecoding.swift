import Foundation

/// Thrown only for an empty file; anything else decodes, lossily if it must.
public struct TextDecodingError: Error, Equatable {
    public init() {}
}

/// Decodes TXT downloads, which are UTF-8, GB18030/GBK or Big5, often without a BOM.
public enum TextDecoding {
    public static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    public static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.big5.rawValue)))

    public static func decode(_ data: Data, preferred: String.Encoding? = nil) throws -> (text: String, encoding: String.Encoding) {
        guard !data.isEmpty else { throw TextDecodingError() }

        if let preferred, let text = String(data: data, encoding: preferred) {
            return (stripBOM(text), preferred)
        }
        for (bom, encoding) in [([0xEF, 0xBB, 0xBF], String.Encoding.utf8),
                                ([0xFF, 0xFE], .utf16LittleEndian),
                                ([0xFE, 0xFF], .utf16BigEndian)] as [([UInt8], String.Encoding)]
        where data.starts(with: bom) {
            if let text = String(data: data.dropFirst(bom.count), encoding: encoding) {
                return (stripBOM(text), encoding)
            }
        }
        if let text = String(data: data, encoding: .utf8) {
            return (stripBOM(text), .utf8)
        }
        // Nearly every Big5 file is also valid GB18030 (as nonsense) and the reverse is
        // often true, so validity can't choose between them; byte statistics can.
        let likely = looksLikeBig5(data) ? big5 : gb18030
        if let text = String(data: data, encoding: likely) {
            return (stripBOM(text), likely)
        }
        // A download cut off mid-character leaves up to three dangling bytes.
        for cut in 1...3 where data.count > cut {
            if let text = String(data: data.dropLast(cut), encoding: likely) {
                return (stripBOM(text), likely)
            }
        }
        if let text = detect(data, among: [gb18030, big5], lossy: false) ?? detect(data, among: [likely], lossy: true) {
            return (stripBOM(text.text), text.encoding)
        }
        return (stripBOM(String(decoding: data, as: UTF8.self)), .utf8)
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// Big5 puts about a third of common characters on trail bytes 0x40–0x7E, which GBK
    /// text written in the common GB2312 set almost never uses. Samples the first 1 MiB.
    static func looksLikeBig5(_ data: Data) -> Bool {
        data.prefix(1 << 20).withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var pairs = 0
            var lowTrail = 0
            var i = 0
            while i + 1 < bytes.count {
                let lead = bytes[i]
                guard lead >= 0x81 else { i += 1; continue }
                pairs += 1
                if bytes[i + 1] < 0xA1 { lowTrail += 1 }
                i += 2
            }
            return pairs > 0 && Double(lowTrail) / Double(pairs) > 0.1
        }
    }

    private static func detect(_ data: Data, among encodings: [String.Encoding], lossy: Bool)
        -> (text: String, encoding: String.Encoding)? {
        var converted: NSString?
        var usedLossy: ObjCBool = false
        let raw = NSString.stringEncoding(
            for: data,
            encodingOptions: [.suggestedEncodingsKey: encodings.map(\.rawValue),
                              .useOnlySuggestedEncodingsKey: true,
                              .allowLossyKey: lossy],
            convertedString: &converted,
            usedLossyConversion: &usedLossy)
        guard raw != 0, let converted else { return nil }
        return (converted as String, String.Encoding(rawValue: raw))
    }
}
