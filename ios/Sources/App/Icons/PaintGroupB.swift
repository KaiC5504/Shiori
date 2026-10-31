import SwiftUI

extension IconPainter {
    static func paintGroupB(_ icon: ShioriIcon, in context: inout GraphicsContext, activity: CGFloat, style: IconStyle) {
        let pen = Pen(context: context, style: style)
        let t = activity
        switch icon {
        case .contents: GroupB.contents(pen, t)
        case .bookmark: GroupB.bookmark(pen, t)
        case .bookmarked: GroupB.bookmarked(pen, t)
        case .note: GroupB.note(pen, t)
        case .highlight: GroupB.highlight(pen, t)
        case .copy: GroupB.copy(pen, t)
        case .share: GroupB.share(pen, t)
        case .edit: GroupB.edit(pen, t)
        case .delete: GroupB.delete(pen, t)
        case .typography: GroupB.typography(pen, t)
        case .sliders: GroupB.sliders(pen, t)
        case .brightness: GroupB.brightness(pen, t)
        case .moon: GroupB.moon(pen, t)
        case .sun: GroupB.sun(pen, t)
        case .theme: GroupB.theme(pen, t)
        case .image: GroupB.image(pen, t)
        case .quote: GroupB.quote(pen, t)
        case .eye: GroupB.eye(pen, t)
        case .eyeOff: GroupB.eyeOff(pen, t)
        case .play: GroupB.play(pen, t)
        case .pause: GroupB.pause(pen, t)
        case .previous: GroupB.skip(pen, t, forward: false)
        case .next: GroupB.skip(pen, t, forward: true)
        case .headphones: GroupB.headphones(pen, t)
        case .speed: GroupB.speed(pen, t)
        case .timer: GroupB.timer(pen, t)
        case .voice: GroupB.voice(pen, t)
        case .stats: GroupB.stats(pen, t)
        case .flame: GroupB.flame(pen, t)
        default: placeholder(in: &context, activity: activity, style: style)
        }
    }
}

/// Draws in grid units. Copies of a `GraphicsContext` share its canvas, so a clipped pen
/// draws onto the same icon.
private struct Pen {
    var context: GraphicsContext
    let style: IconStyle

    var u: CGFloat { style.unit }

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * u, y: y * u)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x * u, y: y * u, width: width * u, height: height * u)
    }

    func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: rect(x - radius, y - radius, 2 * radius, 2 * radius))
    }

    func lines(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.addLines(points.map { p($0.0, $0.1) })
        return path
    }

    func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = lines(points)
        path.closeSubpath()
        return path
    }

    func segment(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        lines([(x0, y0), (x1, y1)])
    }

    /// The set's paper: a faint fill under the ink outline.
    func sheet(_ path: Path, tone: Double? = nil) {
        context.fill(path, with: .color(style.ink.opacity(tone ?? style.fill)))
        ink(path)
    }

    func ink(_ path: Path) {
        context.stroke(path, with: .color(style.ink),
                       style: StrokeStyle(lineWidth: style.stroke, lineCap: .round, lineJoin: .round))
    }

    func solid(_ path: Path, opacity: Double = 1) {
        context.fill(path, with: .color(style.ink.opacity(opacity)))
    }

    func inside(_ path: Path) -> Pen {
        var pen = self
        pen.context.clip(to: path)
        return pen
    }

    func outside(_ path: Path) -> Pen {
        var pen = self
        pen.context.clip(to: path, options: .inverse)
        return pen
    }
}

private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// `t`'s progress through the window from `start` to `end`, for staggered parts.
private func stage(_ t: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
    min(max((t - start) / (end - start), 0), 1)
}

/// Zero at both ends and 1 halfway: a motion that comes back to where it started.
private func bump(_ t: CGFloat) -> CGFloat {
    sin(.pi * min(max(t, 0), 1))
}

private func rotation(_ degrees: CGFloat, around center: CGPoint) -> CGAffineTransform {
    CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: degrees * .pi / 180)
        .translatedBy(x: -center.x, y: -center.y)
}

private func scaling(_ x: CGFloat, _ y: CGFloat, around center: CGPoint) -> CGAffineTransform {
    CGAffineTransform(translationX: center.x, y: center.y)
        .scaledBy(x: x, y: y)
        .translatedBy(x: -center.x, y: -center.y)
}

