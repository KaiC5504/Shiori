import Foundation
import Testing
@testable import ShioriCore

@Test func fileNameMetadata() {
    #expect(FileNameMetadata.parse("全民转职：死灵法师！我即是天灾(慢途的猪).epub") == .init(title: "全民转职：死灵法师！我即是天灾", author: "慢途的猪"))
    #expect(FileNameMetadata.parse("斗破苍穹（天蚕土豆）.txt") == .init(title: "斗破苍穹", author: "天蚕土豆"))
    #expect(FileNameMetadata.parse("《诡秘之主》作者：爱潜水的乌贼.txt") == .init(title: "诡秘之主", author: "爱潜水的乌贼"))
    #expect(FileNameMetadata.parse("无职转生 (1).txt") == .init(title: "无职转生 (1)", author: nil))
    #expect(FileNameMetadata.parse("plain name.txt") == .init(title: "plain name", author: nil))
}
