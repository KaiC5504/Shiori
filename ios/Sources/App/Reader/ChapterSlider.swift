import SwiftUI

/// The chrome's chapter slider between previous and next chapter buttons. `scrub` holds the
/// knob while a finger is on it; `onJump` fires once, on release or on a button tap.
struct ChapterSlider: View {
    /// 0-based, where the knob rests.
    let chapter: Int
    let count: Int
    @Binding var scrub: Double?
    let onJump: (Int) -> Void

    @Environment(\.accent) private var accent

    init(chapter: Int, count: Int, scrub: Binding<Double?>, onJump: @escaping (Int) -> Void) {
        self.chapter = chapter
        self.count = count
        _scrub = scrub
        self.onJump = onJump
    }

    var body: some View {
        HStack(spacing: 6) {
            step(.previous, "Previous chapter", to: chapter - 1)
            // Continuous on purpose: a stepped slider draws a tick per chapter, thousands of them.
            Slider(value: value, in: 0...Double(max(count - 1, 1)), onEditingChanged: editingChanged)
                .tint(accent)
                .disabled(count < 2)
                // VoiceOver steps one chapter at a time instead of the slider's 10% jumps, and
                // each step lands, since there is no drag to release.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Chapter"))
                .accessibilityValue(Text("\(chapter + 1) of \(count)"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: jump(to: chapter + 1)
                    case .decrement: jump(to: chapter - 1)
                    @unknown default: break
                    }
                }
            step(.next, "Next chapter", to: chapter + 1)
        }
        .shioriHaptic(.selection, trigger: tick)
    }

    private var value: Binding<Double> {
        Binding(get: { scrub ?? Double(chapter) }, set: { scrub = $0 })
    }

    private func editingChanged(_ editing: Bool) {
        if editing {
            if scrub == nil { scrub = Double(chapter) }
        } else if let released = scrub {
            scrub = nil
            jump(to: Int(released.rounded()))
        }
    }

    private func jump(to target: Int) {
        guard count > 0 else { return }
        let target = min(max(target, 0), count - 1)
        if target != chapter { onJump(target) }
    }

    /// Ticks per chapter in short books, per percent in long ones, where a tick per chapter
    /// would buzz continuously.
    private var tick: Int? {
        guard let scrub, count > 1 else { return nil }
        return count > 100 ? Int(scrub / Double(count - 1) * 100) : Int(scrub.rounded())
    }

    private func step(_ icon: ShioriIcon, _ label: LocalizedStringKey, to target: Int) -> some View {
        let enabled = target >= 0 && target < count
        return Button {
            jump(to: target)
        } label: {
            IconView(icon, size: 22)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(ChromePressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(Text(label))
    }
}
