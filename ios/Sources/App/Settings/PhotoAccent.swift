import CoreGraphics
import Foundation
import ImageIO

/// Picks the dominant colours out of a photo for the accent page: a 64×64 downsample counted
/// in a 4-bit-per-channel histogram.
enum PhotoAccent {
    static func dominantColours(in data: Data?, count: Int = 5) async -> [UInt32] {
        guard let data else { return [] }
        return await Task.detached(priority: .userInitiated) {
            pixels(of: data).map { dominant($0, count: count) } ?? []
        }.value
    }

    private static let side = 64

    /// RGBA, premultiplied, `side` × `side`.
    private static func pixels(of data: Data) -> [UInt8]? {
        // A small thumbnail first, so a 48 MP photo is never decoded at full size.
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? bytes : nil
    }

    private struct Bin {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        var colour: UInt32 {
            UInt32(red / count) << 16 | UInt32(green / count) << 8 | UInt32(blue / count)
        }

        /// Plain frequency would hand all five places to a grey sky or a shadow, which make
        /// poor accents, so colourful bins get up to three times their count.
        var score: Double {
            let r = red / count, g = green / count, b = blue / count
            let chroma = Double(max(r, g, b) - min(r, g, b)) / 255
            return Double(count) * (1 + 2 * chroma)
        }
    }

    private static func dominant(_ pixels: [UInt8], count: Int) -> [UInt32] {
        var bins = [Bin](repeating: Bin(), count: 4096)
        for i in stride(from: 0, to: pixels.count - 3, by: 4) {
            let alpha = Int(pixels[i + 3])
            guard alpha >= 128 else { continue }
            let red = min(255, Int(pixels[i]) * 255 / alpha)
            let green = min(255, Int(pixels[i + 1]) * 255 / alpha)
            let blue = min(255, Int(pixels[i + 2]) * 255 / alpha)
            let key = (red >> 4) << 8 | (green >> 4) << 4 | blue >> 4
            bins[key].count += 1
            bins[key].red += red
            bins[key].green += green
            bins[key].blue += blue
        }
        let ranked = bins.filter { $0.count > 0 }
            .map { (colour: $0.colour, score: $0.score) }
            .sorted { $0.score > $1.score }
            .map { $0.colour }
        // Neighbouring bins of one colour would crowd out everything else, so each pick must
        // sit apart from the earlier ones; the gap shrinks for photos with few colours.
        var picked: [UInt32] = []
        for gap in [56, 28, 0] where picked.count < count {
            for colour in ranked where picked.count < count && !picked.contains(colour) {
                if picked.allSatisfy({ distance($0, colour) >= gap }) {
                    picked.append(colour)
                }
            }
        }
        return picked
    }

    private static func distance(_ a: UInt32, _ b: UInt32) -> Int {
        let dr = Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF)
        let dg = Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF)
        let db = Int(a & 0xFF) - Int(b & 0xFF)
        return Int(Double(dr * dr + dg * dg + db * db).squareRoot())
    }
}
