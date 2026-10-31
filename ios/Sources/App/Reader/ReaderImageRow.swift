import ImageIO
import SwiftUI
import UIKit

/// An illustration in the scroll. Its height comes from the aspect read with the chapter and
/// never changes when the picture arrives: a row that grew would shift the text under the
/// saved paragraph.
struct ReaderImageRow: View {
    let image: ReaderImage
    let chapter: Int
    let style: ReaderStyle

    @Environment(\.readerModel) private var reader
    @Environment(\.openReaderImage) private var openImage
    @Environment(\.motionReduced) private var reduced
    @Environment(\.displayScale) private var displayScale
    @State private var picture: UIImage?
    @State private var failed = false
    @State private var width: CGFloat = 0

    init(image: ReaderImage, chapter: Int, style: ReaderStyle) {
        self.image = image
        self.chapter = chapter
        self.style = style
    }

    /// Width over height: 4:3 when the header couldn't be read, and never taller than 1.5
    /// widths, so one tall plate can't fill several screens.
    static func frameAspect(_ aspect: CGFloat?) -> CGFloat {
        max(aspect ?? 4 / 3, 1 / 1.5)
    }

    var body: some View {
        let shown = picture ?? reader.flatMap { ReaderImageLoader.cached(image, in: $0) }
        Button(action: open) {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(Self.frameAspect(image.aspect), contentMode: .fit)
                .overlay { face(shown) }
                .contentShape(.rect)
        }
        .buttonStyle(PlatePressStyle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.bottom, style.paragraphGap)
        .accessibilityLabel(Text("Illustration"))
        .accessibilityAddTraits(.isImage)
        .task(id: width > 0) {
            guard width > 0 else { return }
            if shown == nil { await load() }
            #if DEBUG
            await openForDemo()
            #endif
        }
    }

    private func face(_ shown: UIImage?) -> some View {
        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay(alignment: .bottom) {
                        if style.theme != .night {
                            Rectangle()
                                .fill(style.secondaryInk.opacity(0.3))
                                .frame(height: 1 / displayScale)
                                .offset(y: 6)
                        }
                    }
                    // A full-white plate glares on night paper, so it dims with the night text.
                    .opacity(style.theme == .night ? max(style.nightTextBrightness, 0.7) : 1)
                    .transition(reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .animation(Motion.animation(.easeOut(duration: 0.35), reduced: reduced), value: shown == nil)
    }

    private var placeholder: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        return shape
            .fill(style.secondaryInk.opacity(0.08))
            .overlay { shape.strokeBorder(style.secondaryInk.opacity(0.25), lineWidth: 1) }
            .overlay {
                if failed || reduced {
                    IconView(.image, size: 28)
                        .opacity(0.45)
                } else {
                    IconView(.image, size: 28)
                        .phaseAnimator([false, true]) { icon, bright in
                            icon.opacity(bright ? 0.6 : 0.3)
                        } animation: { _ in .easeInOut(duration: 0.9) }
                }
            }
    }

    private func load() async {
        guard let reader else { return }
        let height = width / Self.frameAspect(image.aspect)
        let loaded = await ReaderImageLoader.load(image, from: reader, maxPixel: max(width, height) * displayScale,
                                                  caching: true)
        guard !Task.isCancelled else { return }
        picture = loaded
        failed = loaded == nil
    }

    private func open() {
        guard let openImage else { return }
        let images = reader?.images(inChapter: chapter) ?? []
        if let index = images.firstIndex(of: image) {
            openImage(ImageViewerRequest(images: images, start: index))
        } else {
            openImage(ImageViewerRequest(images: [image], start: 0))
        }
    }

    #if DEBUG
    @MainActor private static var demoOpened = false

    private func openForDemo() async {
        guard DemoLaunch.opensImageViewer, !Self.demoOpened else { return }
        // Past the reader's own cover sliding in and the demo jump landing; a cover asked for
        // during either is dropped.
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, !Self.demoOpened else { return }
        Self.demoOpened = true
        open()
    }
    #endif
}

private struct PlatePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlateFace(pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct PlateFace<Label: View>: View {
    let pressed: Bool
    let label: Label

    @Environment(\.motionReduced) private var reduced

    var body: some View {
        label
            .scaleEffect(pressed && !reduced ? 0.98 : 1)
            .opacity(pressed ? 0.85 : 1)
            .animation(Motion.animation(Motion.press, reduced: reduced), value: pressed)
    }
}

/// Decodes illustrations at the size they're shown, off the main actor, and keeps the scroll's
/// recent ones so a row scrolled back into view doesn't flash its placeholder.
@MainActor
enum ReaderImageLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // A screen-wide plate decodes to a few MB; this holds a chapter's worth, not a book's.
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    /// Archive paths repeat across books ("Images/001.jpg"), so the key carries the book.
    private static func key(_ image: ReaderImage, _ reader: ReaderModel) -> NSString {
        "\(reader.book.id.uuidString)|\(image.path)" as NSString
    }

    static func cached(_ image: ReaderImage, in reader: ReaderModel) -> UIImage? {
        cache.object(forKey: key(image, reader))
    }

    /// Nil when the bytes are missing or aren't a picture ImageIO reads (SVG, for one).
    static func load(_ image: ReaderImage, from reader: ReaderModel, maxPixel: CGFloat,
                     caching: Bool) async -> UIImage? {
        guard let data = await reader.imageData(at: image.path) else { return nil }
        let picture = await Task.detached(priority: .userInitiated) {
            decode(data, maxPixel: maxPixel)
        }.value
        if caching, let picture, let cg = picture.cgImage {
            cache.setObject(picture, forKey: key(image, reader), cost: cg.bytesPerRow * cg.height)
        }
        return picture
    }

    /// A thumbnail at most `maxPixel` on its long side, upright, never the full decode.
    nonisolated static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard maxPixel >= 1, let source = CGImageSourceCreateWithData(data as CFData, noCache) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded(.up)),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}
