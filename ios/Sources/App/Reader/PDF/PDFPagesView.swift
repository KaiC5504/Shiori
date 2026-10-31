import PDFKit
import SwiftUI

/// How the PDF's pages are laid out (spec §7.12).
enum PDFPageLayout: String, CaseIterable {
    case vertical, pages

    var title: LocalizedStringKey {
        switch self {
        case .vertical: "Vertical scroll"
        case .pages: "Page by page"
        }
    }

    var icon: ShioriIcon {
        switch self {
        case .vertical: .layoutList
        case .pages: .book
        }
    }
}

/// Moves the pages from SwiftUI without holding the PDFView in state.
@MainActor
final class PDFPagesController {
    fileprivate weak var view: PDFPagesUIView?

    func go(toPage index: Int) {
        guard let view, let page = view.document?.page(at: index) else { return }
        view.go(to: page)
    }

    func go(to destination: PDFDestination) {
        view?.go(to: destination)
    }

    /// One page on or back, stepped by PDFKit, so its own idea of the current page moves with it.
    func turn(forward: Bool) {
        if forward { view?.goToNextPage(nil) } else { view?.goToPreviousPage(nil) }
    }
}

/// PDFKit's pages, continuous or one at a time, cropped to `contentRects` when given.
struct PDFPagesView: UIViewRepresentable {
    let document: PDFDocument
    let layout: PDFPageLayout
    /// Each page's measured content (`PDFPageRenderer.contentRect`), or nil for the pages as stored.
    let contentRects: [Int: CGRect]?
    /// 0-based, shown once the view has a size.
    let startPage: Int
    let controller: PDFPagesController
    let onPageChange: (Int) -> Void
    /// The page PDFKit actually shows once it has landed on `startPage` or after a relayout.
    let onSettle: (Int) -> Void
    /// The tap's point and the view's size.
    let onTap: (CGPoint, CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFPagesUIView {
        let view = PDFPagesUIView()
        view.backgroundColor = UIColor(Tokens.paper)
        view.displaysPageBreaks = true
        view.maxScaleFactor = 5
        view.document = document
        view.pendingPage = startPage
        Self.apply(layout, to: view)
        let coordinator = context.coordinator
        coordinator.layout = layout
        coordinator.attach(to: view)
        coordinator.applyCrops(contentRects, to: view)
        controller.view = view
        return view
    }

    func updateUIView(_ view: PDFPagesUIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller.view = view
        if coordinator.layout != layout {
            coordinator.layout = layout
            view.relayout { Self.apply(layout, to: view) }
        }
        if coordinator.contentRects != contentRects {
            coordinator.applyCrops(contentRects, to: view)
        }
    }

    static func dismantleUIView(_ view: PDFPagesUIView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    fileprivate static func apply(_ layout: PDFPageLayout, to view: PDFView) {
        switch layout {
        case .vertical:
            view.usePageViewController(false, withViewOptions: nil)
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.pageBreakMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        case .pages:
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 16])
        }
        view.autoScales = true
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFPagesView
        var layout: PDFPageLayout?
        private(set) var contentRects: [Int: CGRect]?
        /// The crop boxes as stored in the file, so cropping can be undone.
        private var stored: [Int: CGRect] = [:]

        init(_ parent: PDFPagesView) {
            self.parent = parent
        }

        func attach(to view: PDFPagesUIView) {
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged(_:)),
                                                   name: .PDFViewPageChanged, object: view)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
            view.onSettled = { [weak self, weak view] in
                guard let self, let view, let index = Self.pageIndex(in: view) else { return }
                DispatchQueue.main.async { [weak self] in self?.parent.onSettle(index) }
            }
        }

        func applyCrops(_ rects: [Int: CGRect]?, to view: PDFPagesUIView) {
            contentRects = rects
            guard let document = view.document else { return }
            var changes: [(page: PDFPage, box: CGRect)] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let box = stored[index] ?? page.bounds(for: .cropBox)
                stored[index] = box
                let target = rects?[index].map { PDFMargins.crop(content: $0, in: box) } ?? box
                if page.bounds(for: .cropBox) != target { changes.append((page, target)) }
            }
            guard !changes.isEmpty else { return }
            // Page space doesn't move with the crop, so the point at the top now is the one to
            // put back. Pending before the change, so the pages it shifts aren't reported as reading.
            let destination = view.hasSettled && layout == .vertical ? view.currentDestination : nil
            if let destination { view.restore(destination) }
            for change in changes {
                change.page.setBounds(change.box, for: .cropBox)
            }
            guard view.hasSettled else { return }
            if layout == .pages {
                // The page view controller keeps each page's old size until it's rebuilt.
                view.relayout {
                    view.usePageViewController(false, withViewOptions: nil)
                    PDFPagesView.apply(.pages, to: view)
                }
            } else if destination == nil {
                view.layoutDocumentView()
            }
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFPagesUIView, !view.isRestoring else { return }
            report(view)
        }

        private func report(_ view: PDFPagesUIView) {
            guard let index = Self.pageIndex(in: view) else { return }
            // PDFKit posts page changes from inside layout, which can be inside a SwiftUI update.
            DispatchQueue.main.async { [weak self] in self?.parent.onPageChange(index) }
        }

        private static func pageIndex(in view: PDFView) -> Int? {
            guard let document = view.document, let page = view.currentPage else { return nil }
            let index = document.index(for: page)
            return index >= 0 && index < document.pageCount ? index : nil
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            parent.onTap(recognizer.location(in: view), view.bounds.size)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// A double tap zooms, so a single tap waits until it can't be one.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            ((other as? UITapGestureRecognizer)?.numberOfTapsRequired ?? 0) > 1
        }

        /// A link is PDFKit's to follow.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view as? PDFView else { return true }
            let point = gestureRecognizer.location(in: view)
            guard let page = view.page(for: point, nearest: false),
                  let annotation = page.annotation(at: view.convert(point, to: page))
            else { return true }
            return annotation.action == nil && annotation.url == nil
        }
    }
}

