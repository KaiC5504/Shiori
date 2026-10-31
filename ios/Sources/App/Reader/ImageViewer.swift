import os
import Photos
import SwiftUI
import UIKit

private let viewerLog = Logger(subsystem: "com.kaichuan.shiori", category: "images")

struct ImageViewerRequest: Identifiable {
    let id = UUID()
    let images: [ReaderImage]
    let start: Int
}

/// The full-screen zoom viewer for a chapter's illustrations (spec §7.11): a pager whose pages
/// pinch and double-tap zoom, a pull down at 1× to close, and Save to Photos.
struct ImageViewer: View {
    let request: ImageViewerRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerModel) private var reader
    @Environment(\.motionReduced) private var reduced
    @State private var position: ScrollPosition
    @State private var zoomed = false
    @State private var pulling = false
    @State private var showsControls = true
    @State private var saving = false
    @State private var notice: SaveNotice?
    @State private var saves = 0
    @State private var failures = 0
    private let start: Int

    init(request: ImageViewerRequest) {
        self.request = request
        start = min(max(request.start, 0), max(request.images.count - 1, 0))
        _position = State(initialValue: ScrollPosition(id: start))
    }

    private var current: Int {
        min(max(position.viewID(type: Int.self) ?? start, 0), max(request.images.count - 1, 0))
    }

    private var controlsVisible: Bool { showsControls && !pulling }

    var body: some View {
        ZStack {
            ReaderTheme.night.paper
                .ignoresSafeArea()
            pager
            controls
        }
        // The viewer is dark on every theme, so tokens and glass take their dark faces.
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .onChange(of: current) { pulling = false }
        .shioriHaptic(.selection, trigger: current)
        .shioriHaptic(.success, trigger: saves)
        .shioriHaptic(.error, trigger: failures)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(request.images.indices, id: \.self) { index in
                    ViewerPage(image: request.images[index],
                               onZoom: { zoomed = $0 },
                               onPulling: { isPulling in
                                   withAnimation(Motion.animation(.easeOut(duration: 0.2), reduced: reduced)) {
                                       pulling = isPulling
                                   }
                               },
                               onPullClose: { dismiss() },
                               onTap: toggleControls)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition($position)
        // A zoomed page pans with the finger; the pager waits until it's back at 1×.
        .scrollDisabled(zoomed)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }

    private var controls: some View {
        GlassEffectContainer {
            VStack(spacing: 12) {
                ZStack {
                    if request.images.count > 1 { counter }
                    HStack {
                        closeButton
                        Spacer(minLength: 0)
                    }
                }
                .opacity(controlsVisible ? 1 : 0)
                .offset(y: controlsVisible || reduced ? 0 : -12)
                Spacer(minLength: 0)
                if let notice {
                    NoticeCapsule(notice: notice)
                        .id(notice.id)
                        .transition(reduced ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                saveButton
                    .opacity(controlsVisible ? 1 : 0)
                    .offset(y: controlsVisible || reduced ? 0 : 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .allowsHitTesting(controlsVisible)
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: controlsVisible)
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: notice)
        .task(id: notice) {
            guard notice != nil, (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
            notice = nil
        }
    }

    private var closeButton: some View {
        Button(action: { dismiss() }) {
            IconView(.close, size: 20)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Close"))
    }

    private var counter: some View {
        Text(verbatim: "\(current + 1) / \(request.images.count)")
            .font(.system(.subheadline, design: .monospaced).weight(.medium))
            .foregroundStyle(Tokens.ink)
            .contentTransition(reduced ? .opacity : .numericText(value: Double(current)))
            .animation(Motion.animation(Motion.press, reduced: reduced), value: current)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .glassEffect(.regular, in: .capsule)
            .accessibilityLabel(Text("Illustration \(current + 1) of \(request.images.count)"))
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 8) {
                if saving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Tokens.ink)
                        .frame(width: 20, height: 20)
                } else {
                    IconView(.image, size: 20)
                }
                Text("Save to Photos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(saving || request.images.isEmpty)
    }

    private func toggleControls() {
        withAnimation(Motion.animation(Motion.reveal, reduced: reduced)) {
            showsControls.toggle()
        }
    }

    /// Saves the picture as stored in the book, not the downsampled one on screen.
    private func save() {
        guard !saving, let reader, request.images.indices.contains(current) else { return }
        let path = request.images[current].path
        saving = true
        Task {
            let saved = await Self.addToPhotos(await reader.imageData(at: path))
            saving = false
            notice = SaveNotice(saved: saved)
            if saved { saves += 1 } else { failures += 1 }
        }
    }

    /// Add-only: Shiori never reads the library, and iOS asks the first time Save is tapped.
    nonisolated private static func addToPhotos(_ data: Data?) async -> Bool {
        guard let data else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            viewerLog.notice("saving to Photos not allowed: \(status.rawValue)")
            return false
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return true
        } catch {
            viewerLog.error("saving to Photos failed: \(error)")
            return false
        }
    }
}

private struct SaveNotice: Equatable {
    let id = UUID()
    let saved: Bool
}

private struct NoticeCapsule: View {
    let notice: SaveNotice

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            IconView(notice.saved ? .check : .warning, active: notice.saved, size: 20)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .onAppear { AccessibilityNotification.Announcement(String(localized: message)).post() }
    }

    /// Carries the in-app language, which the announcement wouldn't otherwise get.
    private var message: LocalizedStringResource {
        var message: LocalizedStringResource = notice.saved ? "Saved to Photos" : "Couldn't save the image."
        message.locale = locale
        return message
    }
}

/// One picture: the row's copy at once if it's cached, then a sharper one for zooming.
private struct ViewerPage: View {
    let image: ReaderImage
    let onZoom: (Bool) -> Void
    let onPulling: (Bool) -> Void
    let onPullClose: () -> Void
    let onTap: () -> Void

    @Environment(\.readerModel) private var reader
    @Environment(\.displayScale) private var displayScale
    @Environment(\.motionReduced) private var reduced
    @State private var picture: UIImage?
    @State private var failed = false

    var body: some View {
        let shown = picture ?? reader.flatMap { ReaderImageLoader.cached(image, in: $0) }
        GeometryReader { geometry in
            ZoomingImage(picture: shown, reduced: reduced, onZoom: onZoom, onPulling: onPulling,
                         onPullClose: onPullClose, onTap: onTap)
                .overlay {
                    if shown == nil {
                        if failed {
                            IconView(.image, size: 32)
                                .opacity(0.45)
                        } else {
                            ProgressView()
                                .tint(Tokens.inkSecondary)
                        }
                    }
                }
                .task(id: image) {
                    // Twice the screen, so a 2× zoom stays sharp; capped, since a few pages
                    // stay alive beside the one shown.
                    let longest = max(geometry.size.width, geometry.size.height, 320)
                    await load(maxPixel: min(longest * displayScale * 2, 3072))
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Illustration"))
        .accessibilityAddTraits(.isImage)
    }

    private func load(maxPixel: CGFloat) async {
        guard let reader else {
            failed = true
            return
        }
        let loaded = await ReaderImageLoader.load(image, from: reader, maxPixel: maxPixel, caching: false)
        guard !Task.isCancelled else { return }
        if let loaded { picture = loaded }
        failed = loaded == nil
    }
}

/// UIScrollView's own zooming: pinch with its bounce, panning with momentum, and a double tap
/// that zooms on the point tapped, none of which SwiftUI's gestures give inside a pager.
private struct ZoomingImage: UIViewRepresentable {
    let picture: UIImage?
    let reduced: Bool
    let onZoom: (Bool) -> Void
    let onPulling: (Bool) -> Void
    let onPullClose: () -> Void
    let onTap: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        ZoomScrollView()
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.reduced = reduced
        view.onZoom = onZoom
        view.onPulling = onPulling
        view.onPullClose = onPullClose
        view.onTap = onTap
        view.picture = picture
    }
}

private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    var reduced = false
    var onZoom: (Bool) -> Void = { _ in }
    var onPulling: (Bool) -> Void = { _ in }
    var onPullClose: () -> Void = {}
    var onTap: () -> Void = {}

    private let imageView = UIImageView()
    private var fittedSize: CGSize = .zero
    private var isZoomed = false
    private var pull: CGFloat = 0
    private var isPulling = false

    var picture: UIImage? {
        didSet {
            guard picture !== oldValue else { return }
            imageView.image = picture
            // The sharper copy that replaces the row's has the same shape; refitting would
            // throw away a zoom already under way.
            if let old = oldValue, let new = picture, Self.aspect(old) > 0,
               abs(Self.aspect(old) - Self.aspect(new)) < 0.01 { return }
            fit()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        // At 1× only the vertical bounce is live: horizontal swipes fall through to the pager,
        // and a pull down is the close gesture.
        alwaysBounceVertical = true
        alwaysBounceHorizontal = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize { fit() }
    }

    private static func aspect(_ image: UIImage) -> CGFloat {
        image.size.height > 0 ? image.size.width / image.size.height : 0
    }

    /// Back to 1×, the picture fitted to the page and centred.
    private func fit() {
        fittedSize = bounds.size
        zoomScale = minimumZoomScale
        let size = picture?.size ?? .zero
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            imageView.frame = .zero
            contentSize = .zero
            return
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        centre()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }

    /// Insets rather than a frame offset, so the picture stays centred at every zoom.
    private func centre() {
        let dx = max((bounds.width - contentSize.width) / 2, 0)
        let dy = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        let zoomed = zoomScale > minimumZoomScale + 0.01
        guard zoomed != isZoomed else { return }
        isZoomed = zoomed
        onZoom(zoomed)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        pull = isZoomed ? 0 : max(-(contentOffset.y + contentInset.top), 0)
        let pulling = pull > 12
        guard pulling != isPulling else { return }
        isPulling = pulling
        onPulling(pulling)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // Velocity is in points per millisecond; a negative y is a flick downwards.
        guard !isZoomed, pull > 70 || (pull > 24 && velocity.y < -1) else { return }
        onPullClose()
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        let change = {
            if self.isZoomed {
                self.setZoomScale(self.minimumZoomScale, animated: !self.reduced)
            } else {
                let point = gesture.location(in: self.imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: self.bounds.width / scale, height: self.bounds.height / scale)
                self.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                     width: size.width, height: size.height), animated: !self.reduced)
            }
        }
        if reduced {
            UIView.transition(with: self, duration: 0.15, options: .transitionCrossDissolve, animations: change)
        } else {
            change()
        }
    }

    @objc private func tapped() {
        onTap()
    }
}
