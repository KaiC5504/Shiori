import ImageIO
import ShioriLibrary
import SwiftUI
import UIKit

/// The book's own cover (an EPUB's cover image, a PDF's first page), else a plain card with
/// its title until M5 brings generated covers. Covers are 3:4.
struct BookCover: View {
    let book: Book
    let width: CGFloat

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.motionReduced) private var reduced
    @State private var image: UIImage?

    init(book: Book, width: CGFloat) {
        self.book = book
        self.width = width
        _image = State(initialValue: CoverThumbnails.cached(Self.key(book)))
    }

    var body: some View {
        let height = width * 4 / 3
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                TitleCard(title: book.title, width: width)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.line, lineWidth: 0.5) }
        .task(id: Self.key(book)) {
            guard book.hasCover else {
                image = nil
                return
            }
            let loaded = await CoverThumbnails.load(from: model.paths.bookDirectory(book.id), key: Self.key(book),
                                                    maxPixels: height * displayScale)
            guard loaded !== image else { return }
            withAnimation(Motion.animation(.easeOut(duration: 0.2), reduced: reduced)) { image = loaded }
        }
        .accessibilityHidden(true)
    }

    // An update can swap the cover, so the key changes with it.
    private static func key(_ book: Book) -> String {
        "\(book.id.uuidString)-\(book.lastUpdatedAt?.timeIntervalSinceReferenceDate ?? 0)"
    }
}

private struct TitleCard: View {
    let title: String
    let width: CGFloat

    var body: some View {
        let inset = width * 0.1
        Rectangle()
            .fill(Tokens.surface)
            .overlay(alignment: .topLeading) {
                Text(verbatim: title)
                    .font(.system(size: max(8, width * 0.19), weight: .bold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(4)
                    .padding(inset)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Tokens.line)
                    .frame(height: 1)
                    .padding(.horizontal, inset)
                    .padding(.bottom, inset * 1.4)
            }
    }
}

/// Downsampled covers, decoded off the main thread and kept in memory so rows scrolling back
/// into view don't decode again.
enum CoverThumbnails {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func load(from directory: URL, key: String, maxPixels: CGFloat) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .utility) {
            Self.decode(in: directory, maxPixels: maxPixels)
        }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    private static func decode(in directory: URL, maxPixels: CGFloat) -> UIImage? {
        // The importer writes `cover.<ext>`, keeping the source image's extension.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)),
              let name = names.sorted().first(where: { $0.lowercased().hasPrefix("cover.") }),
              let source = CGImageSourceCreateWithURL(directory.appending(path: name) as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 64),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }
}
