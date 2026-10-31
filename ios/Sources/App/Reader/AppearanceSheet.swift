import ShioriLibrary
import SwiftUI

/// The Aa sheet (spec §7.4, §7.5, §7.7). Size, font, line spacing and paper fit the medium
/// detent; pulling it up adds the rest of the typography. Every change goes straight into
/// `model.readerPreferences`, so the page behind re-lays out as it changes.
struct AppearanceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @State private var showsFonts: Bool
    @State private var detent: PresentationDetent

    init() {
        #if DEBUG
        let page = DemoLaunch.appearancePage
        _showsFonts = State(initialValue: page == "fonts")
        _detent = State(initialValue: page == "more" ? .large : .medium)
        #else
        _showsFonts = State(initialValue: false)
        _detent = State(initialValue: .medium)
        #endif
    }

    var body: some View {
        ZStack {
            if showsFonts {
                FontList { setShowsFonts(false) }
                    .transition(page(from: 1))
            } else {
                AppearanceForm(preferences: model.readerPreferences) { setShowsFonts(true) }
                    .transition(page(from: -1))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .task { await FontDownloads.shared.activate(model.readerPreferences.typography.fontFamily) }
    }

    private func setShowsFonts(_ shows: Bool) {
        withAnimation(Motion.animation(Motion.reveal, reduced: reduced)) { showsFonts = shows }
    }

    private func page(from side: CGFloat) -> AnyTransition {
        reduced ? .opacity : .offset(x: side * 48).combined(with: .opacity)
    }
}

private struct AppearanceForm: View {
    @Bindable var preferences: ReaderPreferences
    let onFonts: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionReduced) private var reduced
    @Namespace private var ring
    @State private var customSpacing: Bool
    @State private var confirmsReset = false
    /// Where the gap slider returns when "As in the book" is turned off.
    @State private var lastGap: Double

    private static let sizes: ClosedRange<Double> = 10...27
    private static let margins: ClosedRange<Double> = 0...80

    init(preferences: ReaderPreferences, onFonts: @escaping () -> Void) {
        _preferences = Bindable(preferences)
        self.onFonts = onFonts
        _customSpacing = State(initialValue: LineSpacing(preferences.typography.lineHeight) == .custom)
        _lastGap = State(initialValue: preferences.typography.paragraphGap
                         ?? ReaderTypography.default.paragraphGap ?? 0)
    }

    private var typography: ReaderTypography { preferences.typography }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    textSection.staggeredReveal(0)
                    spacingSection.staggeredReveal(1)
                    paperSection.staggeredReveal(2)
                    typeSection.staggeredReveal(3)
                    paragraphSection.staggeredReveal(4)
                    marginSection.staggeredReveal(5)
                    pageSection.staggeredReveal(6)
                    resetButton.staggeredReveal(7)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .confirmationDialog("Reset to defaults", isPresented: $confirmsReset, titleVisibility: .hidden) {
            Button("Reset to defaults", role: .destructive, action: reset)
        }
    }

    private var header: some View {
        HStack {
            Text("Appearance")
                .font(.title2.bold())
                .foregroundStyle(Tokens.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                dismiss()
            } label: {
                IconView(.close, size: 18)
                    .frame(width: 36, height: 36)
                    .background(Tokens.surface, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("aa.close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "TEXT", title: "Text size")
            HStack(spacing: 8) {
                stepButton("A−", glyphSize: 15, label: "Smaller text", id: "aa.smaller", by: -1)
                Text(verbatim: points(typography.size))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Tokens.ink)
                    .contentTransition(.numericText(value: typography.size))
                    .animation(Motion.animation(Motion.press, reduced: reduced), value: typography.size)
                    .lineLimit(1)
                    .frame(minWidth: 56, maxWidth: .infinity, minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Text size"))
                    .accessibilityValue(Text(verbatim: points(typography.size)))
                    .accessibilityAdjustableAction { direction in
                        setSize(typography.size + (direction == .increment ? 1 : -1))
                    }
                stepButton("A+", glyphSize: 19, label: "Larger text", id: "aa.larger", by: 1)
                fontChip
                    .layoutPriority(1)
            }
            .shioriHaptic(.selection, trigger: typography.size)
        }
    }

    private func stepButton(_ glyph: String, glyphSize: CGFloat, label: LocalizedStringKey, id: String,
                            by delta: Double) -> some View {
        let next = typography.size + delta
        let enabled = Self.sizes.contains(next)
        return Button {
            setSize(next)
        } label: {
            Text(verbatim: glyph)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(Tokens.ink)
                .frame(width: 48, height: 44)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
                .contentShape(.rect)
        }
        .buttonStyle(AppearancePressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }

    private var fontChip: some View {
        Button(action: onFonts) {
            HStack(spacing: 6) {
                FontCatalog.name(typography.fontFamily)
                    .font(FontCatalog.face(typography.fontFamily, size: 16))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(1)
                IconView(.forward, size: 14)
                    .opacity(0.6)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(minHeight: 44)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(AppearancePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Font"))
        .accessibilityValue(FontCatalog.name(typography.fontFamily))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("aa.font")
    }

    private var spacingSection: some View {
        let showsSlider = customSpacing || LineSpacing(typography.lineHeight) == .custom
        return VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "SPACING", title: "Line spacing")
            AppearanceSegments(LineSpacing.allCases, selection: spacingChoice) { Text($0.title) }
            if showsSlider {
                ArchiveCard {
                    AppearanceSlider("Line height", value: rounded(\.lineHeight), in: 1.3...2.2, step: 0.05,
                                     valueText: Text(verbatim: multiple(typography.lineHeight)))
                }
                .transition(reveal)
            }
        }
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: showsSlider)
    }

    private var spacingChoice: Binding<LineSpacing> {
        Binding(
            get: { customSpacing ? .custom : LineSpacing(typography.lineHeight) },
            set: { choice in
                customSpacing = choice == .custom
                if let value = choice.lineHeight { set(\.lineHeight, value) }
            })
    }

    private var paperSection: some View {
        let night = preferences.theme == .night
        return VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "PAPER", title: "Paper")
            HStack(alignment: .top, spacing: 8) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    AppearanceSwatch(theme: theme,
                                     ink: ReaderTheme.night.ink.opacity(preferences.nightTextBrightness),
                                     selected: preferences.theme == theme, ring: ring) {
                        choose(theme)
                    }
                }
            }
            .padding(.top, 4)
            .animation(Motion.animation(Motion.lens, reduced: reduced), value: preferences.theme)
            .shioriHaptic(.selection, trigger: preferences.theme)
            if night {
                ArchiveCard {
                    AppearanceSlider("Text brightness", value: brightness, in: 0.35...1, step: 0.05,
                                     valueText: Text(preferences.nightTextBrightness,
                                                     format: .percent.precision(.fractionLength(0))))
                }
                .padding(.top, 4)
                .transition(reveal)
            }
        }
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: night)
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "TYPE", title: "Weight and spacing")
            AppearanceSegments(FontWeightChoice.allCases, selection: binding(\.weight)) { weight in
                Text(weight.title).fontWeight(weight.fontWeight)
            }
            ArchiveCard {
                AppearanceSlider("Letter spacing", value: rounded(\.letterSpacing), in: -0.5...3, step: 0.1,
                                 valueText: Text(verbatim: decimal(typography.letterSpacing, digits: 1)))
            }
        }
    }

    private var paragraphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "PARAGRAPHS", title: "Paragraphs")
            ArchiveCard {
                VStack(spacing: 0) {
                    AppearanceSlider("Paragraph gap", value: gap, in: 0...32, step: 1,
                                     valueText: Text(verbatim: points(typography.paragraphGap ?? lastGap)))
                        .disabled(typography.paragraphGap == nil)
                    AppearanceHairline().padding(.leading, 16)
                    SettingsToggleRow("As in the book", isOn: asInBook)
                    AppearanceHairline().padding(.leading, 16)
                    SettingsToggleRow("First-line indent", isOn: binding(\.firstLineIndent))
                    AppearanceHairline().padding(.leading, 16)
                    SettingsToggleRow("Justify", isOn: binding(\.justify))
                }
            }
            .animation(Motion.animation(Motion.press, reduced: reduced), value: typography.paragraphGap == nil)
        }
    }

    private var marginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "MARGINS", title: "Margins")
            ArchiveCard {
                VStack(spacing: 0) {
                    SettingsToggleRow("Same on all sides", isOn: linked)
                    if typography.marginsLinked {
                        AppearanceHairline().padding(.leading, 16)
                        AppearanceSlider("All sides", value: allSides, in: Self.margins, step: 1,
                                         valueText: Text(verbatim: points(typography.margins.left)))
                            .transition(reveal)
                    } else {
                        ForEach(MarginSide.allCases, id: \.self) { side in
                            AppearanceHairline().padding(.leading, 16)
                            AppearanceSlider(side.title, value: rounded(side.keyPath), in: Self.margins, step: 1,
                                             valueText: Text(verbatim: points(typography[keyPath: side.keyPath])))
                        }
                        .transition(reveal)
                    }
                }
            }
            .animation(Motion.animation(Motion.reveal, reduced: reduced), value: typography.marginsLinked)
        }
    }

    private var pageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppearanceLabel(code: "PAGE", title: "Page")
            ArchiveCard {
                SettingsToggleRow("Info footer",
                                  footnote: Text("The chapter, page, time and battery in one line under the text."),
                                  isOn: $preferences.showsInfoFooter)
            }
        }
    }

    private var resetButton: some View {
        let isDefault = typography == .default
        return Button {
            confirmsReset = true
        } label: {
            Text("Reset to defaults")
                .foregroundStyle(Tokens.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
                .contentShape(.rect)
        }
        .buttonStyle(AppearancePressStyle())
        .disabled(isDefault)
        .opacity(isDefault ? 0.45 : 1)
        .padding(.top, 4)
        .accessibilityIdentifier("aa.reset")
    }

    private var reveal: AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private func setSize(_ size: Double) {
        set(\.size, min(max(size, Self.sizes.lowerBound), Self.sizes.upperBound))
    }

    private func choose(_ theme: ReaderTheme) {
        guard preferences.theme != theme else { return }
        // Day/Night returns to whichever paper was showing when Night was picked here.
        if theme == .night { preferences.dayTheme = preferences.theme }
        preferences.theme = theme
    }

    private func reset() {
        preferences.typography = .default
        customSpacing = false
        lastGap = ReaderTypography.default.paragraphGap ?? 0
    }

    /// Writes only real changes: a slider resends its value on every drag event, and each
    /// write re-lays out the page.
    private func set<Value: Equatable>(_ keyPath: WritableKeyPath<ReaderTypography, Value>, _ value: Value) {
        guard preferences.typography[keyPath: keyPath] != value else { return }
        preferences.typography[keyPath: keyPath] = value
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<ReaderTypography, Value>) -> Binding<Value> {
        Binding(get: { preferences.typography[keyPath: keyPath] }, set: { set(keyPath, $0) })
    }

    /// Slider steps are sums of binary fractions; rounding keeps 1.7 from arriving as 1.7000000000000002.
    private func rounded(_ keyPath: WritableKeyPath<ReaderTypography, Double>) -> Binding<Double> {
        Binding(get: { preferences.typography[keyPath: keyPath] },
                set: { set(keyPath, ($0 * 100).rounded() / 100) })
    }

    private var brightness: Binding<Double> {
        Binding(get: { preferences.nightTextBrightness },
                set: { value in
                    let rounded = (value * 100).rounded() / 100
                    if preferences.nightTextBrightness != rounded { preferences.nightTextBrightness = rounded }
                })
    }

    private var gap: Binding<Double> {
        Binding(get: { typography.paragraphGap ?? lastGap },
                set: { value in
                    lastGap = value.rounded()
                    set(\.paragraphGap, lastGap)
                })
    }

    private var asInBook: Binding<Bool> {
        Binding(get: { typography.paragraphGap == nil },
                set: { set(\.paragraphGap, $0 ? nil : lastGap) })
    }

    private var linked: Binding<Bool> {
        Binding(get: { typography.marginsLinked },
                set: { isOn in
                    var next = preferences.typography
                    next.marginsLinked = isOn
                    // Linked margins all follow the left one; matching them now means
                    // unlinking later starts from what the page showed.
                    if isOn { next.margins = Self.all(next.margins.left) }
                    if next != preferences.typography { preferences.typography = next }
                })
    }

    private var allSides: Binding<Double> {
        Binding(get: { typography.margins.left },
                set: { set(\.margins, Self.all($0.rounded())) })
    }

    private static func all(_ value: Double) -> Margins {
        Margins(left: value, right: value, top: value, bottom: value)
    }

    private func points(_ value: Double) -> String {
        "\(Int(value.rounded())) pt"
    }

    private func decimal(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    private func multiple(_ value: Double) -> String {
        decimal(value, digits: 2) + "×"
    }
}

private enum LineSpacing: Hashable, CaseIterable {
    case compact, standard, loose, custom

    init(_ lineHeight: Double) {
        self = Self.allCases.first { $0.lineHeight.map { abs($0 - lineHeight) < 0.001 } ?? false } ?? .custom
    }

    var lineHeight: Double? {
        switch self {
        case .compact: 1.4
        case .standard: 1.7
        case .loose: 2.0
        case .custom: nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .loose: "Loose"
        case .custom: "Custom"
        }
    }
}

private enum MarginSide: CaseIterable {
    case left, right, top, bottom

    var keyPath: WritableKeyPath<ReaderTypography, Double> {
        switch self {
        case .left: \.margins.left
        case .right: \.margins.right
        case .top: \.margins.top
        case .bottom: \.margins.bottom
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}

private extension FontWeightChoice {
    var title: LocalizedStringKey {
        switch self {
        case .regular: "Regular"
        case .medium: "Medium"
        case .bold: "Bold"
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
    }
}

#if DEBUG
extension DemoLaunch {
    /// "more" opens the Aa sheet at its large detent, "fonts" on the font list.
    static var appearancePage: String? { UserDefaults.standard.string(forKey: "DemoAppearancePage") }
}
#endif
