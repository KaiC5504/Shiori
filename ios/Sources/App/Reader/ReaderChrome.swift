import SwiftUI
import UIKit

/// What the chrome shows about the place in the book.
struct ReaderChromeState: Equatable {
    var bookTitle: String
    var chapterTitle: String
    /// 0-based.
    var chapterIndex: Int
    var chapterCount: Int
}

/// The floating glass chrome (spec §7.7): a top bar and one bottom panel. It fills the reader
/// and brings its own transition: the bar drops in, the panel rises, both fade.
struct ReaderChrome: View {
    let state: ReaderChromeState
    let onBack: () -> Void
    /// A 0-based chapter, sent when the slider is released or a chapter button is tapped.
    let onJump: (Int) -> Void
    let onContents: () -> Void
    let onAppearance: () -> Void
    let onDayNight: () -> Void

    @Environment(AppModel.self) private var model: AppModel?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readerChapterTitle) private var titleOfChapter
    @Environment(\.displayScale) private var displayScale
    @State private var scrub: Double?
    /// The chapter just jumped to, held until the reader reports it so the knob doesn't snap back.
    @State private var pending: Int?
    @State private var jumps = 0
    @State private var insets = EdgeInsets()

    init(state: ReaderChromeState, onBack: @escaping () -> Void, onJump: @escaping (Int) -> Void,
         onContents: @escaping () -> Void, onAppearance: @escaping () -> Void,
         onDayNight: @escaping () -> Void) {
        self.state = state
        self.onBack = onBack
        self.onJump = onJump
        self.onContents = onContents
        self.onAppearance = onAppearance
        self.onDayNight = onDayNight
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                topBar
                    .modifier(ChromeSlide(edge: .top))
                Spacer(minLength: 0)
                panel
                    .modifier(ChromeSlide(edge: .bottom))
            }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
        // Glass and ink must match the paper (Milk stays light on a dark phone), whether or not
        // the reader forces the theme's scheme around the chrome.
        .transformEnvironment(\.colorScheme) { scheme in
            if let forced = theme?.colorScheme { scheme = forced }
        }
        .onChange(of: state.chapterIndex) { pending = nil }
        .task(id: pending) {
            // A jump the reader never lands (an empty chapter, a failed load) lets go eventually.
            guard pending != nil, (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            pending = nil
        }
        .shioriHaptic(.impact(weight: .light), trigger: jumps)
        .shioriHaptic(.selection, trigger: isNight)
        .transition(ChromeTransition())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                IconView(.back, size: 22)
                    .frame(width: ChromeMetrics.round, height: ChromeMetrics.round)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(paper.opacity(0.35)).interactive(), in: .circle)
            .accessibilityLabel(Text("Back"))
            Text(verbatim: state.bookTitle)
                .font(.headline)
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            // Balances the back button so the title stays centred; Listen takes this place later.
            Color.clear
                .frame(width: ChromeMetrics.round, height: ChromeMetrics.round)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, insets.top > 0 ? 0 : 10)
        .padding(.bottom, 10)
        .background {
            // The page scrolls under the title. Solid paper down to the bar's bottom edge keeps the
            // title and status bar legible on any theme; the short fade below hides the cut.
            VStack(spacing: 0) {
                paper
                LinearGradient(colors: [paper, paper.opacity(0)], startPoint: .top, endPoint: .bottom)
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
            ChapterSlider(chapter: resting, count: state.chapterCount, scrub: $scrub) { target in
                pending = target
                jumps += 1
                onJump(target)
            }
            Rectangle()
                .fill(Tokens.ink.opacity(0.12))
                .frame(height: 1 / displayScale)
                .padding(.top, 10)
                .padding(.bottom, 6)
            HStack(spacing: 0) {
                Button(action: onContents) { Text("Contents") }
                    .buttonStyle(ChromeToolStyle(icon: .contents))
                Button(action: onAppearance) { Text("Appearance") }
                    .buttonStyle(ChromeToolStyle(icon: .typography))
                    .accessibilityIdentifier("chrome.appearance")
                Button(action: onDayNight) { isNight ? Text("Day") : Text("Night") }
                    .buttonStyle(ChromeToolStyle(icon: isNight ? .sun : .moon))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background {
            // Swallows taps between the controls, so they don't reach the page and close the chrome.
            Color.clear.contentShape(shape).onTapGesture {}
        }
        .glassEffect(.regular.tint(paper.opacity(0.5)), in: shape)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, insets.bottom > 0 ? 4 : 16)
    }

    private var placeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: shownTitle ?? state.chapterTitle)
                .font(.caption)
                .foregroundStyle(Tokens.inkSecondary)
                .lineLimit(1)
                // Without a title for the target, the current one stays but no longer claims the place.
                .opacity(shownTitle == nil ? 0.45 : 1)
            Spacer(minLength: 0)
            Text(verbatim: counter)
                .font(.system(size: 12, design: .monospaced))
                .tracking(1)
                .foregroundStyle(scrub == nil ? Tokens.inkSecondary : Tokens.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .animation(.easeInOut(duration: 0.15), value: scrub == nil)
        .accessibilityElement(children: .combine)
    }

    private var theme: ReaderTheme? { model?.readerPreferences.theme }

    private var paper: Color { theme?.paper ?? Tokens.paper }

    private var isNight: Bool {
        if let theme { return theme == .night }
        return colorScheme == .dark
    }

    private var lastChapter: Int { max(state.chapterCount - 1, 0) }

    /// Where the knob rests when no finger is on it.
    private var resting: Int { min(max(pending ?? state.chapterIndex, 0), lastChapter) }

    /// The chapter the panel speaks for: the slider's target while dragging.
    private var shown: Int {
        guard let scrub else { return resting }
        return min(max(Int(scrub.rounded()), 0), lastChapter)
    }

    /// nil when the shown chapter isn't the current one and the reader gave no way to name it.
    private var shownTitle: String? {
        shown == state.chapterIndex ? state.chapterTitle : titleOfChapter?(shown)
    }

    private var counter: String {
        guard state.chapterCount > 0 else { return "" }
        let percent = Int(Double(shown) / Double(state.chapterCount) * 100)
        return "\(shown + 1) / \(state.chapterCount) · \(percent)%"
    }
}

