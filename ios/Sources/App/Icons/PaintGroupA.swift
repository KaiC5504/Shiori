import SwiftUI

extension IconPainter {
    static func paintGroupA(_ icon: ShioriIcon, in context: inout GraphicsContext, activity: CGFloat, style: IconStyle) {
        // Sheets erase what they cover, so each icon draws in a layer of its own.
        context.drawLayer { layer in
            let pen = Pen(context: layer, style: style)
            let a = activity
            switch icon {
            case .shelf: GroupA.shelf(pen, a)
            case .import: GroupA.importTray(pen, a)
            case .settings: GroupA.settings(pen, a)
            case .book: GroupA.book(pen, a)
            case .search: GroupA.search(pen, a)
            case .history: GroupA.history(pen, a)
            case .filter: GroupA.filter(pen, a)
            case .sort: GroupA.sort(pen, a)
            case .layoutList: GroupA.layoutList(pen, a)
            case .layoutGrid: GroupA.layoutGrid(pen, a)
            case .add: GroupA.add(pen, a)
            case .more: GroupA.more(pen, a)
            case .close: GroupA.close(pen, a)
            case .back: GroupA.chevron(pen, a, facing: -1)
            case .forward: GroupA.chevron(pen, a, facing: 1)
            case .folder: GroupA.folder(pen, a)
            case .folderAdd: GroupA.folderAdd(pen, a)
            case .document: GroupA.document(pen, a)
            case .refresh: GroupA.refresh(pen, a)
            case .link: GroupA.link(pen, a)
            case .check: GroupA.check(pen, a)
            case .warning: GroupA.warning(pen, a)
            case .info: GroupA.info(pen, a)
            case .language: GroupA.language(pen, a)
            case .lock: GroupA.lock(pen, a)
            case .tag: GroupA.tag(pen, a)
            case .person: GroupA.person(pen, a)
            case .category: GroupA.category(pen, a)
            case .calendar: GroupA.calendar(pen, a)
            default: placeholder(in: &layer, activity: activity, style: style)
            }
        }
    }
}

private enum GroupA {
    static func shelf(_ pen: Pen, _ a: CGFloat) {
        let u = pen.u
        func hop(_ index: CGFloat) -> CGFloat { -2.5 * wave(a, start: index * 0.2, span: 0.6) * u }
        pen.line(pen.poly([(2.5, 21), (21.5, 21)]))
        pen.sheet(IconKit.spine(pen.box(3, 7, 4.5, 12.5), unit: u).offsetBy(dx: 0, dy: hop(0)))
        pen.sheet(IconKit.spine(pen.box(10, 4, 4.5, 15.5), unit: u).offsetBy(dx: 0, dy: hop(1)))
        let leaning = IconKit.spine(pen.box(17, 8.5, 3.5, 11), unit: u).applying(pen.turn(-12, around: 17, 19.5))
        pen.sheet(leaning.offsetBy(dx: 0, dy: hop(2)))
    }

    static func importTray(_ pen: Pen, _ a: CGFloat) {
        let drop = 3 * a
        pen.card(6.5, 2 + drop, 11, 14.5, fold: 3.5)
        pen.arrow(from: (12, 5.5 + drop), to: (12, 10 + drop), head: 2.5)
        var tray = IconKit.tray(pen.box(3, 15, 18, 6), unit: pen.u)
        tray.closeSubpath()
        pen.sheet(tray)
    }

    static func settings(_ pen: Pen, _ a: CGFloat) {
        pen.card(4, 2.5, 16, 19, fold: 3.5)
        let knobs: [(y: CGFloat, from: CGFloat, to: CGFloat)] = [(8.5, 9.5, 14), (12.75, 14.5, 10), (17, 11, 13.5)]
        for (index, knob) in knobs.enumerated() {
            pen.line(pen.poly([(7.5, knob.y), (16.5, knob.y)]))
            let x = lerp(knob.from, knob.to, phase(a, start: CGFloat(index) * 0.15, span: 0.7))
            pen.sheet(pen.circle(x, knob.y, 1.6))
        }
    }

