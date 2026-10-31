import Foundation

/// Three small books for Debug demo mode and screenshots: each opens with a line from a
/// public-domain classic, and the rest is generated filler of realistic length.
public enum DemoBooks {
    public static func write(into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let taohuayuan = directory.appending(path: "桃花源记(陶渊明).epub")
        try EPUBWriter.write(.init(
            title: "桃花源记", author: "陶渊明", identifier: "shiori-demo-taohuayuan",
            chapters: (1...12).map { n in
                (title: "第\(numeral(n))章", volume: nil,
                 paragraphs: paragraphs(opening: "晋太元中，武陵人捕鱼为业。", chapter: n, count: 24))
            },
            coverJPEG: nil), to: taohuayuan)

        let yueyang = directory.appending(path: "岳阳楼记(范仲淹).txt")
        var text = "《岳阳楼记》\n宋·范仲淹\n"
        for n in 1...5 {
            text += "第\(numeral(n))章 楼记其\(numeral(n))\n"
            text += paragraphs(opening: "庆历四年春，滕子京谪守巴陵郡。", chapter: n, count: 20)
                .map { "　　" + $0 }.joined(separator: "\r\n") + "\r\n"
        }
        guard let gb = text.data(using: TextDecoding.gb18030) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        try gb.write(to: yueyang)

        let lanting = directory.appending(path: "兰亭集序(王羲之).epub")
        try EPUBWriter.write(.init(
            title: "兰亭集序", author: "王羲之", identifier: "shiori-demo-lanting",
            chapters: (1...6).map { n in
                (title: "第\(numeral(n))章", volume: n <= 3 ? "上卷 暮春" : "下卷 感怀",
                 paragraphs: paragraphs(opening: "永和九年，岁在癸丑。", chapter: n, count: 18))
            },
            coverJPEG: nil), to: lanting)

        return [taohuayuan, yueyang, lanting]
    }

    /// A web-novel-sized book for the reader's scroll tests: `chapters` chapters titled "第N章"
    /// with 6–45 paragraphs each, every paragraph opening with a 〔N·P〕 marker so a test can
    /// tell exactly which paragraph is on screen.
    public static func writeLong(into directory: URL, chapters count: Int = 3_000) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "长篇测试(生成).epub")
        try EPUBWriter.write(.init(
            title: "长篇测试", author: "生成", identifier: "shiori-demo-long",
            chapters: (1...count).map { n in
                (title: "第\(n)章", volume: nil, paragraphs: markedParagraphs(chapter: n))
            },
            coverJPEG: nil), to: url)
        return url
    }

    private static func markedParagraphs(chapter n: Int) -> [String] {
        let count = 6 + (n * 37) % 40
        return (1...count).map { p in
            let sentences = 2 + (n + p) % 4
            let body = (0..<sentences).map { filler[(n + p + $0) % filler.count] }.joined()
            return "〔\(n)·\(p)〕" + body
        }
    }

    private static let filler = [
        "山间的风从溪水上吹过来，带着一点湿润的草木气息。",
        "他沿着小路慢慢地走，脚下的石子被晒得微微发暖。",
        "远处有人在田里劳作，偶尔传来几声说笑。",
        "天色渐渐暗下来，屋舍里亮起了灯，炊烟一缕一缕地升起。",
        "他停下来看了很久，心里说不出是欢喜还是惆怅。",
        "夜里下了一场小雨，第二天清晨，满地都是落下的花瓣。",
        "这一路上见到的人和事，他后来常常想起，却很少对人说起。",
    ]

    private static func paragraphs(opening: String, chapter: Int, count: Int) -> [String] {
        [opening] + (1..<count).map { i in
            (0..<4).map { filler[(chapter * 3 + i + $0) % filler.count] }.joined()
        }
    }

    private static func numeral(_ n: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return digits[n] }
        if n == 10 { return "十" }
        if n < 20 { return "十" + digits[n - 10] }
        return digits[n / 10] + "十" + (n % 10 == 0 ? "" : digits[n % 10])
    }
}
