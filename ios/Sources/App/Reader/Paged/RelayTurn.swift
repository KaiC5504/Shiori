import ShioriLibrary
import SwiftUI
import UIKit

/// How a relay turn moves: paragraph relay at a speed, or Reduce Motion's crossfade.
enum RelayMotion: Equatable {
    case relay(TurnSpeed)
    case crossfade
}

extension TurnSpeed {
    /// Seconds each paragraph takes to move, and between one paragraph starting and the next.
    var relayTiming: (duration: Double, stagger: Double) {
        switch self {
        case .gentle: (0.30, 0.05)
        case .standard: (0.22, 0.035)
        case .brisk: (0.16, 0.025)
        }
    }
}

/// Where each paragraph of a relay turn is at a given time (spec §7.2, item 1), so a tap plays
/// it and a drag scrubs it the same way.
struct RelayTimeline {
    let duration: Double
    /// When the incoming page's first paragraph starts, once the outgoing first one has mostly gone.
    let handoff: Double
    let outgoingStagger: Double
    let incomingStagger: Double
    let travel: CGFloat
    let total: Double
    /// A crossfade runs straight; a relay leaves accelerating and arrives settling.
    let eases: Bool

    init(motion: RelayMotion, outgoing: Int, incoming: Int, travel: CGFloat) {
        switch motion {
        case .relay(let speed):
            let timing = speed.relayTiming
            duration = timing.duration
            handoff = timing.duration * 0.6
            outgoingStagger = Self.stagger(timing.stagger, count: outgoing)
            incomingStagger = Self.stagger(timing.stagger, count: incoming)
            self.travel = travel
            eases = true
        case .crossfade:
            duration = 0.15
            handoff = 0
            outgoingStagger = 0
            incomingStagger = 0
            self.travel = 0
            eases = false
        }
        total = max(outgoingStagger * Double(max(outgoing - 1, 0)) + duration,
                    handoff + incomingStagger * Double(max(incoming - 1, 0)) + duration)
    }

    /// 0 at rest, 1 gone.
    func outgoing(_ index: Int, at time: Double) -> Double {
        let u = local(time - outgoingStagger * Double(index))
        return eases ? u * u * u : u
    }

    /// 0 not yet in, 1 in place.
    func incoming(_ index: Int, at time: Double) -> Double {
        let u = local(time - handoff - incomingStagger * Double(index))
        return eases ? 1 - (1 - u) * (1 - u) * (1 - u) : u
    }

    /// A leaving paragraph fades ahead of its slide, so it's faint by the time the arriving one
    /// crosses it.
    func outgoingOpacity(_ gone: Double) -> Double {
        eases ? 1 - min(gone * 1.6, 1) : 1 - gone
    }

    private func local(_ elapsed: Double) -> Double {
        min(max(elapsed / duration, 0), 1)
    }

    /// A page of short dialogue lines can hold twenty paragraphs; past eleven the stagger
    /// shrinks so the whole turn never runs longer than ten steps of it.
    private static func stagger(_ step: Double, count: Int) -> Double {
        count > 11 ? step * 10 / Double(count - 1) : step
    }
}

/// Paragraph relay (spec §7.2, item 1), and under Reduce Motion the crossfade every effect
/// becomes. The paper stays still: the outgoing page's paragraphs slide out one after another
/// in the turn's direction, and the incoming page's slide in behind them.
struct RelayTurn: UIViewRepresentable {
    let page: PagedPage
    let style: PageStyle
    let pageFrame: CGRect
    let motion: RelayMotion
    let taps: PageTaps
    let chapters: PagedChapters
    let onTurn: (PagedPage) -> Void
    let onMenu: () -> Void

    func makeUIView(context: Context) -> RelayTurnView {
        RelayTurnView()
    }

    func updateUIView(_ view: RelayTurnView, context: Context) {
        view.motion = motion
        view.taps = taps
        view.chapters = chapters
        view.onTurn = onTurn
        view.onMenu = onMenu
        view.show(page, style: style, in: pageFrame)
    }
}

final class RelayTurnView: UIView, UIGestureRecognizerDelegate {
    var motion = RelayMotion.relay(.standard)
    var taps = PageTaps(layout: .standard, bothSidesForward: false)
    var chapters: PagedChapters?
    var onTurn: (PagedPage) -> Void = { _ in }
    var onMenu: () -> Void = {}

