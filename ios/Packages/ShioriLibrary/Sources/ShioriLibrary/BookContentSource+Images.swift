import CoreGraphics
import Foundation
import ImageIO

extension BookContentSource {
    /// The image's bytes as stored in the book. Only EPUBs carry images.
    public func imageData(at path: String) throws -> Data {
        guard let archive else { throw BookContentError.unsupportedFormat }
        return try archive.data(at: path)
    }

    /// The image's size in pixels, read from its header without decoding; nil when unreadable.
    public func imageSize(at path: String) -> CGSize? {
        guard let data = try? imageData(at: path) else { return nil }
        return Self.pixelSize(of: data)
    }

    /// Upright: an EXIF orientation of 5–8 turns the picture a quarter turn, so its width
    /// and height swap on screen.
    static func pixelSize(of data: Data) -> CGSize? {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, noCache),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, noCache) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
