import SwiftUI

/// PAGE TURN in the Aa sheet (spec §7.7, item 4): Scroll, Paragraph relay or Curl as little
/// pages that play their turn when picked, and relay's speed. Paper turn stays out until M9.
struct PageTurnSection: View {
    @Bindable var preferences: ReaderPreferences

    @Environment(\.motionReduced) private var reduced
    @Namespace private var ring

    init(preferences: ReaderPreferences) {
        _preferences = Bindable(preferences)
    }

    var body: some View {
        let showsSpeed = choice == .relay
        VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "TURN", title: "Page turn")
            HStack(alignment: .top, spacing: 8) {
                ForEach(PageTurnChoice.allCases, id: \.self) { option in
                    PageTurnCard(choice: option, selected: choice == option, theme: preferences.theme,
                                 speed: preferences.speed, ring: ring) {
                        choose(option)
                    }
                }
            }
            .padding(.top, 4)
            .animation(Motion.animation(Motion.lens, reduced: reduced), value: choice)
            .shioriHaptic(.selection, trigger: choice)
            if showsSpeed {
                HStack(spacing: 12) {
                    Text("Speed")
                        .font(.subheadline)
                        .foregroundStyle(Tokens.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                    AppearanceSegments(TurnSpeed.allCases, selection: $preferences.speed) { Text($0.title) }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Speed"))
                }
                .padding(.top, 4)
                .transition(reduced ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: showsSpeed)
    }

    private var choice: PageTurnChoice {
        guard preferences.layout == .paged else { return .scroll }
        return preferences.effect == .curl ? .curl : .relay
    }

    /// Writes only real changes: each one re-lays out the page behind the sheet.
    private func choose(_ option: PageTurnChoice) {
        let effect: PageTurnEffect? = switch option {
        case .scroll: nil
        case .relay: .relay
        case .curl: .curl
        }
        if let effect, preferences.effect != effect { preferences.effect = effect }
        let layout: ReaderLayout = option == .scroll ? .scroll : .paged
        if preferences.layout != layout { preferences.layout = layout }
    }
}

private enum PageTurnChoice: String, CaseIterable {
    case scroll, relay, curl

    var title: LocalizedStringKey {
        switch self {
        case .scroll: "Scroll"
        case .relay: "Paragraph relay"
        case .curl: "Curl"
        }
    }
}

/// A little page of the reader's paper showing its turn, ringed like the paper swatches when
/// chosen. Picking it plays the turn once; the relay card replays at each new speed.
private struct PageTurnCard: View {
    let choice: PageTurnChoice
    let selected: Bool
    let theme: ReaderTheme
    let speed: TurnSpeed
    let ring: Namespace.ID
    let action: () -> Void

    @Environment(\.motionReduced) private var reduced
    @State private var plays = 0