private func shift(_ x: CGFloat, _ y: CGFloat, _ pen: Pen) -> CGAffineTransform {
    CGAffineTransform(translationX: x * pen.u, y: y * pen.u)
}

private enum GroupB {
    static func contents(_ g: Pen, _ t: CGFloat) {
        g.sheet(IconKit.foldedCard(g.rect(4.5, 3, 15, 18), fold: 4 * g.u, unit: g.u))
        let rows: [(y: CGFloat, rest: CGFloat, active: CGFloat)] = [(9, 13.5, 16), (13.5, 15.5, 16), (18, 12, 15)]
        for (i, row) in rows.enumerated() {
            let k = stage(t, CGFloat(i) * 0.2, CGFloat(i) * 0.2 + 0.6)
            g.solid(g.circle(8, row.y, 1))
            g.ink(g.segment(10.75, row.y, mix(row.rest, row.active, k), row.y))
        }
    }

    static func bookmark(_ g: Pen, _ t: CGFloat) {
        g.sheet(ribbon(g, length: mix(15, 17.5, t)))
        g.ink(g.segment(6, 3, 18, 3))
    }

    static func bookmarked(_ g: Pen, _ t: CGFloat) {
        let swing = 9 * sin(2 * .pi * min(max(t, 0), 1))
        let path = ribbon(g, length: 17.5).applying(rotation(swing, around: g.p(12, 3)))
        g.solid(path)
        g.ink(path)
        g.ink(g.segment(6, 3, 18, 3))
    }

    private static func ribbon(_ g: Pen, length: CGFloat) -> Path {
        IconKit.ribbonTab(at: g.p(12, 3), length: length * g.u, unit: g.u)
            .applying(scaling(1.75, 1, around: g.p(12, 3)))
    }

    static func note(_ g: Pen, _ t: CGFloat) {
        let center = g.p(12, 12)
        let tilt = rotation(-5 * t, around: center)
        let paper = IconKit.foldedCard(g.rect(4, 4, 16, 16), fold: mix(3.5, 5.5, t) * g.u, unit: g.u)
            .applying(rotation(90, around: center))
        g.sheet(paper.applying(tilt))
        var writing = g.segment(7.5, 9, 16.5, 9)
        writing.addPath(g.segment(7.5, 12.5, 16.5, 12.5))
        writing.addPath(g.segment(7.5, 16, 12, 16))
        g.ink(writing.applying(tilt))
    }

    static func highlight(_ g: Pen, _ t: CGFloat) {
        let tipX = mix(9.5, 13.5, t)
        g.solid(Path(roundedRect: g.rect(3.5, 14.5, tipX - 3.5, 4), cornerRadius: g.u), opacity: 0.4)
        let place = shift(tipX, 16, g).rotated(by: 30 * .pi / 180)
        let body = Path(roundedRect: g.rect(-2.25, -11, 4.5, 6), cornerRadius: g.u)
        let nib = g.polygon([(-2.25, -5), (2.25, -5), (1.2, -0.4), (-1.2, 0.4)])
        g.sheet(body.applying(place))
        g.sheet(nib.applying(place))
    }

    static func copy(_ g: Pen, _ t: CGFloat) {
        let spread = 0.75 * t
        let front = g.rect(9 + spread, 8 + spread, 10.5, 12.5)
        g.outside(Path(front.insetBy(dx: -1.25 * g.u, dy: -1.25 * g.u)))
            .sheet(IconKit.foldedCard(g.rect(4.5 - spread, 3.5 - spread, 10.5, 12.5), fold: 3 * g.u, unit: g.u))
        g.sheet(IconKit.foldedCard(front, fold: 3 * g.u, unit: g.u))
    }

    static func share(_ g: Pen, _ t: CGFloat) {
        g.sheet(IconKit.tray(g.rect(4.5, 10.5, 15, 10), unit: g.u))
        let lift = 1.5 * t
        g.ink(g.segment(12, 15, 12, 3.5 - lift))
        g.ink(g.lines([(8.5, 7 - lift), (12, 3.5 - lift), (15.5, 7 - lift)]))
    }

