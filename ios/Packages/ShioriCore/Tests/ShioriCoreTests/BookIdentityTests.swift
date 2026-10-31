import Foundation
import Testing
@testable import ShioriCore

@Test func identityKeys() {
    #expect(BookIdentity.identifierKey("  trxs-https://www.trxs.cc/tongren/11502/1.html ") == "trxs-https://www.trxs.cc/tongren/11502/1.html")
    #expect(BookIdentity.identifierKey("   ") == nil)
    #expect(BookIdentity.titleAuthorKey(title: "全民转职：死灵法师！", author: "慢途的猪") == "全民转职:死灵法师!|慢途的猪")
    #expect(BookIdentity.titleAuthorKey(title: "Book", author: nil) == "book|")
}
