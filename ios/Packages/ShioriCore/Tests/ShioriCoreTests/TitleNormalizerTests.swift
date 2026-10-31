import Foundation
import Testing
@testable import ShioriCore

@Test func normalizesWidthWhitespaceAndCase() {
    #expect(TitleNormalizer.normalize("  Ｃｈａｐｔｅｒ　１：\n  The   ROAD ") == "chapter 1: the road")
    #expect(TitleNormalizer.normalize("第一章\t开始") == "第一章 开始")
    #expect(TitleNormalizer.normalize("   ") == "")
}
