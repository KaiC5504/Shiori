import SwiftUI
import UIKit

/// What an open book does to the phone's screen (spec §7.5): keeps it awake, and lights it at the
/// reader's own brightness when one is set. iOS keeps an app's brightness until the phone locks,
/// even after the app has gone, so the reader gives it back whenever it closes or the app leaves
/// the foreground, and takes it again on return.
@MainActor
enum ReaderScreen {
    /// The phone's brightness from just before the reader set its own; nil while the reader
    /// isn't overriding it.
    private static var systemBrightness: CGFloat?

    /// Applies the preferences. Called on open, on each change, and on coming back.
    static func hold(_ preferences: ReaderPreferences) {
        UIApplication.shared.isIdleTimerDisabled = preferences.keepsScreenAwake
        guard let screen else { return }
        if let level = preferences.brightness {
            if systemBrightness == nil { systemBrightness = screen.brightness }
            screen.brightness = CGFloat(level)
        } else {
            giveBackBrightness(to: screen)
        }
    }

    static func release() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let screen { giveBackBrightness(to: screen) }
    }

    /// The phone's own brightness, even while the reader shows its own.
    static var systemLevel: Double {
        Double(systemBrightness ?? screen?.brightness ?? 0.5)
    }

    /// The brightness the page is lit at now.
    static func level(_ preferences: ReaderPreferences) -> Double {
        preferences.brightness ?? systemLevel
    }

    private static func giveBackBrightness(to screen: UIScreen) {
        guard let systemBrightness else { return }
        screen.brightness = systemBrightness
        self.systemBrightness = nil
    }

    private static var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
}

/// The page's leftmost strip (spec §7.6). A vertical drag there sets the reader's brightness: up
/// is brighter, and the page's full height covers the whole range. A tap there still reaches the
/// page, since it is part of the back zone.
struct BrightnessEdge: View {
    let preferences: ReaderPreferences
    let onTap: (CGPoint) -> Void

    @Environment(\.motionReduced) private var reduced
    /// The level the drag started from; non-nil while dragging.
    @State private var start: Double?
    @State private var height: CGFloat = 1
    @State private var limits = 0

    static let width: CGFloat = 24

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: Self.width)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(drag)
                .onTapGesture(coordinateSpace: .global, perform: onTap)
            if start != nil {
                BrightnessLevel(level: ReaderScreen.level(preferences), theme: preferences.theme)
                    .padding(.leading, Self.width + 12)
                    .transition(reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = max($0, 1) }
        .shioriHaptic(.impact(weight: .light), trigger: limits)
        // The Aa sheet's slider does the same for VoiceOver.
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if start == nil {
                    withAnimation(Motion.animation(Motion.reveal, reduced: reduced)) {
                        start = ReaderScreen.level(preferences)
                    }
                }
                guard let start else { return }
                let raw = start - Double(value.translation.height / height)
                // Hundredths: the screen can't show finer steps, and every write is saved.
                let level = (min(max(raw, 0), 1) * 100).rounded() / 100
                guard preferences.brightness != level else { return }
                if level == 0 || level == 1 { limits += 1 }
                preferences.brightness = level
            }
            .onEnded { _ in
                withAnimation(Motion.animation(Motion.reveal, reduced: reduced)) { start = nil }
            }
    }
}

/// The glass capsule beside the strip while a drag sets brightness.
private struct BrightnessLevel: View {
    let level: Double
    let theme: ReaderTheme

    private static let track: CGFloat = 132

    var body: some View {
        VStack(spacing: 10) {
            IconView(.brightness, size: 18)
            Capsule()
                .fill(theme.inkSecondary.opacity(0.3))
                .frame(width: 6, height: Self.track)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(theme.ink)
                        .frame(width: 6, height: Self.track * level)
                }
            Text(level, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .fixedSize()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 9)
        .glassEffect(.regular.tint(theme.paper.opacity(0.35)), in: .capsule)
    }
}
