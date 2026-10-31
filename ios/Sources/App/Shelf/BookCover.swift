import ImageIO
import ShioriLibrary
import SwiftUI
import UIKit

/// The book's own cover (an EPUB's cover image, a PDF's first page), else a card with its
/// title in the book's binding colour. Covers are 3:4.
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
        _image = State(initialValue: CoverThumbnails.cached(CoverThumbnails.key(book), height: width * 4 / 3))
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
                TitleCard(book: book, width: width)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.line, lineWidth: 0.5) }
        .task(id: CoverThumbnails.key(book)) {
            guard book.hasCover else {
                image = nil
                return
            }
            let loaded = await CoverThumbnails.load(from: model.paths.bookDirectory(book.id),
                                                    key: CoverThumbnails.key(book), height: height,
                                                    scale: displayScale)
            guard loaded !== image else { return }
            withAnimation(Motion.animation(.easeOut(duration: 0.2), reduced: reduced)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

private struct TitleCard: View {
    let book: Book
    let width: CGFloat

    var body: some View {
        let palette = BookPalette(bookId: book.id)
        let inset = width * 0.1
        Rectangle()
            .fill(palette.board)
            .overlay(alignment: .topLeading) {
                Text(verbatim: book.title)
                    .font(.system(size: max(7, width * 0.17), weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(4)
                    .padding(inset)
            }
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(palette.ink.opacity(0.35))
                    .frame(width: width * 0.3, height: 1)
                    .padding(.horizontal, inset)
                    .padding(.bottom, inset * 1.4)
            }
    }
}

/// Downsampled covers, decoded off the main thread and kept in memory so views scrolling back
/// into view don't decode again.
enum CoverThumbnails {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    /// An update can swap the cover, so the key changes with it.
    static func key(_ book: Book) -> String {
        "\(book.id.uuidString)-\(book.lastUpdatedAt?.timeIntervalSinceReferenceDate ?? 0)"
    }

    static func cached(_ key: String, height: CGFloat) -> UIImage? {
        cache.object(forKey: sized(key, height))
    }

    static func load(from directory: URL, key: String, height: CGFloat, scale: CGFloat) async -> UIImage? {
        let sizedKey = sized(key, height)
        if let hit = cache.object(forKey: sizedKey) { return hit }
        let maxPixels = bucket(height) * scale
        let image = await Task.detached(priority: .utility) {
            Self.decode(in: directory, maxPixels: maxPixels)
        }.value
        if let image { cache.setObject(image, forKey: sizedKey) }
        return image
    }

    // A few fixed sizes, so a list row's small decode never stands in for the shelf's big one.
    private static func bucket(_ height: CGFloat) -> CGFloat {
        [96, 192, 384, 768].first { $0 >= height } ?? 768
    }

    private static func sized(_ key: String, _ height: CGFloat) -> NSString {
        "\(key)@\(Int(bucket(height)))" as NSString
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
