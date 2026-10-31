import Foundation
import Testing
@testable import ShioriLibrary

@Test func decodesGB18030() throws {
    let data = try #require("第一章 测试\n内容".data(using: TextDecoding.gb18030))
    let r = try TextDecoding.decode(data)
    #expect(r.text == "第一章 测试\n内容")
    #expect(r.encoding == TextDecoding.gb18030)
}
@Test func decodesBig5() throws {
    let data = try #require("第一章 測試\n內容很長的一段繁體中文文字".data(using: TextDecoding.big5))
    #expect(try TextDecoding.decode(data).text == "第一章 測試\n內容很長的一段繁體中文文字")
}
@Test func honoursBOMs() throws {
    #expect(try TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("甲".utf8)).text == "甲")
    var le = Data([0xFF, 0xFE]); le.append(try #require("乙".data(using: .utf16LittleEndian)))
    #expect(try TextDecoding.decode(le).text == "乙")
}
@Test func plainUTF8() throws { #expect(try TextDecoding.decode(Data("丙丁".utf8)).encoding == .utf8) }
@Test func preferredEncodingWins() throws {
    let data = try #require("內容".data(using: TextDecoding.big5))
    #expect(try TextDecoding.decode(data, preferred: TextDecoding.big5).text == "內容")
}
@Test func emptyThrows() { #expect(throws: TextDecodingError()) { try TextDecoding.decode(Data()) } }

// 《岳阳楼记》, 范仲淹 (1046).
private let yueyang = "庆历四年春，滕子京谪守巴陵郡。越明年，政通人和，百废具兴。乃重修岳阳楼，增其旧制，刻唐贤今人诗赋于其上，属予作文以记之。"
private let yueyangTraditional = "慶曆四年春，滕子京謫守巴陵郡。越明年，政通人和，百廢具興。乃重修岳陽樓，增其舊制，刻唐賢今人詩賦於其上，屬予作文以記之。"

@Test func longerPassagesPickTheRightChineseEncoding() throws {
    let gb = try #require(yueyang.data(using: TextDecoding.gb18030))
    #expect(try TextDecoding.decode(gb) == (yueyang, TextDecoding.gb18030))
    let big5 = try #require(yueyangTraditional.data(using: TextDecoding.big5))
    #expect(try TextDecoding.decode(big5) == (yueyangTraditional, TextDecoding.big5))
}
@Test func repairsAFileCutMidCharacter() throws {
    var data = try #require(yueyang.data(using: TextDecoding.gb18030))
    data.append(0xB5)
    let r = try TextDecoding.decode(data)
    #expect(r.text.hasPrefix(yueyang))
    #expect(r.encoding == TextDecoding.gb18030)
}
