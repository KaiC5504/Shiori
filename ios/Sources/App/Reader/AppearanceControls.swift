import SwiftUI

/// The Aa sheet's small archive label, a Latin mono code and then the localised name:
/// "TEXT / 字号".
struct AppearanceLabel: View {
    let code: String
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "\(code) / ")
            Text(title)
        }
        .font(.system(.caption2, design: .monospaced))
        .tracking(1.5)
        .textCase(.uppercase)
        .foregroundStyle(Tokens.inkSecondary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isHeader)
    }
}

struct AppearanceHairline: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A strip of choices with a lens that slides to the chosen one. The lens animates only
/// inside the strip, so the page behind re-lays out at once rather than in a spring.
struct AppearanceSegments<Option: Hashable, Content: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Content

    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced
    @Namespace private var lens

    init(_ options: [Option], selection: Binding<Option>, @ViewBuilder label: @escaping (Option) -> Content) {
        self.options = options
        _selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                cell(option)
            }
        }
        .padding(3)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
        .animation(Motion.animation(Motion.lens, reduced: reduced), value: selection)
        .shioriHaptic(.selection, trigger: selection)
    }

    private func cell(_ option: Option) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            label(option)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Tokens.paper : Tokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if selected {
                        lensShape
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

/// A named slider with its value on the trailing edge.
struct AppearanceSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: Text

    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         valueText: Text) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.valueText = valueText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .foregroundStyle(Tokens.ink)
                Spacer(minLength: 12)
                valueText
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary)
                    .contentTransition(.numericText(value: value))
            }
            Slider(value: $value, in: range, step: step)
                .tint(accent)
                .accessibilityLabel(Text(title))
                .accessibilityValue(valueText)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A paper theme as a little sheet of that paper with "Aa" in its ink. Follow appearance is
/// split corner to corner into the app's light and dark paper.
struct AppearanceSwatch: View {
    let theme: ReaderTheme
    /// Night shows its brightness, so the swatch dims with the slider.
    let ink: Color
    let selected: Bool
    let ring: Namespace.ID
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.motionReduced) private var reduced

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    paper
                    if theme == .followAppearance {
                        paper
                            .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
                            .mask { LowerTriangle() }
                    }
                }
                .frame(maxWidth: 72)
                .frame(height: 58)
                .background {
                    if selected {
                        selectionRing
                    }
                }
                Text(theme.title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Tokens.ink : Tokens.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(AppearancePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(theme.title))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("aa.theme.\(theme.rawValue)")
    }

    private var paper: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return shape
            .fill(theme.paper)
            .overlay {
                Text(verbatim: "Aa")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(theme == .night ? ink : theme.ink)
            }
            .overlay { shape.strokeBorder(Tokens.line, lineWidth: 1) }
    }

    @ViewBuilder
    private var selectionRing: some View {
        let shape = RoundedRectangle(cornerRadius: 11).strokeBorder(Tokens.ink, lineWidth: 2).padding(-4)
        if reduced {
            shape.transition(.opacity)
        } else {
            shape.matchedGeometryEffect(id: "ring", in: ring)
        }
    }
}

private struct LowerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Free-standing controls give a little under the finger; rows in cards use a wash instead.
struct AppearancePressStyle: ButtonStyle {
    @Environment(\.motionReduced) private var reduced

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? 0.94 : 1)
            .opacity(configuration.isPressed && reduced ? 0.7 : 1)
            .animation(Motion.animation(Motion.press, reduced: reduced), value: configuration.isPressed)
    }
}
