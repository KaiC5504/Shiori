import SwiftUI

extension EnvironmentValues {
    @Entry var hapticsEnabled = true
}

extension View {
    /// The only way Shiori plays haptics, so the Settings switch silences all of them.
    func shioriHaptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(ShioriHaptic(feedback: feedback, trigger: trigger))
    }
}

private struct ShioriHaptic<T: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: T
    @Environment(\.hapticsEnabled) private var enabled

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { _, _ in enabled }
    }
}
