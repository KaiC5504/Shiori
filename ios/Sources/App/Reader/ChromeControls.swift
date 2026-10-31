import SwiftUI

/// A tool in the chrome's panel: the icon over the button's label. The icon plays its own
/// motion while pressed, and swaps with a pop when the tool changes icon (Day/Night).
struct ChromeToolStyle: ButtonStyle {
    let icon: ShioriIcon

    func makeBody(configuration: Configuration) -> some View {
        ToolFace(icon: icon, pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct ToolFace<Label: View>: View {
    let icon: ShioriIcon
    let pressed: Bool
    let label: Label

    @Environment(\.motionReduced) private var reduced

    var body: some View {
        VStack(spacing: 3) {
            // Stacked, so the outgoing and incoming icons share one slot while they swap.
            ZStack {
                IconView(icon, active: pressed, size: 24)
                    .id(icon)
                    .transition(reduced ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
            .frame(width: 24, height: 24)
            label
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(.rect)
        .scaleEffect(pressed && !reduced ? 0.92 : 1)
        .opacity(pressed && reduced ? 0.6 : 1)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: pressed)
        .animation(Motion.animation(Motion.lens, reduced: reduced), value: icon)
    }
}

struct ChromePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressFace(pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct PressFace<Label: View>: View {
    let pressed: Bool
    let label: Label

    @Environment(\.motionReduced) private var reduced

    var body: some View {
        label
            .scaleEffect(pressed && !reduced ? 0.86 : 1)
            .opacity(pressed ? 0.6 : 1)
            .animation(Motion.animation(Motion.press, reduced: reduced), value: pressed)
    }
}
