import SwiftUI

/// Stub from wave 1's contracts commit; B2 builds the glass toast.
struct ImportToast: View {
    let toast: Toast
    let open: () -> Void

    init(toast: Toast, open: @escaping () -> Void) {
        self.toast = toast
        self.open = open
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .foregroundStyle(Tokens.ink)
                .lineLimit(2)
            if toast.bookId != nil {
                Button("Open", action: open)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Tokens.surface, in: Capsule())
    }
}
