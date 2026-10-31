import SwiftUI
import UIKit

/// M1's paper and ink colours (spec §4.2). The full token and accent system arrives in M2.
enum Tokens {
    static let paper = Color(light: 0xF2ECE3, dark: 0x1F1F1F)
    static let surface = Color(light: 0xFBF8F3, dark: 0x262626)
    static let line = Color(light: 0xDDD5CA, dark: 0x343434)
    static let ink = Color(light: 0x24222A, dark: 0xEDEDED)
    static let inkSecondary = Color(light: 0x6F6A66, dark: 0x8F8F8F)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
