import CoreGraphics
import Foundation

// Stub from the wave 3 contracts commit; R3 implements it.
extension BookContentSource {
    public func imageData(at path: String) throws -> Data {
        throw BookContentError.unsupportedFormat
    }

    /// The image's size in pixels, read from its header without decoding; nil when unreadable.
    public func imageSize(at path: String) -> CGSize? {
        nil
    }
}
