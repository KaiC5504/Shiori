import SwiftUI
import UIKit

/// Paper and ink tokens (spec §4.2). Views never use a literal colour.
enum Tokens {
    static let paper = color(light: 0xF2ECE3, dark: 0x1F1F1F)
    static let surface = color(light: 0xFBF8F3, dark: 0x262626)
    static let line = color(light: 0xDDD5CA, dark: 0x343434)
    static let ink = color(light: 0x24222A, dark: 0xEDEDED)
    static let inkSecondary = color(light: 0x6F6A66, dark: 0x8F8F8F)
    /// Brand only: the last-read ribbon, onboarding, About. Never the everyday accent.
    static let ribbon = color(light: 0x7650C9, dark: 0xB79CF2)

    static func color(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func accent(_ choice: AccentChoice) -> Color {
        switch choice {
        case .preset(let preset): color(light: preset.light, dark: preset.dark)
        case .custom(let light, let dark, _): color(light: light, dark: dark)
        }
    }
}

extension EnvironmentValues {
    @Entry var accent: Color = Tokens.ink
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