    static func edit(_ g: Pen, _ t: CGFloat) {
        let tipX = mix(6, 8.5, t)
        g.ink(g.segment(3.5, 19, tipX, 19))
        let place = shift(tipX, 19, g).rotated(by: 40 * .pi / 180)
        var body = Path(roundedRect: g.rect(-2, -17, 4, 13.5), cornerRadius: 0.75 * g.u)
        body.addPath(g.segment(-2, -14.5, 2, -14.5))
        g.sheet(body.applying(place))
        g.sheet(g.polygon([(-2, -3.5), (0, 0), (2, -3.5)]).applying(place))
        g.solid(g.polygon([(-0.8, -1.4), (0, 0), (0.8, -1.4)]).applying(place))
    }

    static func delete(_ g: Pen, _ t: CGFloat) {
        g.sheet(g.polygon([(6.5, 8.5), (17.5, 8.5), (16.5, 20.5), (7.5, 20.5)]))
        var slats = g.segment(10, 11.5, 10, 17.5)
        slats.addPath(g.segment(14, 11.5, 14, 17.5))
        g.ink(slats)
        var lid = g.segment(4, 6.5, 20, 6.5)
        lid.addPath(g.lines([(9.5, 6.5), (9.5, 4), (14.5, 4), (14.5, 6.5)]))
        g.ink(lid.applying(rotation(-14 * t, around: g.p(4, 6.5))))
    }

    static func typography(_ g: Pen, _ t: CGFloat) {
        let large = 1 - 0.1 * t
        let small = 1 + 0.15 * t
        g.ink(letterT(g, left: 3, right: 14, top: 5, bottom: 19.5).applying(scaling(large, large, around: g.p(8.5, 19.5))))
        g.ink(letterT(g, left: 14.5, right: 21, top: 11, bottom: 19.5).applying(scaling(small, small, around: g.p(17.75, 19.5))))
    }

    private static func letterT(_ g: Pen, left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
        let mid = (left + right) / 2
        let serif = (right - left) * 0.14
        var path = g.lines([(left, top + serif), (left, top), (right, top), (right, top + serif)])
        path.addPath(g.segment(mid, top, mid, bottom))
        path.addPath(g.segment(mid - serif * 1.4, bottom, mid + serif * 1.4, bottom))
        return path
    }

    static func sliders(_ g: Pen, _ t: CGFloat) {
        let rows: [(y: CGFloat, rest: CGFloat, active: CGFloat)] = [(5.5, 8, 14.5), (12, 15.5, 9.5), (18.5, 10.5, 16)]
        var tabs = Path()
        var tracks = Path()
        for (i, row) in rows.enumerated() {
            let x = mix(row.rest, row.active, stage(t, CGFloat(i) * 0.15, CGFloat(i) * 0.15 + 0.7))
            tabs.addPath(Path(roundedRect: g.rect(x - 1.75, row.y - 2.25, 3.5, 4.5), cornerRadius: g.u))
            tracks.addPath(g.segment(3.5, row.y, 20.5, row.y))
        }
        g.outside(tabs).ink(tracks)
        g.sheet(tabs)
    }

    static func brightness(_ g: Pen, _ t: CGFloat) {
        g.sheet(g.circle(12, 12, 4.5))
        var half = Path()
        half.addRelativeArc(center: g.p(12, 12), radius: 4.5 * g.u, startAngle: .degrees(90), delta: .degrees(180))
        half.closeSubpath()
        g.solid(half)
        g.ink(rays(g, count: 8, turn: 0, from: 7, to: { _ in 7 + mix(0.25, 2.5, t) }))
    }

    static func sun(_ g: Pen, _ t: CGFloat) {
        g.sheet(g.circle(12, 12, mix(4, 4.5, t)))
        g.ink(rays(g, count: 8, turn: 45 * t, from: 6.75, to: { $0 % 2 == 0 ? 9.5 : 8.25 }))
    }

    private static func rays(_ g: Pen, count: Int, turn: CGFloat, from inner: CGFloat, to outer: (Int) -> CGFloat) -> Path {
        var path = Path()
        for i in 0..<count {
            let a = (CGFloat(i) * 360 / CGFloat(count) + turn) * .pi / 180
            let r = outer(i)
            path.addPath(g.segment(12 + inner * cos(a), 12 + inner * sin(a), 12 + r * cos(a), 12 + r * sin(a)))
        }
        return path
    }

