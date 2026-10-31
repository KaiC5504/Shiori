import SwiftUI

// Stub from the wave 3 contracts commit; R3 implements it.
/// An illustration in the scroll, at a height fixed by its aspect before it loads.
struct ReaderImageRow: View {
    let image: ReaderImage
    let chapter: Int
    let style: ReaderStyle

    var body: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(style.secondaryInk)
            .frame(maxWidth: .infinity)
            .aspectRatio(image.aspect ?? 4 / 3, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(style.secondaryInk.opacity(0.35)))
            .padding(.bottom, style.paragraphGap)
            .accessibilityHidden(true)
    }
}
