import CoreGraphics
import Foundation
import ImageIO

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

        // The shelf's first book, whose third chapter the illustration screenshots open.
        let lanting = directory.appending(path: "兰亭集序(王羲之).epub")
        let plates = [
            illustration(width: 720, height: 960, night: false).map {
                EPUBWriter.Illustration(chapter: 2, href: "images/plate-1.jpg", data: $0)
            },
            illustration(width: 960, height: 720, night: true).map {
                EPUBWriter.Illustration(chapter: 2, beforeParagraph: 9, href: "images/plate-2.jpg", data: $0)
            },
        ].compactMap { $0 }
        try EPUBWriter.write(.init(
            title: "兰亭集序", author: "王羲之", identifier: "shiori-demo-lanting",
            chapters: (1...6).map { n in
                (title: "第\(numeral(n))章", volume: n <= 3 ? "上卷 暮春" : "下卷 感怀",
                 paragraphs: paragraphs(opening: "永和九年，岁在癸丑。", chapter: n, count: 18))
            },
            coverJPEG: nil, illustrations: plates), to: lanting)

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

    private struct Palette {
        var skyTop: UInt32
        var skyBottom: UInt32
        /// The sun by day, the moon by night.
        var light: UInt32
        /// Far to near.
        var ridges: [UInt32]
        var mist: UInt32
        var stream: UInt32
        var ink: UInt32
    }

    private static let day = Palette(skyTop: 0xF4EBDD, skyBottom: 0xE4D2B6, light: 0xC8553D,
                                     ridges: [0xBDBAA6, 0x929A88, 0x5F6C5F, 0x323C35],
                                     mist: 0xF1E7D6, stream: 0xDCE4DF, ink: 0x2A2622)
    private static let night = Palette(skyTop: 0x1A2136, skyBottom: 0x3B3653, light: 0xEFE6CF,
                                       ridges: [0x4B4B67, 0x373953, 0x25273C, 0x15161F],
                                       mist: 0x5B5776, stream: 0x8E94B1, ink: 0xEFE6CF)

    /// A JPEG of an ink-wash landscape: ridges with mist pooling between them, a stream, the
    /// sun or the moon, and a seal. Drawn here so no real artwork ships in the demo.
    static func illustration(width: Int, height: Int, night isNight: Bool) -> Data? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let palette = isNight ? night : day
        let w = CGFloat(width)
        let h = CGFloat(height)
        let short = min(w, h)
        func colour(_ rgb: UInt32, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
        }
        func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient? {
            CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1])
        }

        if let sky = gradient(colour(palette.skyTop), colour(palette.skyBottom)) {
            context.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.3),
                                       options: [.drawsAfterEndLocation])
        }
        if isNight {
            context.setFillColor(colour(palette.light, 0.7))
            for i in 0..<48 {
                let x = fraction(Double(i) * 12.9898) * w
                let y = h * (0.5 + 0.5 * fraction(Double(i) * 78.233))
                let r = short * (0.002 + 0.003 * fraction(Double(i) * 3.17))
                context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        }

        let centre = CGPoint(x: w * 0.7, y: h * 0.78)
        let radius = short * 0.11
        if let glow = gradient(colour(palette.light, 0.35), colour(palette.light, 0)) {
            context.drawRadialGradient(glow, startCenter: centre, startRadius: radius,
                                       endCenter: centre, endRadius: radius * 2.6, options: [])
        }
        context.setFillColor(colour(palette.light, 0.9))
        context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))

        let bases: [CGFloat] = [0.60, 0.48, 0.34, 0.18]
        let amplitudes: [CGFloat] = [0.10, 0.12, 0.10, 0.07]
        for (k, rgb) in palette.ridges.enumerated() {
            let base = h * bases[k]
            let amplitude = h * amplitudes[k]
            let phase = CGFloat(k) * 1.7 + (isNight ? 0.9 : 0)
            let ridge = CGMutablePath()
            ridge.move(to: .zero)
            var x: CGFloat = 0
            while x <= w + 3 {
                let t = x / w
                let wave = 0.6 * sin(t * 5.1 + phase) + 0.3 * sin(t * 11.3 + phase * 2) + 0.1 * sin(t * 27 + phase * 3)
                ridge.addLine(to: CGPoint(x: x, y: base + amplitude * wave))
                x += 3
            }
            ridge.addLine(to: CGPoint(x: w + 3, y: 0))
            ridge.closeSubpath()
            context.addPath(ridge)
            context.setFillColor(colour(rgb))
            context.fillPath()
            // Mist pools at the ridge's foot, and the next, nearer ridge rises out of it.
            if k < palette.ridges.count - 1, let mist = gradient(colour(palette.mist, 0), colour(palette.mist, 0.75)) {
                context.saveGState()
                context.clip(to: CGRect(x: 0, y: 0, width: w, height: base))
                context.drawLinearGradient(mist, start: CGPoint(x: 0, y: base), end: CGPoint(x: 0, y: base - amplitude * 1.6),
                                           options: [.drawsAfterEndLocation])
                context.restoreGState()
            }
        }

        let stream = CGMutablePath()
        stream.move(to: CGPoint(x: w * 0.12, y: -h * 0.02))
        stream.addCurve(to: CGPoint(x: w * 0.58, y: h * 0.2), control1: CGPoint(x: w * 0.55, y: h * 0.05),
                        control2: CGPoint(x: w * 0.2, y: h * 0.16))
        context.setLineCap(.round)
        // Fading out up the page, so the stream runs off into the distance instead of stopping.
        for (rgb, alpha, width) in [(palette.stream, 0.8, 0.035), (palette.skyTop, 0.5, 0.008)] as [(UInt32, CGFloat, CGFloat)] {
            guard let fade = gradient(colour(rgb, alpha), colour(rgb, 0)) else { continue }
            context.saveGState()
            context.addPath(stream)
            context.setLineWidth(short * width)
            context.replacePathWithStrokedPath()
            context.clip()
            context.drawLinearGradient(fade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h * 0.21), options: [])
            context.restoreGState()
        }

        if !isNight {
            context.setStrokeColor(colour(palette.ink, 0.55))
            context.setLineWidth(max(short / 320, 1.5))
            for (bx, by, size) in [(0.3, 0.82, 1.0), (0.37, 0.87, 0.7)] as [(CGFloat, CGFloat, CGFloat)] {
                let c = CGPoint(x: w * bx, y: h * by)
                let span = short * 0.03 * size
                context.move(to: CGPoint(x: c.x - span, y: c.y + span * 0.5))
                context.addQuadCurve(to: c, control: CGPoint(x: c.x - span * 0.5, y: c.y + span * 0.6))
                context.addQuadCurve(to: CGPoint(x: c.x + span, y: c.y + span * 0.5),
                                     control: CGPoint(x: c.x + span * 0.5, y: c.y + span * 0.6))
                context.strokePath()
            }
        }

        let seal = short * 0.08
        let sealRect = CGRect(x: w - seal - short * 0.07, y: short * 0.07, width: seal, height: seal)
        context.setFillColor(colour(0xB23A2E, 0.9))
        context.fill(sealRect)
        context.setStrokeColor(colour(0xF4EBDD, 0.85))
        context.setLineWidth(seal * 0.06)
        context.stroke(sealRect.insetBy(dx: seal * 0.16, dy: seal * 0.16))
        context.move(to: CGPoint(x: sealRect.midX, y: sealRect.minY + seal * 0.28))
        context.addLine(to: CGPoint(x: sealRect.midX, y: sealRect.maxY - seal * 0.28))
        context.strokePath()

        context.setStrokeColor(colour(palette.ink, 0.35))
        context.setLineWidth(max(short / 360, 1.5))
        context.stroke(CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: short * 0.035, dy: short * 0.035))

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A repeatable scatter in 0..<1, so the stars fall the same way on every launch.
    private static func fraction(_ seed: Double) -> CGFloat {
        let v = sin(seed) * 43_758.5453
        return CGFloat(v - v.rounded(.down))
    }

    private static func numeral(_ n: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return digits[n] }
        if n == 10 { return "十" }
        if n < 20 { return "十" + digits[n - 10] }
        return digits[n / 10] + "十" + (n % 10 == 0 ? "" : digits[n % 10])
    }
}