    /// The cover swings open towards the viewer, so its free edge narrows and grows taller.
    static func book(_ pen: Pen, _ a: CGFloat) {
        pen.sheet(pen.rounded(6.5, 3, 10.5, 18, 1))
        for y: CGFloat in [7, 10.5, 14] {
            pen.line(pen.poly([(12.5, y), (15.25, y)]))
        }
        let edge = 18 - 7.5 * a, flare = 1.25 * a
        func onCover(_ across: CGFloat, _ down: CGFloat) -> (CGFloat, CGFloat) {
            let top = 2.5 - flare * across, bottom = 19 + flare * across
            return (5 + across * (edge - 5), top + down * (bottom - top))
        }
        pen.sheet(pen.poly([onCover(0, 0), onCover(1, 0), onCover(1, 1), onCover(0, 1)], closed: true))
        pen.line(pen.poly([onCover(0.16, 0), onCover(0.16, 1)]))
        pen.line(pen.poly([onCover(0.4, 0.27), onCover(0.8, 0.27)]))
    }

    static func search(_ pen: Pen, _ a: CGFloat) {
        let tilt = pen.turn(-15 * a, around: 10.5, 10.5)
        pen.line(pen.poly([(15, 15), (19.5, 19.5)]).applying(tilt))
        pen.sheet(pen.circle(10.5, 10.5, 6.5))
        pen.line(pen.poly(arcPoints(10.5, 10.5, 4, from: 200, to: 250)).applying(tilt))
    }

    /// The hands wind backwards.
    static func history(_ pen: Pen, _ a: CGFloat) {
        pen.tint(pen.circle(13, 12, 7.5))
        pen.line(pen.poly(arcPoints(13, 12, 7.5, from: 205, to: 505)))
        pen.line(pen.chevron(tip: onCircle(13, 12, 7.5, 205), pointing: 115, size: 2.5))
        let hour = onCircle(13, 12, 3.5, -90 - 25 * a)
        let minute = onCircle(13, 12, 5, -180 * a)
        pen.line(pen.poly([hour, (13, 12), minute]))
    }

    /// A drop falls through the funnel and out of its stem.
    static func filter(_ pen: Pen, _ a: CGFloat) {
        let funnel: [(CGFloat, CGFloat)] = [(10, 17.5), (10, 11), (3.5, 4), (20.5, 4), (14, 11), (14, 17.5)]
        let body = pen.poly(funnel, closed: true)
        pen.cover(body)
        pen.tint(body)
        pen.line(pen.poly(funnel))
        pen.solid(pen.circle(12, lerp(8, 21, a), 1.1), opacity: clamp01(a * 3))
    }

    /// The rows trade lengths and the arrow flips over.
    static func sort(_ pen: Pen, _ a: CGFloat) {
        let t = clamp01(a)
        let lengths: [(CGFloat, CGFloat)] = [(10.5, 3.5), (7, 7), (3.5, 10.5)]
        for (index, length) in lengths.enumerated() {
            let y = 6.5 + CGFloat(index) * 5.5
            pen.line(pen.poly([(4, y), (4 + lerp(length.0, length.1, t), y)]))
        }
        let flip = cos(.pi * t)
        let tip = 12 + 7 * flip
        pen.line(pen.poly([(19, 5), (19, 19)]))
        pen.line(pen.poly([(16.75, tip - 2.25 * flip), (19, tip), (21.25, tip - 2.25 * flip)]))
    }

    static func layoutList(_ pen: Pen, _ a: CGFloat) {
        for index in 0..<3 {
            let y = 6 + CGFloat(index) * 6
            let nudge = 1.5 * wave(a, start: CGFloat(index) * 0.15, span: 0.7)
            pen.sheet(pen.rounded(3 + nudge, y - 2, 4, 4, 0.75))
            pen.line(pen.poly([(10.5 + nudge, y), (20.5 + nudge, y)]))
        }
    }

    static func layoutGrid(_ pen: Pen, _ a: CGFloat) {
        let origins: [(CGFloat, CGFloat)] = [(3.5, 3.5), (13.5, 3.5), (3.5, 13.5), (13.5, 13.5)]
        for (index, origin) in origins.enumerated() {
            let grow = 0.9 * wave(a, start: CGFloat(index) * 0.12, span: 0.64)
            pen.card(origin.0 - grow, origin.1 - grow, 7 + 2 * grow, 7 + 2 * grow, fold: 2.25)
        }
    }

