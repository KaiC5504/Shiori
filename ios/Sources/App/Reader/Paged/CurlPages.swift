import ShioriLibrary
import SwiftUI
import UIKit

/// Apple's page curl (spec §7.2, item 3): `UIPageViewController` turning `PageCanvas` pages.
/// The curl has its own pace, so the relay's speed doesn't apply.
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

    private let pager = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
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
            for case let shown as CurlPage in pager.viewControllers ?? [] {
                shown.show(style: style, in: pageFrame)
            }
        }
        guard page != current else { return }
        if isTurning {
            deferred = page
            return
        }
        current = page
        pager.setViewControllers([CurlPage(page: page, style: style, pageFrame: pageFrame)], direction: .forward,
                                 animated: false)
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
        isTurning = animated
        current = target
        onTurn(target)
        pager.setViewControllers([CurlPage(page: target, style: style, pageFrame: pageFrame)],
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

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        neighbour(of: viewController, forward: false)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        neighbour(of: viewController, forward: true)
    }

    /// Nil at either end of the book, and while the next chapter is still being laid out.
    private func neighbour(of viewController: UIViewController, forward: Bool) -> UIViewController? {
        guard !isTurning, let page = (viewController as? CurlPage)?.page, let style,
              let target = chapters?.cachedNeighbour(of: page, forward: forward) else { return nil }
        return CurlPage(page: target, style: style, pageFrame: pageFrame)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        isTurning = true
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let page = (pageViewController.viewControllers?.first as? CurlPage)?.page, page != current {
            current = page
            onTurn(page)
        }
        finishTurning()
    }
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