    static func moon(_ g: Pen, _ t: CGFloat) {
        let body = g.circle(11, 13, 8)
        let bite = g.circle(15.75, 8.75, 6.5).applying(rotation(-20 * t, around: g.p(11, 13)))
        g.outside(bite).sheet(body)
        g.inside(body).ink(bite)
        g.solid(sparkle(g, 17.75, 7.25, 2.25 * (1 + 0.3 * bump(t))))
        let late = stage(t, 0.35, 1)
        if late > 0 {
            g.solid(sparkle(g, 13.75, 4, 1.4 * late))
        }
    }

    private static func sparkle(_ g: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        let k = r * 0.22
        var path = Path()
        path.move(to: g.p(x, y - r))
        path.addQuadCurve(to: g.p(x + r, y), control: g.p(x + k, y - k))
        path.addQuadCurve(to: g.p(x, y + r), control: g.p(x + k, y + k))
        path.addQuadCurve(to: g.p(x - r, y), control: g.p(x - k, y + k))
        path.addQuadCurve(to: g.p(x, y - r), control: g.p(x - k, y - k))
        path.closeSubpath()
        return path
    }

    static func theme(_ g: Pen, _ t: CGFloat) {
        let rivet = g.p(7, 17)
        let card = g.rect(4.25, 4.75, 5.5, 15)
        let swatch = IconKit.foldedCard(card, fold: 2 * g.u, unit: g.u)
        let edge = Path(card.insetBy(dx: -0.75 * g.u, dy: -0.75 * g.u))
        let middle = rotation(mix(30, 45, t), around: rivet)
        let last = rotation(mix(60, 90, t), around: rivet)
        // The fanned cards' bottom corners would poke out past the front card's left and bottom edges.
        let behind = g.inside(Path(g.rect(card.minX / g.u, 0, 24, card.maxY / g.u))).outside(edge)
        behind.outside(edge.applying(middle)).sheet(swatch.applying(last), tone: 0.55)
        behind.sheet(swatch.applying(middle), tone: 0.25)
        g.sheet(swatch)
        g.solid(g.circle(7, 17, 0.9))
    }

    static func image(_ g: Pen, _ t: CGFloat) {
        let frame = g.rect(3.5, 4.5, 17, 15)
        g.sheet(IconKit.foldedCard(frame, fold: 3.5 * g.u, unit: g.u))
        let inner = g.inside(Path(frame))
        inner.solid(g.circle(8.5, mix(10, 8.5, t), 1.75))
        let ridge: [(CGFloat, CGFloat)] = [(3.5, 17.5), (8.5, 12.5), (12, 16), (14.5, 13.5), (20.5, 19)]
        inner.solid(g.polygon(ridge + [(20.5, 19.5), (3.5, 19.5)]), opacity: 0.15)
        inner.ink(g.lines(ridge))
    }

    static func quote(_ g: Pen, _ t: CGFloat) {
        for (i, x) in [CGFloat(8), 15.5].enumerated() {
            let start = CGFloat(i) * 0.3
            let y = 14 - 2 * bump(stage(t, start, start + 0.7))
            g.solid(g.circle(x, y, 2.4))
            var tail = Path()
            tail.move(to: g.p(x - 2.25, y + 0.25))
            tail.addQuadCurve(to: g.p(x + 1.75, y - 6), control: g.p(x - 2.75, y - 4.25))
            g.ink(tail)
        }
    }

    static func eye(_ g: Pen, _ t: CGFloat) {
        let lids = almond(g, open: 1 - 0.85 * bump(t))
        g.sheet(lids)
        let iris = g.inside(lids)
        iris.sheet(g.circle(12, 12, 3.5))
        iris.solid(g.circle(12, 12, mix(1.4, 1.8, t)))
    }

    static func eyeOff(_ g: Pen, _ t: CGFloat) {
        let from = g.p(4.5, 4), to = g.p(19.5, 20)
        let length = hypot(to.x - from.x, to.y - from.y)
        let dx = (to.x - from.x) / length * 1.75 * g.u, dy = (to.y - from.y) / length * 1.75 * g.u
        var gap = Path()
        gap.addLines([CGPoint(x: from.x - dx - dy, y: from.y - dy + dx), CGPoint(x: to.x + dx - dy, y: to.y + dy + dx),
                      CGPoint(x: to.x + dx + dy, y: to.y + dy - dx), CGPoint(x: from.x - dx + dy, y: from.y - dy - dx)])
        gap.closeSubpath()
        let eye = g.outside(gap)
        let lids = almond(g, open: mix(1, 0.55, t))
        eye.sheet(lids)
        let iris = eye.inside(lids)
        iris.sheet(g.circle(12, 12, 3.5))
        iris.solid(g.circle(12, 12, 1.4))
        var slash = Path()
        slash.addLines([from, to])
        g.ink(slash)
    }

