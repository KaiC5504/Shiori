import Foundation
import Observation
import ShioriCore
import ShioriLibrary
import SwiftUI

enum ReaderLayout: String, CaseIterable, Codable {
    case scroll, paged
}

/// The paged layout's turn (spec §7.2). `paper` stays hidden until M9 ships it.
enum PageTurnEffect: String, CaseIterable, Codable {
    case relay, curl, paper
}

/// Relay's pace; Apple's curl has its own.
enum TurnSpeed: String, CaseIterable, Codable {
    case gentle, standard, brisk
}

/// The reader's paper themes (spec §7.5). `followAppearance` wears the app's own paper.
enum ReaderTheme: String, CaseIterable, Codable {
    case followAppearance, milk, parchment, lightMoss, night

    var title: LocalizedStringResource {
        switch self {
        case .followAppearance: "Follow appearance"
        case .milk: "Milk"
        case .parchment: "Parchment"
        case .lightMoss: "Light moss"
        case .night: "Night"
        }
    }

    var paper: Color {
        switch self {
        case .followAppearance: Tokens.paper
        case .milk: Self.fixed(0xF6F1E7)
        case .parchment: Self.fixed(0xEADBBE)
        case .lightMoss: Self.fixed(0xDDE6D3)
        case .night: Self.fixed(0x141414)
        }
    }

    var ink: Color {
        switch self {
        case .followAppearance: Tokens.ink
        case .milk: Self.fixed(0x2A2622)
        case .parchment: Self.fixed(0x3A2E20)
        case .lightMoss: Self.fixed(0x26321F)
        case .night: Self.fixed(0xC9C4BB)
        }
    }

    var inkSecondary: Color {
        switch self {
        case .followAppearance: Tokens.inkSecondary
        case .milk: Self.fixed(0x7A7268)
        case .parchment: Self.fixed(0x7D6A52)
        case .lightMoss: Self.fixed(0x5F6E57)
        case .night: Self.fixed(0x7C786F)
        }
    }

    /// The scheme the reader forces so sheets and system controls match the paper.
    var colorScheme: ColorScheme? {
        switch self {
        case .followAppearance: nil
        case .night: .dark
        case .milk, .parchment, .lightMoss: .light
        }
    }

    private static func fixed(_ rgb: UInt32) -> Color { Tokens.color(light: rgb, dark: rgb) }
}

/// Reader settings for all books, saved as they change.
@MainActor @Observable
final class ReaderPreferences {
    @ObservationIgnored private let defaults: UserDefaults

    var typography: ReaderTypography {
        didSet { defaults.set(try? JSONEncoder().encode(typography), forKey: Keys.typography) }
    }

    var theme: ReaderTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// The theme Day/Night returns to from Night.
    var dayTheme: ReaderTheme {
        didSet { defaults.set(dayTheme.rawValue, forKey: Keys.dayTheme) }
    }

    /// Night's text brightness, 0.35...1 (spec §7.5).
    var nightTextBrightness: Double {
        didSet { defaults.set(nightTextBrightness, forKey: Keys.nightTextBrightness) }
    }

    var showsInfoFooter: Bool {
        didSet { defaults.set(showsInfoFooter, forKey: Keys.showsInfoFooter) }
    }

    var layout: ReaderLayout {
        didSet { defaults.set(layout.rawValue, forKey: Keys.layout) }
    }

    var effect: PageTurnEffect {
        didSet { defaults.set(effect.rawValue, forKey: Keys.effect) }
    }

    var speed: TurnSpeed {
        didSet { defaults.set(speed.rawValue, forKey: Keys.speed) }
    }

    var tapLayout: TapZoneLayout {
        didSet { defaults.set(tapLayout.rawValue, forKey: Keys.tapLayout) }
    }

    var bothSidesForward: Bool {
        didSet { defaults.set(bothSidesForward, forKey: Keys.bothSidesForward) }
    }

    var keepsScreenAwake: Bool {
        didSet { defaults.set(keepsScreenAwake, forKey: Keys.keepsScreenAwake) }
    }

    /// The reader's own screen brightness, 0...1; nil follows the system.
    var brightness: Double? {
        didSet { defaults.set(brightness, forKey: Keys.brightness) }
    }

    /// Hidden while reading; the chrome always shows it.
    var hidesStatusBar: Bool {
        didSet { defaults.set(hidesStatusBar, forKey: Keys.hidesStatusBar) }
    }

    var showsBattery: Bool {
        didSet { defaults.set(showsBattery, forKey: Keys.showsBattery) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        typography = defaults.data(forKey: Keys.typography)
            .flatMap { try? JSONDecoder().decode(ReaderTypography.self, from: $0) } ?? .default
        theme = defaults.string(forKey: Keys.theme).flatMap(ReaderTheme.init) ?? .followAppearance
        dayTheme = defaults.string(forKey: Keys.dayTheme).flatMap(ReaderTheme.init) ?? .followAppearance
        nightTextBrightness = defaults.object(forKey: Keys.nightTextBrightness) as? Double ?? 0.8
        showsInfoFooter = defaults.object(forKey: Keys.showsInfoFooter) as? Bool ?? true
        layout = defaults.string(forKey: Keys.layout).flatMap(ReaderLayout.init) ?? .scroll
        effect = defaults.string(forKey: Keys.effect).flatMap(PageTurnEffect.init) ?? .relay
        speed = defaults.string(forKey: Keys.speed).flatMap(TurnSpeed.init) ?? .standard
        tapLayout = defaults.string(forKey: Keys.tapLayout).flatMap(TapZoneLayout.init) ?? .standard
        bothSidesForward = defaults.object(forKey: Keys.bothSidesForward) as? Bool ?? false
        keepsScreenAwake = defaults.object(forKey: Keys.keepsScreenAwake) as? Bool ?? true
        brightness = defaults.object(forKey: Keys.brightness) as? Double
        hidesStatusBar = defaults.object(forKey: Keys.hidesStatusBar) as? Bool ?? true
        showsBattery = defaults.object(forKey: Keys.showsBattery) as? Bool ?? true
    }

    func toggleDayNight() {
        if theme == .night {
            theme = dayTheme == .night ? .followAppearance : dayTheme
        } else {
            dayTheme = theme
            theme = .night
        }
    }

    /// The text colour, with Night's brightness applied.
    var textColor: Color {
        theme == .night ? theme.ink.opacity(nightTextBrightness) : theme.ink
    }

    private enum Keys {
        static let typography = "reader.typography"
        static let theme = "reader.theme"
        static let dayTheme = "reader.dayTheme"
        static let nightTextBrightness = "reader.nightTextBrightness"
        static let showsInfoFooter = "reader.showsInfoFooter"
        static let layout = "reader.layout"
        static let effect = "reader.effect"
        static let speed = "reader.speed"
        static let tapLayout = "reader.tapLayout"
        static let bothSidesForward = "reader.bothSidesForward"
        static let keepsScreenAwake = "reader.keepsScreenAwake"
        static let brightness = "reader.brightness"
        static let hidesStatusBar = "reader.hidesStatusBar"
        static let showsBattery = "reader.showsBattery"
    }
}
