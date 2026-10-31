import CoreGraphics
import Foundation

/// The spine shelf's sizes, all derived from the width it is given.
///
/// The shelf is drawn in an oblique projection: fronts stay flat and readable while depth runs
/// up and to the right. That projection is affine, so every face of a book is one
/// `CGAffineTransform` of a flat view, cheap enough to recompute every scroll frame.
struct ShelfMetrics: Equatable, Sendable {
    static let depthX: CGFloat = 0.24
    static let depthY: CGFloat = 0.18
    static let crestTurn: CGFloat = 50 * .pi / 180
    static let crestScale: CGFloat = 0.08

    let viewport: CGFloat
    let reduced: Bool
    let coverWidth: CGFloat
    let coverHeight: CGFloat
    let thickness: CGFloat
    /// One slot of the scroll row; the snapping unit.
    let pitch: CGFloat
    let lift: CGFloat
    let drop: CGFloat
    let ribbonRise: CGFloat
    /// The crest's on-screen width, turned and scaled.
    let crestWidth: CGFloat
    /// How far the books either side of the crest step aside to make room for it.
    let spread: CGFloat
    let baseline: CGFloat
    let stageHeight: CGFloat

    init(width: CGFloat, reduced: Bool) {
        viewport = width
        self.reduced = reduced
        coverWidth = min(max(width * 0.3, 104), 176).rounded()
        coverHeight = (coverWidth * 4 / 3).rounded()
        thickness = (coverWidth * 0.25).rounded()
        pitch = thickness + max(4, (coverWidth * 0.04).rounded())
        lift = (coverHeight * 0.08).rounded()
        drop = (coverHeight * 0.09).rounded()
        ribbonRise = (coverWidth * 0.08).rounded()
        let nominal = BookBlock(thickness: thickness, depth: coverWidth, height: coverHeight)
        crestWidth = reduced
            ? coverWidth
            : nominal.halfWidth(turn: Self.crestTurn) * 2 * (1 + Self.crestScale)
        spread = crestWidth - pitch * 0.4
        baseline = (coverHeight + coverWidth * Self.depthY + lift + ribbonRise + 10).rounded()
        stageHeight = baseline + drop + 18
    }
}

/// A book as a solid block. `depth` is the cover's width, which runs back into the shelf.
struct BookBlock: Equatable, Sendable {
    var thickness: CGFloat
    var depth: CGFloat
    var height: CGFloat

    init(thickness: CGFloat, depth: CGFloat, height: CGFloat) {
        self.thickness = thickness
        self.depth = depth
        self.height = height
    }

    /// Heights vary a little per book so the row reads as a real shelf; long books are thicker.
    init(bookId: UUID, chapterCount: Int, metrics: ShelfMetrics) {
        let tall = 0.86 + 0.14 * BookHash.unit(bookId, salt: 0)
        let bulk = min(1, log10(CGFloat(max(chapterCount, 1)) + 1) / 3.3)
        thickness = (metrics.thickness * (0.74 + 0.26 * bulk)).rounded()
        depth = (metrics.coverWidth * tall).rounded()
        height = (metrics.coverHeight * tall).rounded()
    }

    /// The box's centre projects to the origin, so its outline is symmetric about it.
    func halfWidth(turn: CGFloat) -> CGFloat {
        let project = Oblique(turn: turn)
        let hw = thickness / 2, hd = depth / 2
        return [(-hw, hd), (hw, hd), (hw, -hd), (-hw, -hd)]
            .map { abs(project($0.0, 0, $0.1).x) }
            .max() ?? 0
    }
}

/// Every flat view that makes up one book on the shelf, in drawing order.
enum BookFace: Sendable {
    case shadow, top, cover, coverShade, ribbon, spine, spineShade
}

/// Where one book stands for a given scroll position. `crest` is 1 at the centre of the row
/// and eases to 0 one slot away; the next book's crest rises as this one's falls, so the two
/// always share the room the crest needs and the order never has to change.
struct BookPose {
    let crest: CGFloat
    private let reduced: Bool
    private let block: BookBlock
    private let project: Oblique
    private let place: CGAffineTransform
    private let flat: CGAffineTransform
    private let shadowCentre: CGPoint
    private let shadowScale: CGFloat
    private let ribbonRise: CGFloat

