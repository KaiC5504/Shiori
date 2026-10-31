import SwiftUI

/// The full-width floating bar (spec §5.1). A lens sits behind the selected lane: it springs
/// to a tapped lane, or follows a finger dragged along the bar and settles on the nearest lane.
struct ShioriTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // GestureState rather than State so a cancelled drag (a system gesture taking over) still
    // returns the lens to its lane.
    @GestureState private var dragX: CGFloat? = nil
    @State private var barWidth: CGFloat = 0
    @State private var iconBounces: [AppTab: Int] = [:]

    private let tabs = AppTab.allCases
    private let lensInset: CGFloat = 4

    init(selection: Binding<AppTab>) {
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                lane(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: BarMetrics.height)
        .background(alignment: .leading) { lens }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .contentShape(.capsule)
        .glassEffect(.regular.tint(Tokens.paper.opacity(0.35)).interactive(), in: .capsule)
        // High priority so a drag cancels the lane button under the finger; a tap never
        // travels the minimum distance, so it stays the button's.
        .highPriorityGesture(drag)
        .sensoryFeedback(.selection, trigger: targetTab)
        .onChange(of: selection) { _, tab in
            if !reduceMotion { iconBounces[tab, default: 0] += 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private func lane(_ tab: AppTab) -> some View {
        let highlighted = tab == targetTab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20))
                    .frame(height: 24)
                    .symbolEffect(.bounce, value: iconBounces[tab, default: 0])
                Text(tab.title)
                    .font(.system(size: 11, weight: highlighted ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(highlighted ? Tokens.ink : Tokens.inkSecondary)
            .animation(.easeInOut(duration: 0.2), value: highlighted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(tab == selection ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    // Solid, not glass: glass can't sample the bar's glass, and inside a shared container the
    // two shapes merge instead of reading as a lens.
    private var lens: some View {
        ZStack {
            if barWidth > 0 {
                Capsule()
                    .fill(Tokens.ink.opacity(0.1))
                    .overlay { Capsule().strokeBorder(Tokens.ink.opacity(0.08), lineWidth: 0.5) }
                    .frame(width: laneWidth - 2 * lensInset,
                           height: BarMetrics.height - 2 * lensInset)
                    .scaleEffect(dragX != nil && !reduceMotion ? 1.06 : 1)
                    .offset(x: lensCenter - laneWidth / 2 + lensInset)
                    // Under Reduce Motion a new selection swaps the lens for a fresh one, so it
                    // crossfades between lanes instead of sliding.
                    .id(reduceMotion ? Optional(selection) : nil)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(lensAnimation, value: selection)
        .animation(lensAnimation, value: dragX)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var lensAnimation: Animation? {
        switch (reduceMotion, dragX != nil) {
        case (false, false): .spring(duration: 0.35, bounce: 0.25)
        case (false, true): .interactiveSpring()
        case (true, false): .easeInOut(duration: 0.15)
        case (true, true): nil
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragX) { value, state, _ in state = value.location.x }
            .onEnded { value in selection = nearestTab(to: value.location.x) }
    }

    private var laneWidth: CGFloat { barWidth / CGFloat(tabs.count) }

    private var lensCenter: CGFloat {
        if let dragX { return clamped(dragX) }
        let index = tabs.firstIndex(of: selection) ?? 0
        return laneWidth * (CGFloat(index) + 0.5)
    }

    /// The lane the lens is on: the selection, or while dragging, the lane under the finger.
    private var targetTab: AppTab {
        dragX.map(nearestTab) ?? selection
    }

    private func clamped(_ x: CGFloat) -> CGFloat {
        min(max(x, laneWidth / 2), barWidth - laneWidth / 2)
    }

    private func nearestTab(to x: CGFloat) -> AppTab {
        guard laneWidth > 0 else { return selection }
        let index = Int(clamped(x) / laneWidth)
        return tabs[min(max(index, 0), tabs.count - 1)]
    }
}
