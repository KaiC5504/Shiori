import ShioriLibrary
import SwiftUI
import UIKit

/// Apple's page curl (spec §7.2, item 3): `UIPageViewController` turning `PageCanvas` pages.
/// The curl has its own pace, so the relay's speed doesn't apply. It's double-sided because the
/// single-sided curl washes the page's back in a cold white that matches no theme's paper.
struct CurlPages: UIViewControllerRepresentable {
    let page: PagedPage
    let style: PageStyle
    let pageFrame: CGRect
    let taps: PageTaps
    let chapters: PagedChapters
    let onTurn: (PagedPage) -> Void
    let onMenu: () -> Void

    func makeUIViewController(context: Context) -> CurlController {
        CurlController()
    }

    func updateUIViewController(_ controller: CurlController, context: Context) {
        controller.taps = taps
        controller.chapters = chapters
        controller.onTurn = onTurn
        controller.onMenu = onMenu
        controller.show(page, style: style, in: pageFrame)
    }
}

final class CurlController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var taps = PageTaps(layout: .standard, bothSidesForward: false)
    var chapters: PagedChapters?
    var onTurn: (PagedPage) -> Void = { _ in }
    var onMenu: () -> Void = {}

    /// Double-sided before SwiftUI hands over the first page, and after the pager's view loads,
    /// which may set it back.
    private let pager: UIPageViewController = {
        let pager = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        pager.loadViewIfNeeded()
        pager.isDoubleSided = true
        return pager
    }()
    private var current: PagedPage?
    private var style: PageStyle?
    private var pageFrame: CGRect = .zero
    private var isTurning = false
    /// A jump or new layout that arrived mid-curl; the page controller can't be reset then.
    private var deferred: PagedPage?

    override func loadView() {
        let stage = CurlStage()
        stage.onScroll = { [weak self] forward in self?.turn(forward: forward, animated: false) }
        view = stage
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(pager)
        pager.view.frame = view.bounds
        pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pager.view)
        pager.didMove(toParent: self)
        pager.dataSource = self
        pager.delegate = self
        // Its own edge taps would turn pages; Shiori's tap zones decide instead.
        for recognizer in pager.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    func show(_ page: PagedPage, style: PageStyle, in pageFrame: CGRect) {
        let restyled = style != self.style || pageFrame != self.pageFrame
        self.style = style
        self.pageFrame = pageFrame
        if restyled {
            for shown in pager.viewControllers ?? [] {
                (shown as? CurlPage)?.show(style: style, in: pageFrame)
                (shown as? CurlBack)?.show(style: style, in: pageFrame)
            }
        }
        guard page != current else { return }
        if isTurning {
            deferred = page
            return
        }
        #if DEBUG
        let first = current == nil
        #endif
        current = page
        pager.setViewControllers(sheet(page, style: style), direction: .forward, animated: false)
        #if DEBUG
        if first, DemoLaunch.freezesCurl { freezeForDemo() }
        #endif
    }

    /// iOS 27 wants the page alone when nothing moves, and the page plus `turning`'s back for an
    /// animated curl; any other count throws.
    private func sheet(_ page: PagedPage, turning: PagedPage? = nil, style: PageStyle) -> [UIViewController] {
        let front = CurlPage(page: page, style: style, pageFrame: pageFrame)
        guard let turning, pager.isDoubleSided else { return [front] }
        return [front, CurlBack(page: turning, style: style, pageFrame: pageFrame)]
    }

    private func turn(forward: Bool, animated: Bool = true) {
        guard !isTurning, let current, let chapters else { return }
        if let target = chapters.cachedNeighbour(of: current, forward: forward) {
            curl(to: target, forward: forward, animated: animated)
            return
        }
        Task { [weak self] in
            guard let target = await chapters.neighbour(of: current, forward: forward),
                  let self, self.current == current, !self.isTurning else { return }
            self.curl(to: target, forward: forward, animated: animated)
        }
    }

    private func curl(to target: PagedPage, forward: Bool, animated: Bool) {
        guard let style else { return }
        // Forward, the current page curls away; back, the target's sheet curls in.
        let turning = animated ? (forward ? current : target) : nil
        isTurning = animated
        current = target
        onTurn(target)
        pager.setViewControllers(sheet(target, turning: turning, style: style),
                                 direction: forward ? .forward : .reverse, animated: animated) { [weak self] _ in
            guard animated else { return }
            self?.finishTurning()
        }
    }

    private func finishTurning() {
        isTurning = false
        guard let deferred, let style else { return }
        self.deferred = nil
        show(deferred, style: style, in: pageFrame)
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        switch taps.action(at: tap.location(in: view), in: view.bounds.size) {
        case .menu: onMenu()
        case .forward: turn(forward: true)
        case .back: turn(forward: false)
        }
    }

    // Double-sided, the pages run front, back, front: going back, the sheet that curls in is the
    // previous page's back, then its front.
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let style else { return nil }
        if let back = viewController as? CurlBack {
            return CurlPage(page: back.page, style: style, pageFrame: pageFrame)
        }
        guard let target = neighbour(of: viewController, forward: false) else { return nil }
        return pageViewController.isDoubleSided
            ? CurlBack(page: target, style: style, pageFrame: pageFrame)
            : CurlPage(page: target, style: style, pageFrame: pageFrame)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let style else { return nil }
        if let back = viewController as? CurlBack {
            return chapters?.cachedNeighbour(of: back.page, forward: true)
                .map { CurlPage(page: $0, style: style, pageFrame: pageFrame) }
        }
        guard let page = (viewController as? CurlPage)?.page,
              let target = neighbour(of: viewController, forward: true) else { return nil }
        return pageViewController.isDoubleSided
            ? CurlBack(page: page, style: style, pageFrame: pageFrame)
            : CurlPage(page: target, style: style, pageFrame: pageFrame)
    }

    /// Nil at either end of the book, and while the next chapter is still being laid out.
    private func neighbour(of viewController: UIViewController, forward: Bool) -> PagedPage? {
        guard !isTurning, let page = (viewController as? CurlPage)?.page else { return nil }
        return chapters?.cachedNeighbour(of: page, forward: forward)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        isTurning = true
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let page = pageViewController.viewControllers?.lazy.compactMap({ $0 as? CurlPage }).first?.page,
           page != current {
            current = page
            onTurn(page)
        }
        finishTurning()
    }

    #if DEBUG
    /// Stops a forward curl partway, so a screenshot can show the page's back.
    private func freezeForDemo() {
        Task { [weak self] in
            // Past the reader's own cover sliding in.
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            view.layer.speed = 0
            turn(forward: true)
            // A later run loop, so the curl's animations start on the frozen clock first.
            try? await Task.sleep(for: .milliseconds(100))
            view.layer.timeOffset = 0.3
        }
    }
    #endif
}

