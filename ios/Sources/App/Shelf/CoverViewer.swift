import ShioriLibrary
import SwiftUI
import UIKit

/// A book's cover on its own, full screen on black. It lifts out of the detail page's cover
/// and settles back into it; pinch or double-tap zooms, and a tap or a swipe down closes it.
struct CoverViewer: View {
    let book: Book
    /// The cover's frame on the page below, in global coordinates.
    let source: CGRect
    /// Called once the cover has settled back, to remove the viewer without an animation.
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.motionReduced) private var reduced
    @State private var image: UIImage?
    @State private var presented = false
    @State private var closing = false
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var drag: CGSize = .zero

    private static let maxZoom: CGFloat = 5

    init(book: Book, source: CGRect, onClose: @escaping () -> Void) {
        self.book = book
        self.source = source
        self.onClose = onClose
        // Whatever size the shelf or detail page already decoded, so the flight starts with a picture.
        let key = CoverThumbnails.key(book)
        let heights: [CGFloat] = [768, 384, 192, 96]
        _image = State(initialValue: heights.lazy.compactMap { CoverThumbnails.cached(key, height: $0) }.first)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { proxy in
                let fitted = fittedSize(in: proxy.size)
                ZStack {
                    Color.black
                        .opacity(presented ? 1 - 0.8 * dismissProgress : 0)
                    cover(width: fitted.width)
                        .frame(width: fitted.width, height: fitted.height)
                        .scaleEffect(presented ? liveScale : restScale(fitted))
                        .offset(presented ? liveOffset : restOffset(in: proxy.frame(in: .global)))
                        .opacity(reduced && !presented ? 0 : 1)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: book.title))
                        .accessibilityAddTraits(.isImage)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(.rect)
                .onTapGesture(count: 2) { toggleZoom(fitted: fitted, container: proxy.size) }
                .onTapGesture { close() }
                .gesture(gestures(fitted: fitted, container: proxy.size))
            }
            .ignoresSafeArea()
            closeButton
        }
        .statusBarHidden()
        .environment(\.colorScheme, .dark)
        .accessibilityAction(.escape) { close() }
        .task { await loadFullCover() }
        .onAppear {
            withAnimation(flight) { presented = true }
        }
    }

    @ViewBuilder
    private func cover(width: CGFloat) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            BookCover(book: book, width: width)
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            IconView(.close, size: 20)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Close"))
        .padding(.trailing, 16)
        .padding(.top, 8)
        .opacity(presented ? 1 - dismissProgress : 0)
    }

    private var flight: Animation {
        Motion.animation(.spring(response: 0.42, dampingFraction: 0.88), reduced: reduced)
    }

    private var settle: Animation {
        Motion.animation(Motion.reveal, reduced: reduced)
    }

    /// 0...1 as a swipe down at rest size heads for closing.
    private var dismissProgress: CGFloat {
        guard zoom == 1 else { return 0 }
        return min(max(drag.height, 0) / 400, 1)
    }

    private var liveScale: CGFloat {
        zoom * pinch * (1 - 0.25 * dismissProgress)
    }

    private var liveOffset: CGSize {
        CGSize(width: pan.width + drag.width, height: pan.height + drag.height)
    }

    /// The cover's size and place on the page below, for the flight in and out.
    private func restScale(_ fitted: CGSize) -> CGFloat {
        guard !reduced else { return 1 }
        guard !source.isEmpty, fitted.width > 0, fitted.height > 0 else { return 0.85 }
        return min(source.width / fitted.width, source.height / fitted.height)
    }

    private func restOffset(in frame: CGRect) -> CGSize {
        guard !reduced, !source.isEmpty else { return .zero }
        return CGSize(width: source.midX - frame.midX, height: source.midY - frame.midY)
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let aspect = image.map { $0.size.width / max($0.size.height, 1) } ?? 3 / 4
        guard container.width > 0, container.height > 0, aspect > 0 else { return .zero }
        if container.width / container.height > aspect {
            return CGSize(width: container.height * aspect, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / aspect)
    }

    private func gestures(fitted: CGSize, container: CGSize) -> some Gesture {
        let magnify = MagnifyGesture()
            .onChanged { pinch = $0.magnification }
            .onEnded { value in
                withAnimation(settle) {
                    zoom = min(max(zoom * value.magnification, 1), Self.maxZoom)
                    pinch = 1
                    pan = clamped(pan, fitted: fitted, container: container)
                }
            }
        let swipe = DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if zoom > 1 {
                    pan = CGSize(width: pan.width + value.translation.width,
                                 height: pan.height + value.translation.height)
                    drag = .zero
                    withAnimation(settle) { pan = clamped(pan, fitted: fitted, container: container) }
                } else if pinch == 1,
                          value.translation.height > 120 || value.predictedEndTranslation.height > 360 {
                    close()
                } else {
                    withAnimation(settle) { drag = .zero }
                }
            }
        return SimultaneousGesture(magnify, swipe)
    }

    private func toggleZoom(fitted: CGSize, container: CGSize) {
        withAnimation(settle) {
            zoom = zoom > 1 ? 1 : 2.5
            pan = clamped(.zero, fitted: fitted, container: container)
        }
    }

    /// Keeps a zoomed cover's edges from leaving the screen's edges.
    private func clamped(_ offset: CGSize, fitted: CGSize, container: CGSize) -> CGSize {
        let maxX = max((fitted.width * zoom - container.width) / 2, 0)
        let maxY = max((fitted.height * zoom - container.height) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(flight) {
            presented = false
            zoom = 1
            pinch = 1
            pan = .zero
            drag = .zero
        } completion: {
            onClose()
        }
    }

    private func loadFullCover() async {
        guard book.hasCover else { return }
        let loaded = await CoverThumbnails.load(from: model.paths.bookDirectory(book.id),
                                                key: CoverThumbnails.key(book), height: 768, scale: displayScale)
        if let loaded { image = loaded }
    }
}
