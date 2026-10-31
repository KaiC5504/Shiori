import os
import SwiftUI
import UIKit

/// The home-screen icons. Names match the alternate icon sets in Assets.xcassets and the
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` list in project.yml.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard = "AppIcon"
    case blackViolet = "AppIcon-BlackViolet"
    case creamCover = "AppIcon-CreamCover"
    case original = "AppIcon-Original"
    case roseRibbon = "AppIcon-RoseRibbon"
    case lightNovel = "AppIcon-LightNovel"
    case lavender = "AppIcon-Lavender"

    var id: String { rawValue }

    /// Nil for the primary icon, as `setAlternateIconName` expects.
    var alternateName: String? { self == .standard ? nil : rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .standard: "Default"
        case .blackViolet: "Black violet"
        case .creamCover: "Cream and teal"
        case .original: "Charcoal and pink"
        case .roseRibbon: "Rose"
        case .lightNovel: "Cream and rose"
        case .lavender: "Lavender"
        }
    }

    static var current: AppIconChoice {
        UIApplication.shared.alternateIconName.flatMap(AppIconChoice.init) ?? .standard
    }
}

struct AppIconSettingsView: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.motionReduced) private var reduced
    @State private var selected = AppIconChoice.current
    @State private var failed = false
    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "settings")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(code: "03 / APPEARANCE / ICON", title: "App icon")
                SectionLabel(code: "ICON / HOME SCREEN", title: "Choose an icon")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 20)], spacing: 24) {
                    ForEach(Array(AppIconChoice.allCases.enumerated()), id: \.element) { index, icon in
                        tile(icon).staggeredReveal(index)
                    }
                }
                Text("The default follows the home screen into dark and tinted mode. iOS confirms each change with its own alert.")
                    .font(.footnote)
                    .foregroundStyle(Tokens.inkSecondary)
                if failed {
                    Text("Couldn't change the icon.")
                        .font(.footnote)
                        .foregroundStyle(Tokens.inkSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .paperBackground()
        .shioriHaptic(.selection, trigger: selected)
    }

    private func tile(_ icon: AppIconChoice) -> some View {
        let isSelected = icon == selected
        return Button {
            choose(icon)
        } label: {
            VStack(spacing: 10) {
                Image(previewName(icon))
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(isSelected ? Tokens.ink : Tokens.line, lineWidth: isSelected ? 2.5 : 1)
                    }
                    .scaleEffect(isSelected ? 1.04 : 1)
                    .animation(Motion.animation(Motion.press, reduced: reduced), value: isSelected)
                Text(localized(icon.title))
                    .font(.caption)
                    .foregroundStyle(isSelected ? Tokens.ink : Tokens.inkSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The default's preview follows dark mode, as its home-screen icon does.
    private func previewName(_ icon: AppIconChoice) -> String {
        icon == .standard && colorScheme == .dark ? "Preview-AppIcon-dark" : "Preview-\(icon.rawValue)"
    }

    private func choose(_ icon: AppIconChoice) {
        guard icon != selected, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selected
        selected = icon
        failed = false
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            } catch {
                Self.log.error("changing the app icon failed: \(error)")
                selected = previous
                failed = true
            }
        }
    }

    private func localized(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}
