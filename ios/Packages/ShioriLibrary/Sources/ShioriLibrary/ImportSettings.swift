import Foundation
import ShioriCore

public enum TXTEncodingChoice: String, Codable, CaseIterable, Sendable {
    case auto, utf8, gb18030, big5, utf16
}

/// TXT import choices from Settings → Import (spec §8.1), applied to new imports and re-splits.
public struct ImportSettings: Codable, Equatable, Sendable {
    public var encoding: TXTEncodingChoice
    public var enabledRuleIDs: Set<String>
    /// A chapter (not volume) rule; an invalid pattern is ignored rather than failing imports.
    public var customPattern: String?

    public init(encoding: TXTEncodingChoice, enabledRuleIDs: Set<String>, customPattern: String?) {
        self.encoding = encoding
        self.enabledRuleIDs = enabledRuleIDs
        self.customPattern = customPattern
    }

    public static let `default` = ImportSettings(
        encoding: .auto, enabledRuleIDs: Set(ChapterRule.presets.map(\.id)), customPattern: nil)

    /// Enabled presets in preset order, then the custom rule.
    public var rules: [ChapterRule] {
        var rules = ChapterRule.presets.filter { enabledRuleIDs.contains($0.id) }
        if let pattern = customPattern?.trimmingCharacters(in: .whitespaces), !pattern.isEmpty,
           (try? NSRegularExpression(pattern: pattern)) != nil {
            rules.append(ChapterRule(id: "custom", pattern: pattern, isVolume: false))
        }
        return rules
    }

    private static let key = "importSettings"

    public static func load(from defaults: UserDefaults) -> ImportSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ImportSettings.self, from: data) else { return .default }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
