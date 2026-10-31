import SwiftUI

extension EnvironmentValues {
    /// The system's Reduce Motion or Shiori's own switch. Read this, never
    /// `accessibilityReduceMotion` directly.
    @Entry var motionReduced = false
}

/// Shiori's springs (spec §4.6). Under reduced motion every one becomes a short crossfade.
enum Motion {
    static let lens = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let reveal = Animation.spring(response: 0.45, dampingFraction: 0.86)
    static let press = Animation.snappy(duration: 0.2)

    static func animation(_ base: Animation, reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : base
    }
}

extension View {
    /// Fades in with an 8 pt rise, 0.04 s after the previous index (capped at 12).
    func staggeredReveal(_ index: Int) -> some View {
        modifier(StaggeredReveal(index: index))
    }
}

private struct StaggeredReveal: ViewModifier {
    let index: Int
    @Environment(\.motionReduced) private var reduced
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduced ? 0 : 8)
            .onAppear {
                withAnimation(Motion.animation(Motion.reveal, reduced: reduced)
                    .delay(Double(min(index, 12)) * 0.04)) {
                    shown = true
                }
            }
    }
}