    /// The card lifts off its shadow.
    static func add(_ pen: Pen, _ a: CGFloat) {
        let lift = 2 * a
        pen.line(pen.poly([(8.5, 21.5), (15.5, 21.5)]), opacity: 0.35 * clamp01(a))
        pen.card(5.5, 4 - lift, 13, 16, fold: 3.5)
        pen.plus(at: (12, 12.5 - lift), arm: 3.25)
    }

    static func more(_ pen: Pen, _ a: CGFloat) {
        for index in 0..<3 {
            let hop = 2.5 * wave(a, start: CGFloat(index) * 0.18, span: 0.64)
            pen.solid(pen.circle(5.5 + CGFloat(index) * 6.5, 12 - hop, 1.75))
        }
    }

    static func close(_ pen: Pen, _ a: CGFloat) {
        let spin = pen.turn(90 * a, around: 12, 12)
        pen.line(pen.poly([(6.5, 6.5), (17.5, 17.5)]).applying(spin))
        pen.line(pen.poly([(17.5, 6.5), (6.5, 17.5)]).applying(spin))
    }

    /// `facing` is -1 for back and 1 for forward.
    static func chevron(_ pen: Pen, _ a: CGFloat, facing: CGFloat) {
        let nudge = 2.5 * facing * wave(a)
        pen.line(pen.poly([(12 - 3.5 * facing + nudge, 4.5), (12 + 4 * facing + nudge, 12), (12 - 3.5 * facing + nudge, 19.5)]))
    }

    /// The front flap tips forward and a card rises out of the folder.
    static func folder(_ pen: Pen, _ a: CGFloat) {
        folderBack(pen)
        pen.card(5.5, 11 - 4.5 * a, 13, 8, fold: 2.5)
        folderFront(pen, open: a)
    }

    static func folderAdd(_ pen: Pen, _ a: CGFloat) {
        folderBack(pen)
        folderFront(pen, open: 0)
        let spin = pen.turn(90 * a, around: 12, 15)
        let arm = 2.5 * (1 + 0.25 * wave(a))
        pen.line(pen.poly([(12 - arm, 15), (12 + arm, 15)]).applying(spin))
        pen.line(pen.poly([(12, 15 - arm), (12, 15 + arm)]).applying(spin))
    }

    private static func folderBack(_ pen: Pen) {
        pen.sheet(pen.poly([(2.5, 19.5), (2.5, 5), (8.5, 5), (10.5, 7.5), (21.5, 7.5), (21.5, 19.5)], closed: true))
    }

    private static func folderFront(_ pen: Pen, open: CGFloat) {
        let top = 10.5 + 1.5 * open
        pen.sheet(pen.poly([(2.5 - open, top), (21.5 + open, top), (21.5, 19.5), (2.5, 19.5)], closed: true))
    }

    /// The corner dog-ears further.
    static func document(_ pen: Pen, _ a: CGFloat) {
        pen.card(5, 2.5, 14, 19, fold: 4 + 1.5 * a)
        pen.line(pen.poly([(8.5, 7), (12, 7)]))
        for (y, end) in [(10.5, 15.5), (14, 15.5), (17.5, 12.5)] as [(CGFloat, CGFloat)] {
            pen.line(pen.poly([(8.5, y), (end, y)]))
        }
    }

    static func refresh(_ pen: Pen, _ a: CGFloat) {
        let spin = pen.turn(180 * a, around: 12, 12)
        for start: CGFloat in [200, 20] {
            let end = start + 135
            pen.line(pen.poly(arcPoints(12, 12, 7, from: start, to: end)).applying(spin))
            pen.line(pen.chevron(tip: onCircle(12, 12, 7, end), pointing: end + 90, size: 2.75).applying(spin))
        }
    }