    private static func almond(_ g: Pen, open: CGFloat) -> Path {
        var path = Path()
        path.move(to: g.p(2.5, 12))
        path.addQuadCurve(to: g.p(21.5, 12), control: g.p(12, 12 - 9.5 * open))
        path.addQuadCurve(to: g.p(2.5, 12), control: g.p(12, 12 + 9.5 * open))
        path.closeSubpath()
        return path
    }

    static func play(_ g: Pen, _ t: CGFloat) {
        let push = bump(t)
        let triangle = g.polygon([(8.5, 5), (19.5, 12), (8.5, 19)])
        g.sheet(triangle.applying(scaling(1 + 0.08 * push, 1, around: g.p(8.5, 12))).applying(shift(push, 0, g)))
    }

    static func pause(_ g: Pen, _ t: CGFloat) {
        for (i, x) in [CGFloat(6.5), 13.5].enumerated() {
            let start = CGFloat(i) * 0.2
            let squash = 1 - 0.22 * bump(stage(t, start, start + 0.8))
            let bar = Path(roundedRect: g.rect(x, 5, 4, 14), cornerRadius: 1.25 * g.u)
            g.sheet(bar.applying(scaling(1, squash, around: g.p(x + 2, 19))))
        }
    }

    static func skip(_ g: Pen, _ t: CGFloat, forward: Bool) {
        let kick = bump(t)
        let mirror = forward ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 24 * g.u, ty: 0) : .identity
        let triangle = g.polygon([(18, 6), (8.5, 12), (18, 18)])
        g.sheet(triangle.applying(shift(-kick, 0, g)).applying(mirror))
        g.ink(g.segment(6, 6, 6, 18).applying(shift(-0.5 * kick, 0, g)).applying(mirror))
    }

    static func headphones(_ g: Pen, _ t: CGFloat) {
        let k = bump(t)
        let lift = -1.25 * k, squeeze = 0.6 * k
        var cups = Path(roundedRect: g.rect(3 + squeeze, 11.5 + lift, 4, 7.5), cornerRadius: 1.5 * g.u)
        cups.addPath(Path(roundedRect: g.rect(17 - squeeze, 11.5 + lift, 4, 7.5), cornerRadius: 1.5 * g.u))
        var band = Path()
        band.addRelativeArc(center: g.p(12, 12.5 + lift), radius: 7.5 * g.u, startAngle: .degrees(180), delta: .degrees(180))
        g.outside(cups).ink(band)
        g.sheet(cups)
    }

    static func speed(_ g: Pen, _ t: CGFloat) {
        var dial = Path()
        dial.addRelativeArc(center: g.p(12, 14), radius: 8.5 * g.u, startAngle: .degrees(150), delta: .degrees(240))
        g.sheet(dial)
        let a = mix(220, 320, t) * .pi / 180
        g.ink(g.segment(12, 14, 12 + 6 * cos(a), 14 + 6 * sin(a)))
        g.solid(g.circle(12, 14, 1.6))
    }

    static func timer(_ g: Pen, _ t: CGFloat) {
        let press = 0.75 * bump(t)
        g.sheet(g.circle(12, 13.5, 7.5))
        var crown = g.segment(12, 6, 12, 3.5 + press)
        crown.addPath(g.segment(10, 3.5 + press, 14, 3.5 + press))
        crown.addPath(g.segment(17.85, 7.65, 18.75, 6.75))
        g.ink(crown)
        let a = mix(-90, 0, t) * .pi / 180
        g.ink(g.segment(12, 13.5, 12 + 5 * cos(a), 13.5 + 5 * sin(a)))
        g.solid(g.circle(12, 13.5, 1.1))
    }

    static func voice(_ g: Pen, _ t: CGFloat) {
        g.sheet(bubble(g))
        let rest: [CGFloat] = [2.5, 6, 4, 1.5]
        let active: [CGFloat] = [5, 3, 7, 3.5]
        var wave = Path()
        for i in 0..<4 {
            let start = CGFloat(i) * 0.12
            let h = mix(rest[i], active[i], stage(t, start, start + 0.64))
            let x = 7.5 + CGFloat(i) * 3
            wave.addPath(g.segment(x, 10.25 - h / 2, x, 10.25 + h / 2))
        }
        g.ink(wave)
    }

    private static func bubble(_ g: Pen) -> Path {
        let left: CGFloat = 3, right: CGFloat = 21, top: CGFloat = 3.5, bottom: CGFloat = 17, r: CGFloat = 3.5
        var path = Path()
        path.move(to: g.p(left + r, top))
        path.addLine(to: g.p(right - r, top))
        path.addQuadCurve(to: g.p(right, top + r), control: g.p(right, top))
        path.addLine(to: g.p(right, bottom - r))
        path.addQuadCurve(to: g.p(right - r, bottom), control: g.p(right, bottom))
        path.addLine(to: g.p(11.5, bottom))
        path.addLine(to: g.p(6.5, 21))
        path.addLine(to: g.p(7.5, bottom))
        path.addLine(to: g.p(left + r, bottom))
        path.addQuadCurve(to: g.p(left, bottom - r), control: g.p(left, bottom))
        path.addLine(to: g.p(left, top + r))
        path.addQuadCurve(to: g.p(left + r, top), control: g.p(left, top))
        path.closeSubpath()
        return path
    }

    static func stats(_ g: Pen, _ t: CGFloat) {
        let bars: [(x: CGFloat, rest: CGFloat, active: CGFloat)] = [(5, 6, 9), (10.25, 9.5, 13), (15.5, 13, 15.5)]
        for (i, bar) in bars.enumerated() {
            let start = CGFloat(i) * 0.15
            let h = mix(bar.rest, bar.active, stage(t, start, start + 0.7))
            g.sheet(Path(roundedRect: g.rect(bar.x, 19.5 - h, 3.5, h), cornerRadius: 0.75 * g.u))
        }
        g.ink(g.segment(3, 19.5, 21, 19.5))
    }

    static func flame(_ g: Pen, _ t: CGFloat) {
        let sway = 1.4 * sin(3 * .pi * min(max(t, 0), 1))
        var outer = Path()
        outer.move(to: g.p(12, 21))
        outer.addCurve(to: g.p(5.5, 14.5), control1: g.p(8, 21), control2: g.p(5.5, 18.25))
        outer.addCurve(to: g.p(7.75 - 0.4 * sway, 8), control1: g.p(5.5, 11.75), control2: g.p(6.5, 9.5))
        outer.addCurve(to: g.p(10, 11), control1: g.p(8.5, 9.25), control2: g.p(9.25, 10.5))
        outer.addCurve(to: g.p(12.75 + sway, 2.75), control1: g.p(9.5, 7.5), control2: g.p(11, 5))
        outer.addCurve(to: g.p(18.5, 14.5), control1: g.p(16.5 + 0.5 * sway, 6.5), control2: g.p(18.5, 10.5))
        outer.addCurve(to: g.p(12, 21), control1: g.p(18.5, 18.25), control2: g.p(16, 21))
        outer.closeSubpath()
        g.sheet(outer)
        let inner = teardrop(g, base: (12, 19.75), width: 3, tip: (12.5 + 0.6 * sway, mix(13.5, 11, t)))
        g.solid(inner, opacity: Double(mix(0.3, 1, min(max(t, 0), 1))))
    }

    private static func teardrop(_ g: Pen, base: (x: CGFloat, y: CGFloat), width w: CGFloat, tip: (x: CGFloat, y: CGFloat)) -> Path {
        let waist = base.y - w
        let rise = waist - tip.y
        var path = Path()
        path.move(to: g.p(base.x, base.y))
        path.addCurve(to: g.p(base.x - w, waist), control1: g.p(base.x - 0.55 * w, base.y), control2: g.p(base.x - w, base.y - 0.45 * w))
        path.addCurve(to: g.p(tip.x, tip.y), control1: g.p(base.x - w, waist - 0.45 * rise), control2: g.p(tip.x - 0.25 * w, tip.y + 0.35 * rise))
        path.addCurve(to: g.p(base.x + w, waist), control1: g.p(tip.x + 0.25 * w, tip.y + 0.35 * rise), control2: g.p(base.x + w, waist - 0.45 * rise))
        path.addCurve(to: g.p(base.x, base.y), control1: g.p(base.x + w, base.y - 0.45 * w), control2: g.p(base.x + 0.55 * w, base.y))
        path.closeSubpath()
        return path
    }
}