    var body: some View {
        Button {
            play()
            action()
        } label: {
            VStack(spacing: 6) {
                page
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        if selected {
                            selectionRing
                        }
                    }
                Text(choice.title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Tokens.ink : Tokens.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(AppearancePressStyle())
        .onChange(of: speed) {
            if choice == .relay, selected { play() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(choice.title))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("aa.turn.\(choice.rawValue)")
    }

    private var page: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return shape
            .fill(theme.paper)
            .overlay {
                KeyframeAnimator(initialValue: 0.0, trigger: plays) { phase in
                    PageTurnGlyph(choice: choice, phase: phase, speed: speed, theme: theme)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(1.0, duration: duration)
                        MoveKeyframe(0.0)
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Tokens.line, lineWidth: 1) }
    }

    private var duration: Double {
        switch choice {
        case .scroll: 0.9
        case .relay: PageTurnGlyph.relayTimeline(speed: speed, width: 1).total
        case .curl: 0.8
        }
    }

    private func play() {
        if !reduced { plays += 1 }
    }

    @ViewBuilder
    private var selectionRing: some View {
        let shape = RoundedRectangle(cornerRadius: 11).strokeBorder(Tokens.ink, lineWidth: 2).padding(-4)
        if reduced {
            shape.transition(.opacity)
        } else {
            shape.matchedGeometryEffect(id: "ring", in: ring)
        }
    }
}

/// Lines of text on the card's page, moving as the effect does. `phase` runs from 0 to 1 and
/// both ends look the same, so the animation can rest at either.
private struct PageTurnGlyph: View {
    let choice: PageTurnChoice
    let phase: Double
    let speed: TurnSpeed
    let theme: ReaderTheme

    /// Three paragraphs, as the reader's own relay would time them.
    static func relayTimeline(speed: TurnSpeed, width: CGFloat) -> RelayTimeline {
        RelayTimeline(motion: .relay(speed), outgoing: 3, incoming: 3, travel: width * 0.6)
    }

    var body: some View {
        Canvas { context, size in
            // The page's margins; relay paragraphs travel out across them to the card's edge.
            let inner = CGSize(width: max(size.width - 24, 0), height: max(size.height - 20, 0))
            context.translateBy(x: 12, y: 10)
            switch choice {
            case .scroll:
                context.clip(to: Path(CGRect(origin: .zero, size: inner)))
                drawScroll(in: &context, size: inner)
            case .relay:
                drawRelay(in: &context, size: inner)
            case .curl:
                drawCurl(in: &context, size: inner)
            }
        }
        .accessibilityHidden(true)
    }

    private static let widths: [CGFloat] = [1, 0.82, 1, 0.55]
    private static let pitch: CGFloat = 7
    private static let thickness: CGFloat = 2.5

    private var ink: Color { theme.inkSecondary.opacity(0.7) }

    private func line(_ context: inout GraphicsContext, x: CGFloat, y: CGFloat, width: CGFloat, opacity: Double = 1) {
        guard width > 0, opacity > 0 else { return }
        let rect = CGRect(x: x, y: y, width: width, height: Self.thickness)
        context.fill(Path(roundedRect: rect, cornerRadius: Self.thickness / 2), with: .color(ink.opacity(opacity)))
    }

    /// The lines rise by a whole run of the width pattern, so the last frame matches the first.
    private func drawScroll(in context: inout GraphicsContext, size: CGSize) {
        let eased = phase * phase * (3 - 2 * phase)
        let shift = eased * Self.pitch * CGFloat(Self.widths.count)
        let count = Int(size.height / Self.pitch) + Self.widths.count + 1
        for row in 0..<count {
            let y = CGFloat(row) * Self.pitch - shift
            guard y > -Self.thickness, y < size.height else { continue }
            line(&context, x: 0, y: y, width: size.width * Self.widths[row % Self.widths.count])
        }
    }

    /// Three two-line paragraphs leave to the left one after another and arrive from the right.
    private func drawRelay(in context: inout GraphicsContext, size: CGSize) {
        let timeline = Self.relayTimeline(speed: speed, width: size.width)
        let time = phase * timeline.total
        let block = size.height / 3
        for index in 0..<3 {
            let y = CGFloat(index) * block
            let gone = timeline.outgoing(index, at: time)
            let arrived = timeline.incoming(index, at: time)
            paragraph(&context, y: y, width: size.width, dx: -timeline.travel * gone,
                      opacity: timeline.outgoingOpacity(gone))
            paragraph(&context, y: y, width: size.width, dx: timeline.travel * (1 - arrived), opacity: arrived)
        }
    }

    private func paragraph(_ context: inout GraphicsContext, y: CGFloat, width: CGFloat, dx: CGFloat,
                           opacity: Double) {
        line(&context, x: dx + width * 0.12, y: y, width: width * 0.88, opacity: opacity)
        line(&context, x: dx, y: y + Self.pitch, width: width * 0.6, opacity: opacity)
    }

    /// The lower corner lifts and falls back, with the page's underside showing in the fold.
    private func drawCurl(in context: inout GraphicsContext, size: CGSize) {
        let lift = sin(.pi * phase)
        let fold = 6 + 16 * lift
        let corner = CGPoint(x: size.width, y: size.height)
        var page = context
        var cut = Path()
        cut.move(to: .zero)
        cut.addLine(to: CGPoint(x: size.width, y: 0))
        cut.addLine(to: CGPoint(x: size.width, y: size.height - fold))
        cut.addLine(to: CGPoint(x: size.width - fold, y: size.height))
        cut.addLine(to: CGPoint(x: 0, y: size.height))
        cut.closeSubpath()
        page.clip(to: cut)
        var row = 0
        var y: CGFloat = 0
        while y < size.height {
            line(&page, x: 0, y: y, width: size.width * Self.widths[row % Self.widths.count])
            row += 1
            y += Self.pitch
        }
        var flap = Path()
        flap.move(to: CGPoint(x: corner.x, y: corner.y - fold))
        flap.addLine(to: CGPoint(x: corner.x - fold, y: corner.y))
        flap.addLine(to: CGPoint(x: corner.x - fold, y: corner.y - fold))
        flap.closeSubpath()
        context.fill(flap, with: .color(theme.inkSecondary.opacity(0.18)))
        context.stroke(flap, with: .color(theme.inkSecondary.opacity(0.45)), lineWidth: 0.75)
    }
}

private extension TurnSpeed {
    var title: LocalizedStringKey {
        switch self {
        case .gentle: "Gentle"
        case .standard: "Standard"
        case .brisk: "Brisk"
        }
    }
}
