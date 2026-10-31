import SwiftUI

/// The glass capsule above the bar after Open in (spec §8.2). It rises out of the bar, stays
/// 4 s, and sinks back; a swipe down dismisses it sooner.
struct ImportToast: View {
    let toast: Toast
    let open: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @Environment(\.locale) private var locale
    @Environment(\.accent) private var accent
    @State private var shown = false
    @State private var arrivals = 0

    init(toast: Toast, open: @escaping () -> Void) {
        self.toast = toast
        self.open = open
    }

    var body: some View {
        HStack(spacing: 12) {
            IconView(.check, active: shown, size: 22)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.bookId != nil {
                Button(action: open) {
                    Text("Open")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(accent.opacity(0.14), in: Capsule())
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.bookId == nil ? 16 : 8)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .glassEffect(.regular.tint(Tokens.paper.opacity(0.35)).interactive(), in: .capsule)
        .scaleEffect(shown || reduced ? 1 : 0.9, anchor: .bottom)
        .offset(y: shown || reduced ? 0 : 16)
        .opacity(shown ? 1 : 0)
        .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
            if drag.translation.height > 16 { Task { await dismiss() } }
        })
        .shioriHaptic(.success, trigger: arrivals)
        .accessibilityElement(children: .contain)
        .task(id: toast.id) {
            arrivals += 1
            withAnimation(animation) { shown = true }
            AccessibilityNotification.Announcement(String(localized: message)).post()
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await dismiss()
        }
    }

    /// Built outside a view, the message carries no locale of its own; this gives it the
    /// in-app language rather than the phone's.
    private var message: LocalizedStringResource {
        var message = toast.message
        message.locale = locale
        return message
    }

    private var animation: Animation {
        Motion.animation(Motion.reveal, reduced: reduced)
    }

    private func dismiss() async {
        guard model.toast?.id == toast.id else { return }
        withAnimation(animation) { shown = false }
        try? await Task.sleep(for: .milliseconds(reduced ? 150 : 300))
        if model.toast?.id == toast.id { model.toast = nil }
    }
}
