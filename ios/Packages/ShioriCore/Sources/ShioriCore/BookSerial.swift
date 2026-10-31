import Foundation

/// A book's archive serial, "SH-" plus six digits (spec §4.3). It comes from the id alone,
/// so it never changes and needs no column.
public enum BookSerial {
    public static func make(_ id: UUID) -> String {
        let digits = String(number(id))
        return "SH-" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// The first 4 bytes of the UUID as a big-endian UInt32, mod 1,000,000.
    public static func number(_ id: UUID) -> Int {
        let bytes = id.uuid
        let head = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
        return Int(head % 1_000_000)
    }
}
