import SwiftUI

struct ImageViewerRequest: Identifiable {
    let id = UUID()
    let images: [ReaderImage]
    let start: Int
}

// Stub from the wave 3 contracts commit; R3 implements it.
/// The full-screen zoom viewer for a chapter's illustrations (spec §7.11).
struct ImageViewer: View {
    let request: ImageViewerRequest

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .onTapGesture { dismiss() }
    }
}
