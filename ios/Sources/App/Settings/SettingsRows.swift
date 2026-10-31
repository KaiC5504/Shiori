import SwiftUI

/// One compact row: the title, with an optional footnote under it, then the row's current
/// value and glyph on the trailing edge.
struct SettingsRow<Accessory: View>: View {
    private let title: Text
    private let footnote: Text?
    private let accessory: Accessory

    init(_ title: LocalizedStringKey, footnote: Text? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = Text(title)
        self.footnote = footnote
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowLabels(title: title, footnote: footnote)
            Spacer(minLength: 12)
            HStack(spacing: 8) { accessory }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(_ title: LocalizedStringKey, footnote: Text? = nil) {
        self.init(title, footnote: footnote) { EmptyView() }
    }
}

/// A switch that flips in place. The whole row is its label, so VoiceOver reads it as one.
struct SettingsToggleRow: View {
    private let title: Text
    private let footnote: Text?
    @Binding private var isOn: Bool

    init(_ title: LocalizedStringKey, footnote: Text? = nil, isOn: Binding<Bool>) {
        self.title = Text(title)
        self.footnote = footnote
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabels(title: title, footnote: footnote)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}

private struct SettingsRowLabels: View {
    let title: Text
    let footnote: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            title
                .foregroundStyle(Tokens.ink)
            if let footnote {
                footnote
                    .font(.footnote)
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A row's current value. It crossfades when the setting changes, so the row changes in place.
struct SettingsValue: View {
    private let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.callout)
            .foregroundStyle(Tokens.inkSecondary)
            .lineLimit(1)
            .contentTransition(.opacity)
    }
}

/// What tapping the row does: push a page, open a menu, or leave the app.
enum SettingsGlyph {
    case push, menu, external

    var image: some View {
        let name = switch self {
        case .push: "chevron.right"
        case .menu: "chevron.up.chevron.down"
        case .external: "arrow.up.right"
        }
        return Image(systemName: name)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Tokens.inkSecondary)
            .accessibilityHidden(true)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 1)
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }
}

/// Rows sit inside a card, so the press shows as a wash over the row, not a scale.
struct SettingsPressStyle: ButtonStyle {
    @Environment(\.motionReduced) private var reduced

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Tokens.line.opacity(configuration.isPressed ? 0.6 : 0))
            .animation(Motion.animation(Motion.press, reduced: reduced), value: configuration.isPressed)
    }
}

/// The brand ribbon hanging from the About card's top edge (spec §4.2 allows it on About).
struct SettingsRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.6))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
