import CoreGraphics
import Foundation

/// Draws pages off the main actor for the thumbnail grid and the margin crop. It opens its own
/// copy of the file, so it never shares a document with the PDFView on screen.
actor PDFPageRenderer {
    private let document: CGPDFDocument?
    private let thumbnails = NSCache<NSNumber, CGImage>()

    init(url: URL) {
        document = CGPDFDocument(url as CFURL)
        thumbnails.countLimit = 120
    }

    /// Width over height of every page as shown, rotation included.
    func aspects() -> [CGFloat] {
        guard let document else { return [] }
        return (0..<document.numberOfPages).map { index in
            guard let page = document.page(at: index + 1) else { return 1 / 2.squareRoot() }
            let size = Self.shownSize(of: page)
            return size.height > 0 ? size.width / size.height : 1 / 2.squareRoot()
        }
    }

    /// The 0-based page, `pixels` wide.
    func thumbnail(_ index: Int, pixels: Int) -> CGImage? {
        let key = NSNumber(value: index)
        if let cached = thumbnails.object(forKey: key), cached.width >= pixels { return cached }
        guard let page = document?.page(at: index + 1), pixels > 0 else { return nil }
        let box = page.getBoxRect(.cropBox)
        let size = Self.shownSize(of: page)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = CGFloat(pixels) / size.width
        let height = min(max(Int((size.height * scale).rounded()), 1), pixels * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // Pages without a background are transparent; PDFView shows them on white, so the grid does too.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        // /Rotate turns the page clockwise.
        switch Self.rotation(of: page) {
        case 90:
            context.translateBy(x: 0, y: box.width)
            context.rotate(by: -.pi / 2)
        case 180:
            context.translateBy(x: box.width, y: box.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: box.height, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.translateBy(x: -box.minX, y: -box.minY)
        context.clip(to: box)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// Where the 0-based page has ink, in unrotated page space, the space `PDFPage.setBounds`
    /// takes. `.null` for a blank page.
    func contentRect(_ index: Int) -> CGRect {
        guard let page = document?.page(at: index + 1) else { return .null }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return .null }
        let height = Self.measureHeight
        let width = min(max(Int((box.width / box.height * CGFloat(height)).rounded()), 1), height * 4)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return .null }
        let sx = CGFloat(width) / box.width
        let sy = CGFloat(height) / box.height
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: sx, y: sy)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.clip(to: box)
        context.drawPDFPage(page)
        guard let data = context.data else { return .null }

        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var left = width, right = -1, top = height, bottom = -1
        for row in 0..<height {
            let line = pixels + row * rowBytes
            var first = -1, last = -1, inked = 0
            for x in 0..<width where line[x] < Self.inkLevel {
                if first < 0 { first = x }
                last = x
                inked += 1
            }
            // A lone dark pixel is scanner dust more often than text.
            guard inked >= 2 else { continue }
            top = min(top, row)
            bottom = row
            left = min(left, first)
            right = max(right, last)
        }
        guard bottom >= 0 else { return .null }
        // Row 0 of the bitmap is the top of the page, where page space has its largest y.
        return CGRect(x: box.minX + CGFloat(left) / sx,
                      y: box.minY + CGFloat(height - bottom - 1) / sy,
                      width: CGFloat(right - left + 1) / sx,
                      height: CGFloat(bottom - top + 1) / sy)
    }

    /// Enough to find a margin to within a few points; the crop adds more air than that anyway.
    private static let measureHeight = 240
    /// Off-white paper and faint scan noise stay margin; anti-aliased text edges count as ink.
    private static let inkLevel: UInt8 = 224

    private static func rotation(of page: CGPDFPage) -> Int32 {
        ((page.rotationAngle % 360) + 360) % 360
    }

    private static func shownSize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        return rotation(of: page) % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }
}

/// The margin crop: each page's content box with a little air, kept per book in Caches so a
/// long PDF is measured once.
enum PDFMargins {
    /// The crop box for a page whose ink is `content`, inside its stored `box`.
    static func crop(content: CGRect, in box: CGRect) -> CGRect {
        guard !content.isNull, !content.isEmpty, !box.isEmpty else { return box }
        let air = max(min(box.width, box.height) * 0.03, 4)
        var rect = content.insetBy(dx: -air, dy: -air)
        // A nearly blank page (a page number, a short title) would otherwise be zoomed far past the rest.
        let minWidth = box.width * 0.6
        if rect.width < minWidth { rect = rect.insetBy(dx: -(minWidth - rect.width) / 2, dy: 0) }
        let minHeight = box.height * 0.2
        if rect.height < minHeight {
            rect = CGRect(x: rect.minX, y: rect.maxY - minHeight, width: rect.width, height: minHeight)
        }
        if rect.minX < box.minX { rect.origin.x = box.minX }
        if rect.maxX > box.maxX { rect.origin.x = box.maxX - rect.width }
        if rect.minY < box.minY { rect.origin.y = box.minY }
        if rect.maxY > box.maxY { rect.origin.y = box.maxY - rect.height }
        rect = rect.intersection(box)
        // A sliver isn't worth showing the page differently from the file.
        if rect.isNull || (rect.width > box.width * 0.97 && rect.height > box.height * 0.97) { return box }
        return rect
    }

    static func load(contentHash: String) -> [Int: CGRect] {
        guard let url = file(contentHash),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return [:] }
        var rects: [Int: CGRect] = [:]
        for (key, values) in stored {
            guard let index = Int(key) else { continue }
            rects[index] = values.count == 4
                ? CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                : .null
        }
        return rects
    }

    static func save(_ rects: [Int: CGRect], contentHash: String) {
        guard let url = file(contentHash) else { return }
        var stored: [String: [Double]] = [:]
        for (index, rect) in rects {
            stored[String(index)] = rect.isNull
                ? []
                : [rect.minX, rect.minY, rect.width, rect.height].map { Double($0) }
        }
        // A cache only: if the write fails, the pages are measured again next time.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(stored).write(to: url, options: .atomic)
    }

    /// Named by the file's hash, so an updated PDF is measured afresh.
    private static func file(_ contentHash: String) -> URL? {
        guard !contentHash.isEmpty,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return caches.appending(path: "PDFMargins", directoryHint: .isDirectory)
            .appending(path: "\(contentHash)-v1.json")
    }
}