    /// The page turned to, from the moment the turn is certain, while its motion still plays.
    private(set) var current: PagedPage?
    private let canvas = PageCanvas()
    private var style: PageStyle?
    private var pageFrame: CGRect = .zero
    private var run: RelayRun?
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval?
    /// The next page, drawn ahead while the reader reads this one.
    private var prepared: (page: PagedPage, image: CGImage)?
    private var preparing: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(canvas)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        // The delegate and UIView both ask `gestureRecognizerShouldBegin`; this view answers both.
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finishRun() }
    }

    func show(_ page: PagedPage, style: PageStyle, in pageFrame: CGRect) {
        let restyled = style != self.style || pageFrame != self.pageFrame
        self.style = style
        self.pageFrame = pageFrame
        guard page != current || restyled else { return }
        // A jump or a new layout lands at once, over any turn still playing.
        stopRun()
        prepared = nil
        current = page
        canvas.show(page, style: style, in: pageFrame)
        prepareNext()
    }

    private func turn(forward: Bool, animated: Bool = true) {
        guard let current, let chapters else { return }
        finishRun()
        if let target = chapters.cachedNeighbour(of: current, forward: forward) {
            play(to: target, forward: forward, animated: animated)
            return
        }
        Task { [weak self] in
            guard let target = await chapters.neighbour(of: current, forward: forward),
                  let self, self.current == current, self.run == nil else { return }
            self.play(to: target, forward: forward, animated: animated)
        }
    }

    private func play(to target: PagedPage, forward: Bool, animated: Bool) {
        guard animated, let run = startRun(to: target, forward: forward) else {
            commit(target)
            if let style { canvas.show(target, style: style, in: pageFrame, prerendered: preparedImage(for: target)) }
            prepareNext()
            return
        }
        commit(target)
        run.isCommitted = true
        run.goal = .finish
        startLink()
    }

    /// The turn is certain: the reader's place moves now, while the motion finishes.
    private func commit(_ target: PagedPage) {
        current = target
        onTurn(target)
    }

    private func startRun(to target: PagedPage, forward: Bool) -> RelayRun? {
        guard let style, let outgoing = canvas.image, bounds.width > 0,
              let incoming = preparedImage(for: target)
                ?? PageRenderer.image(of: target, size: pageFrame.size, style: style),
              let page = canvas.page
        else { return nil }
        let outgoingLayers = slices(of: outgoing, page: page)
        let incomingLayers = slices(of: incoming, page: target)
        let timeline = RelayTimeline(motion: motion, outgoing: outgoingLayers.count, incoming: incomingLayers.count,
                                     travel: bounds.width * 0.35)
        let run = RelayRun(target: target, targetImage: incoming, forward: forward, timeline: timeline,
                           outgoing: outgoingLayers, incoming: incomingLayers)
        CATransaction.withoutActions {
            for slice in outgoingLayers + incomingLayers { layer.addSublayer(slice) }
            canvas.showsText = false
        }
        self.run = run
        apply(run)
        return run
    }

    /// One layer per paragraph, each showing its band of the page's one image.
    private func slices(of image: CGImage, page: PagedPage) -> [CALayer] {
        let scale = max(style?.scale ?? 1, 1)
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        guard size.height > 0 else { return [] }
        return Self.bands(of: page, height: size.height, scale: scale).map { band in
            let slice = CALayer()
            slice.contents = image
            slice.contentsScale = scale
            slice.contentsRect = CGRect(x: 0, y: band.lowerBound / size.height, width: 1,
                                        height: (band.upperBound - band.lowerBound) / size.height)
            slice.frame = CGRect(x: pageFrame.minX, y: pageFrame.minY + band.lowerBound, width: size.width,
                                 height: band.upperBound - band.lowerBound)
            return slice
        }
    }

    /// Bands that tile the page from top to bottom, one per paragraph, cut halfway across each
    /// paragraph gap and on whole pixels, so every pixel of the page moves with exactly one band.
    private static func bands(of page: PagedPage, height: CGFloat, scale: CGFloat) -> [ClosedRange<CGFloat>] {
        let boxes = page.layout?.paragraphs(onPage: page.index).map(\.bounds).filter { !$0.isNull } ?? []
        guard boxes.count > 1 else { return [0...height] }
        var bands: [ClosedRange<CGFloat>] = []
        var top: CGFloat = 0
        for (above, below) in zip(boxes, boxes.dropFirst()) {
            let cut = min(max(((above.maxY + below.minY) / 2 * scale).rounded() / scale, top), height)
            bands.append(top...cut)
            top = cut
        }
        bands.append(top...height)
        return bands
    }

    private func apply(_ run: RelayRun) {
        // Forward turns carry the text towards the left edge, the way a page leaves.
        let direction: CGFloat = run.forward ? -1 : 1
        let timeline = run.timeline
        CATransaction.withoutActions {
            for (index, slice) in run.outgoing.enumerated() {
                let gone = timeline.outgoing(index, at: run.time)
                slice.setAffineTransform(CGAffineTransform(translationX: direction * timeline.travel * gone, y: 0))
                slice.opacity = Float(timeline.outgoingOpacity(gone))
            }
            for (index, slice) in run.incoming.enumerated() {
                let arrived = timeline.incoming(index, at: run.time)
                slice.setAffineTransform(
                    CGAffineTransform(translationX: -direction * timeline.travel * (1 - arrived), y: 0))
                slice.opacity = Float(arrived)
            }
        }
    }

    /// Snaps a playing turn to where it was going.
    private func finishRun() {
        guard let run else { return }
        let completed = run.isCommitted
        stopRun()
        if completed, let style {
            canvas.show(run.target, style: style, in: pageFrame, prerendered: run.targetImage)
        }
        prepareNext()
    }

    private func stopRun() {
        guard let run else { return }
        self.run = nil
        link?.invalidate()
        link = nil
        CATransaction.withoutActions {
            for slice in run.outgoing + run.incoming { slice.removeFromSuperlayer() }
            canvas.showsText = true
        }
    }

    private func startLink() {
        guard link == nil else { return }
        lastTick = nil
        let link = CADisplayLink(target: RelayLinkTarget(self), selector: #selector(RelayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let run else {
            link.invalidate()
            self.link = nil
            return
        }
        let now = link.targetTimestamp
        let step = now - (lastTick ?? link.timestamp)
        lastTick = now
        switch run.goal {
        case .finish:
            run.time = min(run.time + step, run.timeline.total)
        case .back:
            run.time = max(run.time - step * 1.5, 0)
        case .finger:
            return
        }
        apply(run)
        if run.goal == .finish ? run.time >= run.timeline.total : run.time <= 0 { finishRun() }
    }

    private func preparedImage(for page: PagedPage) -> CGImage? {
        prepared?.page == page ? prepared?.image : nil
    }

    /// Draws the page a forward turn reaches off the main actor, so the turn starts without a
    /// draw. Backward turns draw when they start.
    private func prepareNext() {
        preparing?.cancel()
        guard let current, let style, let next = chapters?.cachedNeighbour(of: current, forward: true),
              prepared?.page != next else { return }
        let size = pageFrame.size
        preparing = Task { [weak self] in
            let image = await Task.detached(priority: .utility) {
                PageRenderer.image(of: next, size: size, style: style)
            }.value
            guard !Task.isCancelled, let self, let image, self.style == style, self.pageFrame.size == size else {
                return
            }
            self.prepared = (next, image)
        }
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        switch taps.action(at: tap.location(in: self), in: bounds.size) {
        case .menu: onMenu()
        case .forward: turn(forward: true)
        case .back: turn(forward: false)
        }
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            finishRun()
            let moved = pan.translation(in: self).x
            let forward = (moved != 0 ? moved : pan.velocity(in: self).x) < 0
            // Past either end of the book, or while the next chapter lays out, the drag does nothing.
            guard let current, let target = chapters?.cachedNeighbour(of: current, forward: forward),
                  let run = startRun(to: target, forward: forward) else { return }
            run.goal = .finger
        case .changed:
            guard let run, run.goal == .finger else { return }
            run.time = dragProgress(pan, run) * run.timeline.total
            apply(run)
        case .ended, .cancelled, .failed:
            guard let run, run.goal == .finger else { return }
            let speed = pan.velocity(in: self).x * (run.forward ? -1 : 1)
            let completes = pan.state == .ended && (speed > 500 || (speed > -500 && dragProgress(pan, run) > 0.3))
            if completes {
                commit(run.target)
                run.isCommitted = true
                run.goal = .finish
            } else {
                run.goal = .back
            }
            startLink()
        default:
            break
        }
    }

    private func dragProgress(_ pan: UIPanGestureRecognizer, _ run: RelayRun) -> Double {
        guard bounds.width > 0 else { return 0 }
        let travelled = pan.translation(in: self).x * (run.forward ? -1 : 1)
        return min(max(Double(travelled / bounds.width), 0), 1)
    }

    /// Only a sideways drag turns; anything else is left to the views around the page.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer.view === self, let pan = recognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    // VoiceOver's three-finger swipes, and its reading on through pages (`.causesPageTurn`).
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .left, .next: turn(forward: true, animated: false)
        case .right, .previous: turn(forward: false, animated: false)
        default: return false
        }
        return true
    }
}

private final class RelayRun {
    enum Goal {
        case finger, finish, back
    }

    let target: PagedPage
    let targetImage: CGImage
    let forward: Bool
    let timeline: RelayTimeline
    let outgoing: [CALayer]
    let incoming: [CALayer]
    var time: Double = 0
    var goal = Goal.finger
    var isCommitted = false

    init(target: PagedPage, targetImage: CGImage, forward: Bool, timeline: RelayTimeline,
         outgoing: [CALayer], incoming: [CALayer]) {
        self.target = target
        self.targetImage = targetImage
        self.forward = forward
        self.timeline = timeline
        self.outgoing = outgoing
        self.incoming = incoming
    }
}

/// A display link keeps its target alive; this one holds the view weakly.
@MainActor
private final class RelayLinkTarget: NSObject {
    weak var view: RelayTurnView?

    init(_ view: RelayTurnView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        view?.tick(link)
    }
}
