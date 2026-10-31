import SwiftUI

/// The PDF reader's floating glass chrome, laid out like the text reader's (spec §7.7): a top
/// bar with back and the title, and one bottom panel with the page slider and the PDF's tools.
struct PDFChrome: View {
    let title: String
    /// 0-based.
    let page: Int
    let pageCount: Int
    /// The outline entry a page is in, for the line above the slider.
    let section: (Int) -> String?
    let hasOutline: Bool
    @Binding var layout: PDFPageLayout
    @Binding var cropsMargins: Bool
    /// Margins are still being measured, so the crop hasn't shown yet.
    let isCropping: Bool
    let onBack: () -> Void
    let onJump: (Int) -> Void
    let onThumbnails: () -> Void
    let onContents: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var scrub: Double?
    @State private var insets = EdgeInsets()

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                topBar
                    .modifier(PDFChromeSlide(edge: .top))
                Spacer(minLength: 0)
                panel
                    .modifier(PDFChromeSlide(edge: .bottom))
            }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
        .shioriHaptic(.selection, trigger: cropsMargins)
        .transition(PDFChromeTransition())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                IconView(.back, size: 22)
                    .frame(width: PDFChromeMetrics.round, height: PDFChromeMetrics.round)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Tokens.paper.opacity(0.35)).interactive(), in: .circle)
            .accessibilityLabel(Text("Back"))
            Text(verbatim: title)
                .font(.headline)
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            // Balances the back button so the title stays centred.
            Color.clear
                .frame(width: PDFChromeMetrics.round, height: PDFChromeMetrics.round)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, insets.top > 0 ? 0 : 10)
        .padding(.bottom, 10)
        .background {
            // Pages scroll under the title; solid paper to the bar's edge keeps it legible on any page.
            VStack(spacing: 0) {
                Tokens.paper
                LinearGradient(colors: [Tokens.paper, Tokens.paper.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
            .padding(.bottom, -28)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return VStack(spacing: 0) {
            placeLine
                .padding(.bottom, 8)
            PDFPageSlider(page: page, count: pageCount, scrub: $scrub, onJump: onJump)
            Rectangle()
                .fill(Tokens.ink.opacity(0.12))
                .frame(height: 1 / displayScale)
                .padding(.top, 10)
                .padding(.bottom, 6)
            tools
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background {
            // Swallows taps between the controls, so they don't reach the page and close the chrome.
            Color.clear.contentShape(shape).onTapGesture {}
        }
        .glassEffect(.regular.tint(Tokens.paper.opacity(0.5)), in: shape)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, insets.bottom > 0 ? 4 : 16)
    }

    private var placeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: section(shown) ?? "")
                .font(.caption)
                .foregroundStyle(Tokens.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: pageCount > 0 ? "\(shown + 1) / \(pageCount)" : "")
                .font(.system(size: 12, design: .monospaced))
                .tracking(1)
                .foregroundStyle(scrub == nil ? Tokens.inkSecondary : Tokens.ink)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("pdf.page")
        }
        .animation(.easeInOut(duration: 0.15), value: scrub == nil)
    }

    private var tools: some View {
        HStack(spacing: 0) {
            Button(action: onThumbnails) { Text("Thumbnails") }
                .buttonStyle(PDFToolStyle(icon: .layoutGrid))
                .accessibilityIdentifier("pdf.thumbnails")
            if hasOutline {
                Button(action: onContents) { Text("Contents") }
                    .buttonStyle(PDFToolStyle(icon: .contents))
                    .accessibilityIdentifier("pdf.contents")
            }
            Menu {
                Picker(selection: $layout) {
                    ForEach(PDFPageLayout.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text("Layout")
                }
            } label: {
                PDFToolFace(icon: layout.icon, on: false, pressed: false, busy: false) { Text("Layout") }
            }
            .accessibilityIdentifier("pdf.layout")
            Toggle(isOn: $cropsMargins) { Text("Crop margins") }
                .toggleStyle(PDFToolToggleStyle(icon: .document, busy: isCropping))
                .accessibilityIdentifier("pdf.crop")
        }
    }

    /// The page the panel speaks for: the slider's target while dragging.
    private var shown: Int {
        guard let scrub else { return min(max(page, 0), max(pageCount - 1, 0)) }
        return min(max(Int(scrub.rounded()), 0), max(pageCount - 1, 0))
    }
}