    /// `offset` is how far the slot's centre is from the row's centre, in points.
    init(offset: CGFloat, block: BookBlock, metrics: ShelfMetrics) {
        let d = offset / metrics.pitch
        let t = max(0, 1 - abs(d))
        let crest = t * t * (3 - 2 * t)
        let x = metrics.pitch / 2 + (d < 0 ? -1 : 1) * metrics.spread / 2 * (1 - crest)
        let hd = block.depth / 2
        self.crest = crest
        self.block = block
        reduced = metrics.reduced
        ribbonRise = metrics.ribbonRise
        if metrics.reduced {
            project = Oblique(turn: 0)
            let anchor = project(0, 0, hd)
            place = CGAffineTransform(translationX: x - anchor.x, y: metrics.baseline - anchor.y)
            flat = CGAffineTransform(translationX: x - hd, y: metrics.baseline - block.height)
            shadowCentre = CGPoint(x: x, y: metrics.baseline)
            shadowScale = 1
        } else {
            project = Oblique(turn: crest * ShelfMetrics.crestTurn)
            // Shelved books line up on their spines; the crest centres its whole outline.
            let ax = project(0, 0, hd).x * (1 - crest)
            let ay = ShelfMetrics.depthY * (block.thickness / 2 * project.s + hd * project.c)
            let scale = 1 + ShelfMetrics.crestScale * crest
            // 1 for the crest's neighbours, a fifth two slots out, nothing beyond.
            let wave = d * d * exp(1 - d * d)
            let y = metrics.baseline - metrics.lift * wave + metrics.drop * crest
            place = CGAffineTransform(translationX: -ax, y: -ay)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: x, y: y))
            flat = .identity
            shadowCentre = CGPoint.zero.applying(place)
            shadowScale = scale
        }
    }

    func transform(_ face: BookFace) -> CGAffineTransform {
        let hw = block.thickness / 2, hd = block.depth / 2, h = block.height
        switch face {
        case .shadow:
            let size = Self.shadowSize(block)
            return CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
                .concatenating(CGAffineTransform(scaleX: shadowScale, y: shadowScale))
                .concatenating(CGAffineTransform(translationX: shadowCentre.x, y: shadowCentre.y))
        case .top:
            return affine(V3(-hw, -h, -hd), u: V3(1, 0, 0), v: V3(0, 0, 1))
        case .spine, .spineShade:
            return affine(V3(-hw, -h, hd), u: V3(1, 0, 0), v: V3(0, 1, 0))
        case .cover, .coverShade:
            return reduced ? flat : coverPlane
        case .ribbon:
            return CGAffineTransform(translationX: Self.ribbonInset(block), y: -ribbonRise)
                .concatenating(reduced ? flat : coverPlane)
        }
    }

    /// Reduced motion keeps the row still and crossfades the crest's spine into its flat cover.
    /// The cover only fades in over the last half of the approach, so two flat covers never
    /// overlap mid-scroll.
    func opacity(_ face: BookFace) -> Double {
        let c = Double(crest)
        let t = max(0, c * 2 - 1)
        let flat = t * t * (3 - 2 * t)
        switch face {
        case .shadow: return (reduced ? 0.3 * flat : 0.5 * c)
        case .top, .spine: return reduced ? 1 - flat : 1
        case .cover, .ribbon: return reduced ? flat : 1
        case .coverShade: return reduced ? 0 : 0.55 * (1 - c)
        case .spineShade: return reduced ? 0 : 0.3 * c
        }
    }

    static func shadowSize(_ block: BookBlock) -> CGSize {
        CGSize(width: block.depth * 1.3, height: block.depth * 0.22)
    }

    static func ribbonInset(_ block: BookBlock) -> CGFloat {
        (block.depth * 0.72).rounded()
    }

    static func ribbonSize(_ block: BookBlock, rise: CGFloat) -> CGSize {
        CGSize(width: max(6, (block.depth * 0.075).rounded()), height: rise + (block.depth * 0.3).rounded())
    }

    // The front cover is the +x face: it runs from the spine's edge back to the fore-edge.
    private var coverPlane: CGAffineTransform {
        affine(V3(block.thickness / 2, -block.height, block.depth / 2), u: V3(0, 0, -1), v: V3(0, 1, 0))
    }

    private func affine(_ origin: V3, u: V3, v: V3) -> CGAffineTransform {
        let o = project(origin.x, origin.y, origin.z)
        let pu = project(u.x, u.y, u.z)
        let pv = project(v.x, v.y, v.z)
        return CGAffineTransform(a: pu.x, b: pu.y, c: pv.x, d: pv.y, tx: o.x, ty: o.y).concatenating(place)
    }
}

private struct V3 {
    var x, y, z: CGFloat

    init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// x right, y down, z toward the reader. Turning swings the front cover toward the reader.
struct Oblique {
    let c: CGFloat
    let s: CGFloat

    init(turn: CGFloat) {
        c = cos(turn)
        s = sin(turn)
    }

    func callAsFunction(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        let xr = x * c - z * s
        let zr = x * s + z * c
        return CGPoint(x: xr - ShelfMetrics.depthX * zr, y: y + ShelfMetrics.depthY * zr)
    }
}

/// Stable per-book numbers in 0...1, from the UUID's random tail.
enum BookHash {
    static func unit(_ id: UUID, salt: Int) -> CGFloat {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let i = 10 + (salt % 3) * 2
        return CGFloat(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])) / CGFloat(UInt16.max)
    }
}