    /// Two open links joined by a bar, drawn level and then turned to the diagonal. They tug
    /// apart and snap back.
    static func link(_ pen: Pen, _ a: CGFloat) {
        let apart = 1.5 * wave(a)
        let place = pen.turn(-45, around: 0, 0).concatenating(CGAffineTransform(translationX: 12 * pen.u, y: 12 * pen.u))
        let left = [(-1.5 - apart, -3.5)] + arcPoints(-5.5 - apart, 0, 3.5, from: 270, to: 90) + [(-1.5 - apart, 3.5)]
        let right = [(1.5 + apart, -3.5)] + arcPoints(5.5 + apart, 0, 3.5, from: -90, to: 90) + [(1.5 + apart, 3.5)]
        pen.line(pen.poly(left).applying(place))
        pen.line(pen.poly(right).applying(place))
        pen.line(pen.poly([(-3, 0), (3, 0)]).applying(place))
    }

    /// The tick pulls back and draws itself again.
    static func check(_ pen: Pen, _ a: CGFloat) {
        let mark = pen.poly([(5, 12.5), (10, 17.5), (19.5, 7)])
        pen.line(mark.trimmedPath(from: 0, to: 1 - 0.5 * wave(a)))
    }

    /// The sign rocks on its base and settles.
    static func warning(_ pen: Pen, _ a: CGFloat) {
        let t = clamp01(a)
        let rock = pen.turn(12 * sin(2 * .pi * t) * (1 - t), around: 12, 20.5)
        pen.sheet(pen.poly([(12, 3.5), (21.5, 20), (2.5, 20)], closed: true).applying(rock))
        pen.line(pen.poly([(12, 9.5), (12, 13.5)]).applying(rock))
        pen.solid(pen.circle(12, 16.5, 1).applying(rock))
    }

    static func info(_ pen: Pen, _ a: CGFloat) {
        pen.sheet(pen.circle(12, 12, 8.5))
        pen.line(pen.poly([(12, 11), (12, 16.5)]))
        pen.solid(pen.circle(12, 7.75 - 2 * wave(a), 1.1))
    }

    /// The 文 card and the A card swap places, passing each other on a curve.
    static func language(_ pen: Pen, _ a: CGFloat) {
        let t = phase(a)
        let swing = 1.75 * sin(.pi * t)
        let han = (x: lerp(2, 10, t) + swing, y: lerp(2, 10, t) - swing)
        let latin = (x: lerp(10, 2, t) - swing, y: lerp(10, 2, t) + swing)
        let hanGlyph = lerp(-1.5, 0.5, t), latinGlyph = lerp(0.5, -1.5, t)
        let drawHan = {
            pen.card(han.x, han.y, 12, 12, fold: 2.5)
            let cx = han.x + 6 + hanGlyph, cy = han.y + 6 + hanGlyph
            pen.line(pen.poly([(cx, cy - 3), (cx, cy - 2.1)]), width: 0.85)
            pen.line(pen.poly([(cx - 2.6, cy - 1.4), (cx + 2.6, cy - 1.4)]), width: 0.85)
            pen.line(pen.poly([(cx - 1.6, cy + 0.1), (cx + 2.4, cy + 2.75)]), width: 0.85)
            pen.line(pen.poly([(cx + 1.6, cy + 0.1), (cx - 2.4, cy + 2.75)]), width: 0.85)
        }
        let drawLatin = {
            pen.card(latin.x, latin.y, 12, 12, fold: 2.5)
            let cx = latin.x + 6 + latinGlyph, cy = latin.y + 6 + latinGlyph
            pen.line(pen.poly([(cx - 2.5, cy + 2.5), (cx, cy - 2.75), (cx + 2.5, cy + 2.5)]), width: 0.85)
            pen.line(pen.poly([(cx - 1.4, cy + 0.6), (cx + 1.4, cy + 0.6)]), width: 0.85)
        }
        if t < 0.5 {
            drawHan()
            drawLatin()
        } else {
            drawLatin()
            drawHan()
        }
    }

    /// Open at rest, and the shackle drops shut when active: it stands for the rotation lock.
    static func lock(_ pen: Pen, _ a: CGFloat) {
        let rise = 2.5 * (1 - a)
        let shackle = [(8.5, 15)] + arcPoints(12, 8, 3.5, from: 180, to: 360) + [(15.5, 11)]
        pen.line(pen.poly(shackle).offsetBy(dx: 0, dy: -rise * pen.u))
        pen.sheet(pen.rounded(5, 11, 14, 10, 2))
        pen.solid(pen.circle(12, 15.25, 1.25))
        pen.line(pen.poly([(12, 15.5), (12, 17.75)]))
    }