/// The page slider between previous and next page buttons. The pages follow the knob while it
/// moves, since a PDF page is drawn as fast as it's asked for.
private struct PDFPageSlider: View {
    /// 0-based.
    let page: Int
    let count: Int
    @Binding var scrub: Double?
    let onJump: (Int) -> Void

    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            step(.previous, "Previous page", id: "pdf.previous", to: page - 1)
            Slider(value: value, in: 0...Double(max(count - 1, 1)), onEditingChanged: editingChanged)
                .tint(accent)
                .disabled(count < 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Page"))
                .accessibilityValue(Text("Page \(page + 1)"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: jump(to: page + 1)
                    case .decrement: jump(to: page - 1)
                    @unknown default: break
                    }
                }
            step(.next, "Next page", id: "pdf.next", to: page + 1)
        }
        .shioriHaptic(.selection, trigger: tick)
        .onChange(of: scrubbed) { _, target in
            if let target { jump(to: target) }
        }
    }

    private var value: Binding<Double> {
        Binding(get: { scrub ?? Double(page) }, set: { scrub = $0 })
    }

    private var scrubbed: Int? {
        scrub.map { Int($0.rounded()) }
    }

    private func editingChanged(_ editing: Bool) {
        if editing {
            if scrub == nil { scrub = Double(page) }
        } else if let released = scrub {
            scrub = nil
            jump(to: Int(released.rounded()))
        }
    }

    private func jump(to target: Int) {
        guard count > 0 else { return }
        let target = min(max(target, 0), count - 1)
        if target != page { onJump(target) }
    }

    /// Ticks per page in short PDFs, per percent in long ones, where a tick per page would buzz.
    private var tick: Int? {
        guard let scrub, count > 1 else { return nil }
        return count > 100 ? Int(scrub / Double(count - 1) * 100) : Int(scrub.rounded())
    }

    private func step(_ icon: ShioriIcon, _ label: LocalizedStringKey, id: String, to target: Int) -> some View {
        let enabled = target >= 0 && target < count
        return Button {
            jump(to: target)
        } label: {
            IconView(icon, size: 22)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(ChromePressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }
}

/// A tool in the panel, as the text reader draws its tools, plus an on state for toggles.
private struct PDFToolStyle: ButtonStyle {
    let icon: ShioriIcon
    var on = false
    var busy = false

    func makeBody(configuration: Configuration) -> some View {
        PDFToolFace(icon: icon, on: on, pressed: configuration.isPressed, busy: busy) { configuration.label }
    }
}

private struct PDFToolToggleStyle: ToggleStyle {
    let icon: ShioriIcon
    let busy: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(PDFToolStyle(icon: icon, on: configuration.isOn, busy: busy))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private struct PDFToolFace<Label: View>: View {
    let icon: ShioriIcon
    let on: Bool
    let pressed: Bool
    let busy: Bool
    @ViewBuilder let label: Label

    @Environment(\.motionReduced) private var reduced

    var body: some View {
        VStack(spacing: 3) {
            // Stacked, so the outgoing and incoming icons share one slot while they swap.
            ZStack {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Tokens.ink)
                        .transition(.opacity)
                } else {
                    IconView(icon, active: on || pressed, size: 24)
                        .id(icon)
                        .transition(reduced ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: 24, height: 24)
            label
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(.rect)
        .scaleEffect(pressed && !reduced ? 0.92 : 1)
        .opacity(pressed && reduced ? 0.6 : 1)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: pressed)
        .animation(Motion.animation(Motion.lens, reduced: reduced), value: icon)
        .animation(Motion.animation(Motion.lens, reduced: reduced), value: busy)
    }
}

private enum PDFChromeMetrics {
    static let round: CGFloat = 46
}

extension EnvironmentValues {
    /// True while the PDF chrome transitions in or out.
    @Entry fileprivate var pdfChromeOffstage = false
}

/// The chrome fades as a whole, and each part also travels from its own edge.
private struct PDFChromeTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .environment(\.pdfChromeOffstage, !phase.isIdentity)
    }
}

private struct PDFChromeSlide: ViewModifier {
    let edge: VerticalEdge

    @Environment(\.pdfChromeOffstage) private var offstage
    @Environment(\.motionReduced) private var reduced

    func body(content: Content) -> some View {
        let away = offstage && !reduced
        content
            .offset(y: away ? (edge == .top ? -24 : 40) : 0)
            .scaleEffect(away ? 0.96 : 1, anchor: edge == .top ? .top : .bottom)
    }
}
