import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case system, zhHans, english

    var locale: Locale? {
        switch self {
        case .system: nil
        case .zhHans: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark
}

/// The accent pairs from spec §4.2.
enum AccentPreset: String, CaseIterable, Codable {
    case ink, iris, sealVermilion, indigo, fogPine, shallowSea, rouge, wheat, graphite, ribbonViolet

    var light: UInt32 {
        switch self {
        case .ink: 0x24222A
        case .iris: 0x6E6190
        case .sealVermilion: 0xA9402B
        case .indigo: 0x2E4A78
        case .fogPine: 0x4F6B5F
        case .shallowSea: 0x476C85
        case .rouge: 0x8E5864
        case .wheat: 0x7F6A3C
        case .graphite: 0x5F636A
        case .ribbonViolet: 0x7650C9
        }
    }

    var dark: UInt32 {
        switch self {
        case .ink: 0xEDEDED
        case .iris: 0xB3A8CC
        case .sealVermilion: 0xE58A6F
        case .indigo: 0x94AEDA
        case .fogPine: 0x93B5A6
        case .shallowSea: 0x8DB3CC
        case .rouge: 0xD3A0AC
        case .wheat: 0xCDB789
        case .graphite: 0xA5A9B0
        case .ribbonViolet: 0xB79CF2
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .ink: "Ink"
        case .iris: "Iris"
        case .sealVermilion: "Seal vermilion"
        case .indigo: "Indigo"
        case .fogPine: "Fog pine"
        case .shallowSea: "Shallow sea"
        case .rouge: "Rouge"
        case .wheat: "Wheat"
        case .graphite: "Graphite"
        case .ribbonViolet: "Ribbon violet"
        }
    }
}

enum AccentChoice: Codable, Equatable {
    case preset(AccentPreset)
    /// `adjusted` when the picked colour failed 4.5:1 against paper and was darkened or lightened.
    case custom(light: UInt32, dark: UInt32, adjusted: Bool)
}

/// App-wide preferences, one UserDefaults key each.
@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            // The environment locale switches the running app; AppleLanguages makes the next
            // cold launch (and system-rendered text) agree.
            switch language {
            case .system: defaults.removeObject(forKey: "AppleLanguages")
            case .zhHans: defaults.set(["zh-Hans"], forKey: "AppleLanguages")
            case .english: defaults.set(["en"], forKey: "AppleLanguages")
            }
        }
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var accent: AccentChoice {
        didSet { defaults.set(try? JSONEncoder().encode(accent), forKey: Keys.accent) }
    }

    var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: Keys.reduceMotion) }
    }

    var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Keys.haptics) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .system
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init) ?? .system
        accent = defaults.data(forKey: Keys.accent)
            .flatMap { try? JSONDecoder().decode(AccentChoice.self, from: $0) } ?? .preset(.ink)
        reduceMotion = defaults.bool(forKey: Keys.reduceMotion)
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
    }

    var locale: Locale? { language.locale }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private enum Keys {
        static let language = "settings.language"
        static let appearance = "settings.appearance"
        static let accent = "settings.accent"
        static let reduceMotion = "settings.reduceMotion"
        static let haptics = "settings.haptics"
    }
}