    /// Drawn pointing left, then turned so the point faces up-left. The far end is rounded so
    /// it can't be read as a second point. It swings from its hole.
    static func tag(_ pen: Pen, _ a: CGFloat) {
        let t = clamp01(a)
        let tip: CGFloat = 5.3
        let place = pen.turn(45, around: 0, 0).concatenating(CGAffineTransform(translationX: tip * pen.u, y: tip * pen.u))
        let hole = tip + 5.5 * 0.7071
        let swing = pen.turn(16 * sin(2 * .pi * t) * (1 - t), around: hole, hole)
        let outline = [(0, 0), (5.5, -4)] + arcPoints(13, -2, 2, from: -90, to: 0)
            + arcPoints(13, 2, 2, from: 0, to: 90) + [(5.5, 4)]
        pen.sheet(pen.poly(outline, closed: true).applying(place).applying(swing))
        pen.line(pen.circle(5.5, 0, 1.1).applying(place).applying(swing))
    }

    static func person(_ pen: Pen, _ a: CGFloat) {
        var shoulders = Path()
        shoulders.move(to: pen.pt(4.5, 20.5))
        shoulders.addCurve(to: pen.pt(12, 13.5), control1: pen.pt(4.5, 16), control2: pen.pt(7.5, 13.5))
        shoulders.addCurve(to: pen.pt(19.5, 20.5), control1: pen.pt(16.5, 13.5), control2: pen.pt(19.5, 16))
        shoulders.closeSubpath()
        pen.sheet(shoulders)
        pen.sheet(pen.circle(12, 7.5 - 1.75 * wave(a), 3.5))
    }

    /// A triangle, a circle and a square that trade places round a circle, staying upright.
    static func category(_ pen: Pen, _ a: CGFloat) {
        let turn = 120 * phase(a)
        let triangle = onCircle(12, 13.5, 5.75, -90 + turn)
        let round = onCircle(12, 13.5, 5.75, 150 + turn)
        let square = onCircle(12, 13.5, 5.75, 30 + turn)
        pen.sheet(pen.poly([(triangle.0, triangle.1 - 3.75), (triangle.0 + 3.9, triangle.1 + 3),
                            (triangle.0 - 3.9, triangle.1 + 3)], closed: true))
        pen.sheet(pen.circle(round.0, round.1, 3.5))
        pen.sheet(pen.rounded(square.0 - 3.25, square.1 - 3.25, 6.5, 6.5, 1))
    }

    /// The marked day moves on to the next.
    static func calendar(_ pen: Pen, _ a: CGFloat) {
        pen.sheet(pen.rounded(3.5, 5, 17, 15.5, 2))
        pen.line(pen.poly([(3.5, 9.5), (20.5, 9.5)]))
        pen.line(pen.poly([(8, 3), (8, 7)]))
        pen.line(pen.poly([(16, 3), (16, 7)]))
        for y: CGFloat in [13.25, 17] {
            for x: CGFloat in [8, 12, 16] {
                pen.solid(pen.circle(x, y, 0.9))
            }
        }
        let x = lerp(8, 12, a), half = 1.75 * (1 + 0.2 * wave(a))
        pen.solid(pen.rounded(x - half, 13.25 - half, 2 * half, 2 * half, 0.75))
    }
}

/// Draws in 24-unit grid coordinates. A sheet hides whatever it is laid over, like paper.
private struct Pen {
    let context: GraphicsContext
    let style: IconStyle

