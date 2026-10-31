import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// A PDF's title, author and first-page cover (spec §8.3). PDFs are stored whole; reading
/// them comes with the PDF reader.
enum PDFImport {
    struct Info {
        var title: String?
        var author: String?
        var coverJPEG: Data?
    }

    static func read(_ url: URL, coverHeight: Int = 600) throws -> Info {
        guard let document = PDFDocument(url: url) else { throw ImportFailure.unreadable("not a PDF") }
        // A PDF with only an owner password opens unlocked; one that needs a password to open can't be shown.
        if document.isLocked { throw ImportFailure.drmProtected }
        guard document.pageCount > 0 else { throw ImportFailure.empty }
        let attributes = document.documentAttributes ?? [:]
        return Info(title: usableTitle(attributes[PDFDocumentAttribute.titleAttribute] as? String),
                    author: trimmed(attributes[PDFDocumentAttribute.authorAttribute] as? String),
                    coverJPEG: document.page(at: 0).flatMap { jpeg(of: $0, height: coverHeight) })
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// Word and other exporters often leave "Untitled" or the source file's name in the
    /// title, and the PDF's own file name is the better title then.
    private static func usableTitle(_ title: String?) -> String? {
        guard let title = trimmed(title) else { return nil }
        let lower = title.lowercased()
        if lower == "untitled" || lower.hasPrefix("microsoft word - ") { return nil }
        if lower.range(of: #"\.(docx?|pdf|txt|rtf|pages|indd|tex)$"#, options: .regularExpression) != nil { return nil }
        return title
    }

    /// Drawn with Core Graphics rather than `thumbnail(of:for:)`, which returns a UIImage or
    /// an NSImage depending on the platform.
    static func jpeg(of page: PDFPage, height: Int) -> Data? {
        let box = page.bounds(for: .mediaBox)
        let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        guard size.width > 0, size.height > 0, height > 0 else { return nil }
        let scale = CGFloat(height) / size.height
        let width = min(max(Int((size.width * scale).rounded()), 1), height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // Pages without a background are transparent, which JPEG would turn black.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
