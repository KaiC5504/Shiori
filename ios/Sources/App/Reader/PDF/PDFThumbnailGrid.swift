import SwiftUI

/// Every page as a thumbnail, the current one ringed in the accent; a tap jumps there. Cells
/// draw their page only as they scroll in, so a long PDF opens the grid at once.
struct PDFThumbnailGrid: View {
    @Environment(\.dismiss) private var dismiss
    let renderer: PDFPageRenderer
    /// 0-based.
    let current: Int
    let onSelect: (Int) -> Void

    @State private var aspects: [CGFloat]?

    var body: some View {
        VStack(spacing: 0) {
            PDFSheetHeader(title: "Thumbnails")
            ScrollViewReader { proxy in
                ScrollView {
                    if let aspects {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 14, alignment: .bottom)],
                                  spacing: 18) {
                            ForEach(aspects.indices, id: \.self) { index in
                                cell(index, aspect: aspects[index])
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
                .onChange(of: aspects == nil) {
                    Task {
                        await Task.yield()
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
        }
        .background(Tokens.surface)
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tokens.surface)
        .task { aspects = await renderer.aspects() }
    }

    private func cell(_ index: Int, aspect: CGFloat) -> some View {
        Button {
            onSelect(index)
            dismiss()
        } label: {
            PDFThumbnailCell(renderer: renderer, index: index, aspect: aspect, isCurrent: index == current)
        }
        .buttonStyle(ChromePressStyle())
        .accessibilityLabel(Text("Page \(index + 1)"))
        .accessibilityValue(index == current ? Text("Reading now") : Text(verbatim: ""))
        .accessibilityAddTraits(index == current ? .isSelected : [])
    }
}

private struct PDFThumbnailCell: View {
    let renderer: PDFPageRenderer
    let index: Int
    let aspect: CGFloat
    let isCurrent: Bool

    @Environment(\.accent) private var accent
    @Environment(\.displayScale) private var displayScale
    @Environment(\.motionReduced) private var reduced
    @State private var image: CGImage?
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            page
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(accent, lineWidth: 2)
                        .opacity(isCurrent ? 1 : 0)
                }
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isCurrent ? accent : Tokens.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
    }

    private var page: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return Tokens.paper
            .aspectRatio(max(aspect, 0.1), contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Tokens.line, lineWidth: 1) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: width) {
                guard width > 0 else { return }
                let pixels = Int((width * displayScale).rounded(.up))
                let drawn = await renderer.thumbnail(index, pixels: pixels)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.animation(.easeOut(duration: 0.25), reduced: reduced)) { image = drawn }
            }
    }
}