    var u: CGFloat { style.unit }

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * u, y: y * u)
    }

    func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x * u, y: y * u, width: width * u, height: height * u)
    }

    func poly(_ points: [(CGFloat, CGFloat)], closed: Bool = false) -> Path {
        var path = Path()
        path.addLines(points.map { pt($0.0, $0.1) })
        if closed { path.closeSubpath() }
        return path
    }

    func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: box(x - radius, y - radius, 2 * radius, 2 * radius))
    }

    func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> Path {
        Path(roundedRect: box(x, y, width, height), cornerRadius: radius * u)
    }

    /// Two strokes meeting at `tip`, opening away from the direction it points in.
    func chevron(tip: (CGFloat, CGFloat), pointing degrees: CGFloat, size: CGFloat) -> Path {
        let back = (degrees + 180) * .pi / 180, spread: CGFloat = 0.75
        return poly([(tip.0 + size * cos(back - spread), tip.1 + size * sin(back - spread)),
                     tip,
                     (tip.0 + size * cos(back + spread), tip.1 + size * sin(back + spread))])
    }

    func arrow(from start: (CGFloat, CGFloat), to end: (CGFloat, CGFloat), head: CGFloat) {
        line(poly([start, end]))
        let degrees = atan2(end.1 - start.1, end.0 - start.0) * 180 / .pi
        line(chevron(tip: end, pointing: degrees, size: head))
    }

    func plus(at center: (CGFloat, CGFloat), arm: CGFloat) {
        line(poly([(center.0 - arm, center.1), (center.0 + arm, center.1)]))
        line(poly([(center.0, center.1 - arm), (center.0, center.1 + arm)]))
    }

    /// A rotation about a grid point; positive turns clockwise on screen.
    func turn(_ degrees: CGFloat, around x: CGFloat, _ y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x * u, y: y * u)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -x * u, y: -y * u)
    }

    func line(_ path: Path, width: CGFloat = 1, opacity: Double = 1) {
        context.stroke(path, with: .color(style.ink.opacity(opacity)),
                       style: StrokeStyle(lineWidth: style.stroke * width, lineCap: .round, lineJoin: .round))
    }

    func solid(_ path: Path, opacity: Double = 1) {
        context.fill(path, with: .color(style.ink.opacity(opacity)))
    }

    func tint(_ path: Path, depth: Double = 1) {
        context.fill(path, with: .color(style.ink.opacity(style.fill * depth)))
    }

    func cover(_ path: Path) {
        var eraser = context
        eraser.blendMode = .destinationOut
        eraser.fill(path, with: .color(style.ink))
    }

    func sheet(_ path: Path) {
        cover(path)
        tint(path)
        line(path)
    }

    /// `IconKit.foldedCard` with its flap shaded a little deeper than the face.
    func card(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, fold: CGFloat) {
        let right = x + width, bottom = y + height
        let outline = poly([(x, y), (right - fold, y), (right, y + fold), (right, bottom), (x, bottom)], closed: true)
        let flap = poly([(right - fold, y), (right - fold, y + fold), (right, y + fold)], closed: true)
        cover(outline)
        tint(outline)
        tint(flap, depth: 1.5)
        line(IconKit.foldedCard(box(x, y, width, height), fold: fold * u, unit: u))
    }
}

private func clamp01(_ t: CGFloat) -> CGFloat {
    min(max(t, 0), 1)
}

private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
    from + (to - from) * t
}

/// Eased 0 to 1 across the slice of activity from `start` to `start + span`.
private func phase(_ a: CGFloat, start: CGFloat = 0, span: CGFloat = 1) -> CGFloat {
    let t = clamp01((a - start) / span)
    return t * t * (3 - 2 * t)
}

/// 0 to 1 and back to 0 across the slice, for motions that settle where they began.
private func wave(_ a: CGFloat, start: CGFloat = 0, span: CGFloat = 1) -> CGFloat {
    sin(.pi * clamp01((a - start) / span))
}

/// A point on a circle in grid units. 0° points right and angles grow clockwise on screen.
private func onCircle(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, _ degrees: CGFloat) -> (CGFloat, CGFloat) {
    let angle = degrees * .pi / 180
    return (cx + radius * cos(angle), cy + radius * sin(angle))
}

/// Points along an arc, which runs either way round depending on whether `to` is above `from`.
private func arcPoints(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, from: CGFloat, to: CGFloat) -> [(CGFloat, CGFloat)] {
    let steps = max(2, Int((abs(to - from) / 4).rounded(.up)))
    return (0...steps).map { step in
        onCircle(cx, cy, radius, from + (to - from) * CGFloat(step) / CGFloat(steps))
    }
}
