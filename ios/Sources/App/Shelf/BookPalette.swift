import CoreGraphics
import SwiftUI
import UIKit

/// A book's binding colours: its cover's dominant colour, else a muted archive colour picked
/// by its id. These are book data, like the cover itself, so they don't follow the theme. The
/// board stays dark enough that the pale spine ink always reads on it.
struct BookPalette: Equatable, Sendable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = min(max(saturation, 0), 0.5)
        self.brightness = min(max(brightness, 0.24), 0.42)
    }

    init(bookId: UUID) {
        let swatches = Self.archive
        let pick = min(Int(BookHash.unit(bookId, salt: 1) * CGFloat(swatches.count)), swatches.count - 1)
        let swatch = swatches[pick]
        self.init(hue: swatch.hue, saturation: swatch.saturation, brightness: swatch.brightness)
    }

    var board: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }
    var boardLight: Color { Color(hue: hue, saturation: saturation * 0.9, brightness: brightness + 0.07) }
    var ink: Color { Color(hue: hue, saturation: min(saturation, 0.1), brightness: 0.94) }
    var pages: Color { Color(hue: hue, saturation: 0.07, brightness: 0.68) }
    var shade: Color { Color(hue: hue, saturation: saturation, brightness: 0.05) }

    // Plum, pine, walnut, oxblood, olive, navy, slate, teal, rose grey, umber.
    private static let archive: [(hue: Double, saturation: Double, brightness: Double)] = [
        (0.74, 0.32, 0.34), (0.42, 0.34, 0.30), (0.08, 0.40, 0.33), (0.99, 0.44, 0.32),
        (0.16, 0.36, 0.30), (0.60, 0.40, 0.33), (0.56, 0.20, 0.34), (0.49, 0.36, 0.28),
        (0.02, 0.22, 0.38), (0.11, 0.32, 0.28),
    ]

    /// The cover's strongest hue, from a 12 × 12 sample: pixels are binned by hue and weighted
    /// by how vivid they are, so a dark or grey frame doesn't drown out the art.
    static func dominant(in image: CGImage) -> BookPalette? {
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let bins = 12
        var weight = [Double](repeating: 0, count: bins)
        var hueSum = [Double](repeating: 0, count: bins)
        var saturationSum = [Double](repeating: 0, count: bins)
        var brightnessSum = [Double](repeating: 0, count: bins)
        var brightnessTotal = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let (h, s, v) = hsv(Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
            brightnessTotal += v
            let w = s * v
            let bin = min(Int(h * Double(bins)), bins - 1)
            weight[bin] += w
            hueSum[bin] += h * w
            saturationSum[bin] += s * w
            brightnessSum[bin] += v * w
        }
        let count = Double(side * side)
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > count * 0.02 else {
            return BookPalette(hue: 0.08, saturation: 0.04, brightness: brightnessTotal / count * 0.6)
        }
        let w = weight[best]
        return BookPalette(hue: hueSum[best] / w, saturation: saturationSum[best] / w * 0.8,
                           brightness: brightnessSum[best] / w * 0.6)
    }

    private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let high = max(r, g, b), low = min(r, g, b), span = high - low
        guard span > 0 else { return (0, 0, high) }
        var h: Double
        if high == r {
            h = (g - b) / span
        } else if high == g {
            h = (b - r) / span + 2
        } else {
            h = (r - g) / span + 4
        }
        h /= 6
        if h < 0 { h += 1 }
        return (h, span / high, high)
    }
}

/// Cover palettes, worked out off the main thread once per cover.
@MainActor
enum BookPalettes {
    private static var cache: [String: BookPalette] = [:]

    static func cached(_ key: String) -> BookPalette? {
        cache[key]
    }

    static func palette(for key: String, image: UIImage) async -> BookPalette? {
        if let hit = cache[key] { return hit }
        guard let cgImage = image.cgImage else { return nil }
        let found = await Task.detached(priority: .utility) { BookPalette.dominant(in: cgImage) }.value
        if let found { cache[key] = found }
        return found
    }
}