/// A PDFView that can be told where to land before it has laid anything out.
final class PDFPagesUIView: PDFView {
    /// 0-based; shown at the next layout with a size.
    var pendingPage: Int?
    var pendingDestination: PDFDestination?
    /// Called once a pending page or destination has been shown.
    var onSettled: (() -> Void)?
    private(set) var hasSettled = false
    private var settling = false

    /// While true, page changes are PDFKit laying out, not the reader moving.
    var isRestoring: Bool { settling || pendingPage != nil || pendingDestination != nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !settling, pendingPage != nil || pendingDestination != nil,
              bounds.width > 0, bounds.height > 0 else { return }
        settling = true
        // PDFKit lays the document out after this pass; a go(to:) inside it lands on the first page.
        DispatchQueue.main.async { [weak self] in self?.settle() }
    }

    func restore(_ destination: PDFDestination) {
        pendingDestination = destination
        setNeedsLayout()
    }

    /// Runs `change` faded out, then puts the current page back.
    func relayout(_ change: @escaping () -> Void) {
        let index = pendingPage ?? currentPage.flatMap { page in document?.index(for: page) } ?? 0
        UIView.animate(withDuration: 0.12) {
            self.alpha = 0
        } completion: { _ in
            // Pending first: the change posts page changes of its own, which aren't the reader's.
            self.pendingDestination = nil
            self.pendingPage = index
            change()
            self.setNeedsLayout()
        }
    }

    private func settle() {
        defer {
            settling = false
            hasSettled = true
            onSettled?()
            if alpha < 1 {
                UIView.animate(withDuration: 0.2) { self.alpha = 1 }
            }
        }
        guard let document, document.pageCount > 0 else { return }
        layoutDocumentView()
        if let destination = pendingDestination {
            go(to: destination)
        } else if let index = pendingPage, let page = document.page(at: min(max(index, 0), document.pageCount - 1)) {
            go(to: page)
        }
        pendingPage = nil
        pendingDestination = nil
    }
}