private final class CurlPage: UIViewController {
    let page: PagedPage
    private let canvas = PageCanvas()
    private var style: PageStyle
    private var pageFrame: CGRect

    init(page: PagedPage, style: PageStyle, pageFrame: CGRect) {
        self.page = page
        self.style = style
        self.pageFrame = pageFrame
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = canvas
        canvas.show(page, style: style, in: pageFrame)
    }

    func show(style: PageStyle, in pageFrame: CGRect) {
        self.style = style
        self.pageFrame = pageFrame
        if isViewLoaded { canvas.show(page, style: style, in: pageFrame) }
    }
}

/// The underside of a page: the theme's paper, a shade toward the ink, with the page's text
/// showing through faintly and mirrored, as it would through thin paper.
private final class CurlBack: UIViewController {
    let page: PagedPage
    private let showThrough = CALayer()
    private var style: PageStyle
    private var pageFrame: CGRect
    private var image: CGImage?

    init(page: PagedPage, style: PageStyle, pageFrame: CGRect) {
        self.page = page
        self.style = style
        self.pageFrame = pageFrame
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = UIView()
        view.accessibilityElementsHidden = true
        showThrough.opacity = 0.08
        showThrough.transform = CATransform3DMakeScale(-1, 1, 1)
        view.layer.addSublayer(showThrough)
        draw()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        place()
    }

    func show(style: PageStyle, in pageFrame: CGRect) {
        if style != self.style || pageFrame.size != self.pageFrame.size { image = nil }
        self.style = style
        self.pageFrame = pageFrame
        if isViewLoaded { draw() }
    }

    private func draw() {
        view.backgroundColor = Self.blend(style.paper, toward: style.ink, by: 0.05)
        if image == nil { image = PageRenderer.image(of: page, size: pageFrame.size, style: style) }
        CATransaction.withoutActions {
            showThrough.contents = image
            showThrough.contentsScale = max(style.scale, 1)
        }
        place()
    }

    /// Seen from behind, the text's box sits mirrored across the page.
    private func place() {
        let scale = max(style.scale, 1)
        let size = image.map { CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) } ?? .zero
        let x = view.bounds.width - pageFrame.minX - size.width
        CATransaction.withoutActions {
            showThrough.bounds = CGRect(origin: .zero, size: size)
            showThrough.position = CGPoint(x: x + size.width / 2, y: pageFrame.minY + size.height / 2)
        }
    }

    private static func blend(_ paper: CGColor, toward ink: CGColor, by amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard UIColor(cgColor: paper).getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              UIColor(cgColor: ink).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        else { return UIColor(cgColor: paper) }
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}

/// Takes VoiceOver's three-finger swipes, and its reading on through pages.
private final class CurlStage: UIView {
    var onScroll: ((Bool) -> Void)?

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .left, .next: onScroll?(true)
        case .right, .previous: onScroll?(false)
        default: return false
        }
        return true
    }
}
