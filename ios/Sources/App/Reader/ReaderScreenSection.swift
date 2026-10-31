import ShioriCore
import SwiftUI

/// SCREEN AND GESTURES in the Aa sheet (spec §7.5, §7.6): tap zones with a small page that shows
/// them, brightness, keep awake, the status bar and the battery.
struct ReaderScreenSection: View {
    @Bindable var preferences: ReaderPreferences

    init(preferences: ReaderPreferences) {
        _preferences = Bindable(preferences)
    }

    private static let diagramWidth: CGFloat = 78

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "SCREEN", title: "Screen and gestures")
            VStack(spacing: 10) {
                tapCard
                brightnessCard
                screenCard
            }
        }
    }

    private var tapCard: some View {
        ArchiveCard {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap zones")
                        .foregroundStyle(Tokens.ink)
                        .accessibilityAddTraits(.isHeader)
                    TapLayoutPicker(selection: $preferences.tapLayout)
                }
                .padding(.leading, Self.diagramWidth + 14)
                // Sized by the picker beside it, so the little page is as tall as the choices.
                .overlay(alignment: .leading) {
                    TapZoneDiagram(layout: preferences.tapLayout, bothSidesForward: preferences.bothSidesForward)
                        .frame(width: Self.diagramWidth)
                }
                .padding(16)
                AppearanceHairline().padding(.leading, 16)
                SettingsToggleRow("Both sides go forward", isOn: $preferences.bothSidesForward)
            }
        }
    }

    // The slider is always there: dragging it is how the reader takes its own brightness, and while
    // following the system it shows the phone's level to start from.
    private var brightnessCard: some View {
        ArchiveCard {
            VStack(spacing: 0) {
                AppearanceSlider("Brightness", value: brightness, in: 0...1, step: 0.01,
                                 valueText: Text(ReaderScreen.level(preferences),
                                                 format: .percent.precision(.fractionLength(0))))
                AppearanceHairline().padding(.leading, 16)
                SettingsToggleRow("Follow system",
                                  footnote: Text("Swipe up or down along the left edge to change brightness."),
                                  isOn: followsSystem)
            }
        }
    }

    private var screenCard: some View {
        ArchiveCard {
            VStack(spacing: 0) {
                SettingsToggleRow("Keep screen awake", isOn: $preferences.keepsScreenAwake)
                AppearanceHairline().padding(.leading, 16)
                SettingsToggleRow("Hide status bar", isOn: $preferences.hidesStatusBar)
                AppearanceHairline().padding(.leading, 16)
                SettingsToggleRow("Show battery", isOn: $preferences.showsBattery)
            }
        }
    }

    private var brightness: Binding<Double> {
        Binding(get: { ReaderScreen.level(preferences) },
                set: { value in
                    let rounded = (min(max(value, 0), 1) * 100).rounded() / 100
                    if preferences.brightness != rounded { preferences.brightness = rounded }
                })
    }

    private var followsSystem: Binding<Bool> {
        Binding(get: { preferences.brightness == nil },
                set: { follows in preferences.brightness = follows ? nil : ReaderScreen.systemLevel })
    }
}

private extension TapZoneLayout {
    var title: LocalizedStringKey {
        switch self {
        case .standard: "Standard"
        case .rightHanded: "Right-handed"
        case .leftHanded: "Left-handed"
        }
    }
}

/// The three layouts stacked, with the lens that slides to the chosen one, like the sheet's
/// segment strips.
private struct TapLayoutPicker: View {
    @Binding var selection: TapZoneLayout

    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced
    @Namespace private var lens

    var body: some View {
        VStack(spacing: 2) {
            ForEach(TapZoneLayout.allCases, id: \.self) { option in
                cell(option)
            }
        }
        .padding(3)
        .background(Tokens.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
        .animation(Motion.animation(Motion.lens, reduced: reduced), value: selection)
        .shioriHaptic(.selection, trigger: selection)
    }

    private func cell(_ option: TapZoneLayout) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            Text(option.title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Tokens.paper : Tokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .background {
                    if selected {
                        lensShape
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("aa.tapLayout.\(option.rawValue)")
    }

    @ViewBuilder
    private var lensShape: some View {
        let shape = RoundedRectangle(cornerRadius: 5).fill(accent)
        if reduced {
            shape.transition(.opacity)
        } else {
            shape.matchedGeometryEffect(id: "lens", in: lens)
        }
    }
}

/// A little page in a 3 × 4 grid, every cell coloured by what a tap at its centre does. Every
/// border in the layouts falls on a third across or a quarter down, so the grid is exact, and it
/// asks `TapZones` itself rather than restating the zones. A change ripples across the cells.
private struct TapZoneDiagram: View {
    let layout: TapZoneLayout
    let bothSidesForward: Bool

    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced

    private static let columns = 3
    private static let rows = 4

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        cell(row: row, column: column)
                    }
                }
            }
        }
        .padding(5)
        .background(Tokens.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private func cell(row: Int, column: Int) -> some View {
        let action = TapZones.action(x: Double(column) + 0.5, y: Double(row) + 0.5,
                                     width: Double(Self.columns), height: Double(Self.rows),
                                     layout: layout, bothSidesForward: bothSidesForward)
        let delay = reduced ? 0 : Double(row + column) * 0.04
        return RoundedRectangle(cornerRadius: 4)
            .fill(fill(action))
            .overlay {
                Image(systemName: glyph(action))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ink(action))
                    .contentTransition(reduced ? .opacity : .symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.animation(Motion.lens, reduced: reduced).delay(delay), value: action)
    }

    private func fill(_ action: TapAction) -> Color {
        switch action {
        case .forward: accent
        case .back: Tokens.ink.opacity(0.14)
        case .menu: Tokens.line.opacity(0.5)
        }
    }

    private func ink(_ action: TapAction) -> Color {
        switch action {
        case .forward: Tokens.paper
        case .back: Tokens.ink
        case .menu: Tokens.inkSecondary
        }
    }

    // Physical left and right: the zones are where the thumb lands, whatever the language.
    private func glyph(_ action: TapAction) -> String {
        switch action {
        case .forward: "chevron.right"
        case .back: "chevron.left"
        case .menu: "ellipsis"
        }
    }
}
