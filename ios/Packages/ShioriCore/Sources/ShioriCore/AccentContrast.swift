import Foundation

/// WCAG contrast for 0xRRGGBB colours, and the custom-accent rule from spec §4.2.
public enum AccentContrast {
    public static let minimum = 4.5

    /// The WCAG 2 contrast ratio, 1...21, in either argument order.
    public static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    public static func luminance(_ rgb: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let c = Double(channel & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb >> 16) + 0.7152 * linear(rgb >> 8) + 0.0722 * linear(rgb)
    }

    /// Turns one picked colour into a light/dark pair that each reach 4.5:1 against its
    /// paper, stepping HSL lightness by 0.02: darker for light mode, lighter for dark mode.
    ///
    /// No single colour reaches 4.5:1 against both Shiori papers, so the dark-mode partner
    /// is always derived, as the presets' are. `adjusted` therefore means only that the
    /// picked colour itself was too pale for light-mode paper and had to change.
    public static func fixed(accent: UInt32, paperLight: UInt32, paperDark: UInt32)
        -> (light: UInt32, dark: UInt32, adjusted: Bool) {
        let picked = accent & 0xFFFFFF
        let light = stepped(picked, against: paperLight, by: -0.02)
        let dark = stepped(picked, against: paperDark, by: 0.02)
        return (light, dark, light != picked)
    }

    private static func stepped(_ rgb: UInt32, against paper: UInt32, by step: Double) -> UInt32 {
        var hsl = HSL(rgb: rgb)
        var current = rgb
        while ratio(current, paper) < minimum {
            let next = min(max(hsl.l + step, 0), 1)
            if next == hsl.l { break }
            hsl.l = next
            current = hsl.rgb
        }
        return current
    }
}

/// "#A9402B"-style text for 0xRRGGBB colours.
public enum HexColour {
    public static func string(_ rgb: UInt32) -> String {
        let digits = String(rgb & 0xFFFFFF, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// Accepts 6 or 3 hex digits, with or without a leading "#".
    public static func parse(_ text: String) -> UInt32? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}

private struct HSL {
    var h: Double
    var s: Double
    var l: Double

    init(rgb: UInt32) {
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        let high = max(r, g, b)
        let low = min(r, g, b)
        l = (high + low) / 2
        guard high > low else {
            h = 0
            s = 0
            return
        }
        let d = high - low
        s = l > 0.5 ? d / (2 - high - low) : d / (high + low)
        switch high {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h /= 6
    }

    var rgb: UInt32 {
        func channel(_ value: Double) -> UInt32 {
            UInt32((min(max(value, 0), 1) * 255).rounded())
        }
        guard s > 0 else {
            let v = channel(l)
            return v << 16 | v << 8 | v
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func hue(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return channel(hue(h + 1 / 3)) << 16 | channel(hue(h)) << 8 | channel(hue(h - 1 / 3))
    }
}