extension EnvironmentValues {
    /// Names a 0-based chapter, so the chrome can show the slider's target by title while dragging.
    @Entry var readerChapterTitle: ((Int) -> String?)? = nil

    /// True while the chrome transitions in or out.
    @Entry fileprivate var readerChromeOffstage = false
}

private enum ChromeMetrics {
    static let round: CGFloat = 46
}

/// The chrome fades as a whole, and each part also travels from its own edge.
private struct ChromeTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .environment(\.readerChromeOffstage, !phase.isIdentity)
    }
}

private struct ChromeSlide: ViewModifier {
    let edge: VerticalEdge

    @Environment(\.readerChromeOffstage) private var offstage
    @Environment(\.motionReduced) private var reduced

    func body(content: Content) -> some View {
        let away = offstage && !reduced
        content
            .offset(y: away ? (edge == .top ? -24 : 40) : 0)
            .scaleEffect(away ? 0.96 : 1, anchor: edge == .top ? .top : .bottom)
    }
}

/// The slim info line at the bottom of the page (spec §7.7, option B): the chapter on the left,
/// the place in the book, the time and the battery on the right. It takes the reader's ink as
/// `.secondary`, and the reader sets its horizontal margins.
struct ReaderInfoFooter: View {
    let chapterTitle: String
    let chapterIndex: Int
    let chapterCount: Int
    let showsBattery: Bool

    /// 0...1; nil when the phone can't say (always, in the simulator).
    @State private var battery: Float?

    init(chapterTitle: String, chapterIndex: Int, chapterCount: Int, showsBattery: Bool) {
        self.chapterTitle = chapterTitle
        self.chapterIndex = chapterIndex
        self.chapterCount = chapterCount
        self.showsBattery = showsBattery
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: chapterTitle)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 0)
            TimelineView(.everyMinute) { context in
                HStack(spacing: 0) {
                    if chapterCount > 0 {
                        Text(verbatim: "\(chapterIndex + 1) / \(chapterCount) · ")
                    }
                    Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    if showsBattery, let battery {
                        Text(verbatim: " · ")
                        Text(Double(battery), format: .percent.precision(.fractionLength(0)))
                    }
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .tracking(1)
            .lineLimit(1)
            .fixedSize()
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .task(id: showsBattery) { await watchBattery() }
    }

    /// The level only reads while monitoring is on, which costs power, so it is on only while
    /// the footer shows it.
    private func watchBattery() async {
        let device = UIDevice.current
        guard showsBattery else {
            battery = nil
            return
        }
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = false }
        battery = Self.level(device)
        for await _ in NotificationCenter.default.notifications(named: UIDevice.batteryLevelDidChangeNotification) {
            battery = Self.level(device)
        }
    }

    private static func level(_ device: UIDevice) -> Float? {
        device.batteryLevel >= 0 ? device.batteryLevel : nil
    }
}
