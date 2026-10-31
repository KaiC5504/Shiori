import SwiftUI

/// Shiori's own folded-paper icon set (spec §4.5). Group A is drawn in PaintGroupA.swift,
/// group B in PaintGroupB.swift.
enum ShioriIcon: String, CaseIterable, Sendable {
    // Group A
    case shelf, `import`, settings, book, search, history, filter, sort, layoutList, layoutGrid
    case add, more, close, back, forward, folder, folderAdd, document, refresh, link
    case check, warning, info, language, lock, tag, person, category, calendar
    // Group B
    case contents, bookmark, bookmarked, note, highlight, copy, share, edit, delete, typography
    case sliders, brightness, moon, sun, theme, image, quote, eye, eyeOff, play
    case pause, previous, next, headphones, speed, timer, voice, stats, flame

    var group: IconGroup {
        switch self {
        case .shelf, .import, .settings, .book, .search, .history, .filter, .sort, .layoutList, .layoutGrid,
             .add, .more, .close, .back, .forward, .folder, .folderAdd, .document, .refresh, .link,
             .check, .warning, .info, .language, .lock, .tag, .person, .category, .calendar:
            .a
        default:
            .b
        }
    }
}

enum IconGroup {
    case a, b
}

/// Everything is drawn on a 24-unit grid; `unit` is points per grid unit.
struct IconStyle {
    var unit: CGFloat
    var stroke: CGFloat
    var ink: Color
    /// The faint card fill: 0.06 at rest, 0.16 when active.
    var fill: Double

    init(size: CGFloat, ink: Color, active: Bool) {
        unit = size / 24
        stroke = 1.5 * unit
        self.ink = ink
        fill = active ? 0.16 : 0.06
    }
}

/// An icon whose `activity` springs from 0 to 1 when it turns active and back when it
/// doesn't; it jumps under reduced motion.
struct IconView: View {
    let icon: ShioriIcon
    let active: Bool
    let size: CGFloat

    @Environment(\.motionReduced) private var reduced
    @State private var activity: CGFloat

    init(_ icon: ShioriIcon, active: Bool = false, size: CGFloat = 24) {
        self.icon = icon
        self.active = active
        self.size = size
        _activity = State(initialValue: active ? 1 : 0)
    }

    var body: some View {
        IconCanvas(icon: icon, activity: activity, active: active, size: size)
            .frame(width: size, height: size)
            .onChange(of: active) { _, isActive in
                if reduced {
                    activity = isActive ? 1 : 0
                } else {
                    withAnimation(Motion.lens) { activity = isActive ? 1 : 0 }
                }
            }
            .accessibilityHidden(true)
    }
}

private struct IconCanvas: View, Animatable {
    let icon: ShioriIcon
    var activity: CGFloat
    let active: Bool
    let size: CGFloat
    @Environment(\.accent) private var accent

    var animatableData: CGFloat {
        get { activity }
        set { activity = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            var context = context
            IconPainter.paint(icon, in: &context, activity: activity,
                              style: IconStyle(size: size, ink: active ? accent : Tokens.ink, active: active))
        }
    }
}

enum IconPainter {
    static func paint(_ icon: ShioriIcon, in context: inout GraphicsContext, activity: CGFloat, style: IconStyle) {
        switch icon.group {
        case .a: paintGroupA(icon, in: &context, activity: activity, style: style)
        case .b: paintGroupB(icon, in: &context, activity: activity, style: style)
        }
    }

    /// The stand-in both group files draw until their icons exist.
    static func placeholder(in context: inout GraphicsContext, activity: CGFloat, style: IconStyle) {
        let u = style.unit
        let card = IconKit.foldedCard(CGRect(x: 5 * u, y: (4 - 2 * activity) * u, width: 14 * u, height: 17 * u),
                                      fold: 4 * u, unit: u)
        context.fill(card, with: .color(style.ink.opacity(style.fill)))
        context.stroke(card, with: .color(style.ink), style: StrokeStyle(lineWidth: style.stroke, lineJoin: .round))
    }
}

/// Path primitives on the 24-unit grid, scaled by `unit`.
enum IconKit {
    /// A card with its top-right corner folded down by `fold`.
    static func foldedCard(_ rect: CGRect, fold: CGFloat, unit: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        return path
    }

    /// A book spine: a tall rounded slab with a band near the top.
    static func spine(_ rect: CGRect, unit: CGFloat) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 0.75 * unit)
        let band = rect.minY + rect.height * 0.22
        path.move(to: CGPoint(x: rect.minX, y: band))
        path.addLine(to: CGPoint(x: rect.maxX, y: band))
        return path
    }

    /// A bookmark ribbon hanging down from `point`, with a notched tail.
    static func ribbonTab(at point: CGPoint, length: CGFloat, unit: CGFloat) -> Path {
        let half = 2 * unit
        var path = Path()
        path.move(to: CGPoint(x: point.x - half, y: point.y))
        path.addLine(to: CGPoint(x: point.x + half, y: point.y))
        path.addLine(to: CGPoint(x: point.x + half, y: point.y + length))
        path.addLine(to: CGPoint(x: point.x, y: point.y + length - 1.5 * unit))
        path.addLine(to: CGPoint(x: point.x - half, y: point.y + length))
        path.closeSubpath()
        return path
    }

    /// An open tray: a floor with raised lips at both ends.
    static func tray(_ rect: CGRect, unit: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + unit, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - unit, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
