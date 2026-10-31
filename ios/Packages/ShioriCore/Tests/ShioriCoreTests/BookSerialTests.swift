import Foundation
import Testing
@testable import ShioriCore

@Test func serialIsTheFirstFourBytesModAMillion() {
    let id = UUID(uuidString: "12345678-9ABC-DEF0-1234-56789ABCDEF0")!
    #expect(BookSerial.make(id) == "SH-419896")
    let small = UUID(uuidString: "00000007-0000-0000-0000-000000000000")!
    #expect(BookSerial.make(small) == "SH-000007")
}
