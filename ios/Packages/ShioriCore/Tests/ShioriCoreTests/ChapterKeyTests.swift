import Foundation
import Testing
@testable import ShioriCore

@Test func chapterKeysCountRepeats() {
    let keys = ChapterKeys.make(titles: ["第一章 开始", "番外", "番外", "  第一章  开始 "])
    #expect(keys == [
        ChapterKey(title: "第一章 开始", occurrence: 0), ChapterKey(title: "番外", occurrence: 0),
        ChapterKey(title: "番外", occurrence: 1), ChapterKey(title: "第一章 开始", occurrence: 1),
    ])
}
