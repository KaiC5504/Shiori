import os
import PhotosUI
// PhotosPicker's cross-import overlay, named because tools/check-app.sh doesn't load overlays.
import _PhotosUI_SwiftUI
import ShioriCore
import SwiftUI
import UIKit

/// Settings → Appearance → Accent (spec §4.2): the ten preset pairs, then a custom colour
/// from the system picker, a hex code or a photo. Every choice applies at once.
struct AccentSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced

    @State private var hex = ""
    /// The picker's own colour, kept apart from the contrast-fixed accent so the system
    /// picker doesn't jump while it's being dragged.
    @State private var picked: Color?
    @State private var photo: PhotosPickerItem?
    @State private var photoColours: [UInt32] = []
    @State private var readingPhoto = false
    @State private var photoFailed = false
    @State private var taps = 0
    @FocusState private var typingHex: Bool

    private static let log = Logger(subsystem: "com.kaichuan.shiori", category: "accent")

    init() {}

    private var accent: AccentChoice { model.settings.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(code: "03 / APPEARANCE / ACCENT", title: "Accent")
                AccentSpecimen(choice: accent)
                    .staggeredReveal(2)
                presets
                    .staggeredReveal(3)
                custom
                    .staggeredReveal(4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .shioriHaptic(.selection, trigger: taps)
        .onChange(of: photo) { _, item in
            Task { await readPhoto(item) }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(code: "ACCENT / PRESETS", title: "Presets")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 18) {
                ForEach(Array(AccentPreset.allCases.enumerated()), id: \.element) { index, preset in
                    PresetSwatch(number: index + 1, preset: preset, selected: accent == .preset(preset)) {
                        hex = ""
                        picked = nil
                        choose(.preset(preset))
                        taps += 1
                    }
                }
            }
        }
    }

    private var custom: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(code: "ACCENT / CUSTOM", title: "Custom")
            ArchiveCard {
                VStack(spacing: 0) {
                    hexRow
                    Hairline()
                    photoRow
                    if !photoColours.isEmpty {
                        Hairline()
                        photoSwatches
                    }
                    if photoFailed {
                        Hairline()
                        Text("Couldn't read that photo.")
                            .font(.footnote)
                            .foregroundStyle(Tokens.inkSecondary)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }
            if isAdjusted {
                adjustedNote
                    .transition(reduced ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: isAdjusted)
    }

    private var hexRow: some View {
        HStack(spacing: 8) {
            Text(verbatim: "#")
                .font(.body.monospaced())
                .foregroundStyle(Tokens.inkSecondary)
            TextField("Hex colour", text: $hex)
                .font(.body.monospaced())
                .foregroundStyle(Tokens.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($typingHex)
                .onChange(of: hex) { _, text in hexChanged(text) }
                .onSubmit(submitHex)
            ColorPicker(selection: pickerSelection, supportsOpacity: false) {
                Text("Custom")
            }
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var photoRow: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            HStack(spacing: 12) {
                IconView(.image, size: 22)
                Text("Pick from a photo")
                    .foregroundStyle(Tokens.ink)
                Spacer(minLength: 8)
                if readingPhoto {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(readingPhoto)
    }

    private var photoSwatches: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(photoColours.enumerated()), id: \.element) { index, rgb in
                let selected = isCurrent(rgb)
                Button {
                    hex = String(HexColour.string(rgb).dropFirst())
                    picked = Self.swatch(rgb)
                    applyCustom(rgb)
                    taps += 1
                } label: {
                    VStack(spacing: 6) {
                        ColourDot(colour: Self.swatch(rgb), selected: selected)
                        Text(verbatim: HexColour.string(rgb))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(selected ? Tokens.ink : Tokens.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .staggeredReveal(index)
                .accessibilityLabel(Text(verbatim: HexColour.string(rgb)))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private var adjustedNote: some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(.info, size: 18)
            Text("Adjusted for contrast: a darker version in light mode and a lighter one in dark mode, so text stays readable.")
                .font(.footnote)
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var pickerSelection: Binding<Color> {
        Binding(
            get: { picked ?? Self.swatch(currentLight) },
            set: { colour in
                picked = colour
                let rgb = Self.rgb(of: UIColor(colour))
                hex = String(HexColour.string(rgb).dropFirst())
                applyCustom(rgb)
            })
    }

    private var currentLight: UInt32 {
        switch accent {
        case .preset(let preset): preset.light
        case .custom(let light, _, _): light
        }
    }

    private var isAdjusted: Bool {
        if case .custom(_, _, let adjusted) = accent { return adjusted }
        return false
    }

    private func hexChanged(_ text: String) {
        let digits = String(text.uppercased().filter(\.isHexDigit).prefix(6))
        guard digits == text else {
            hex = digits
            return
        }
        guard digits.count == 6, let rgb = HexColour.parse(digits) else { return }
        if typingHex { picked = Self.swatch(rgb) }
        applyCustom(rgb)
    }

    private func submitHex() {
        if hex.count == 3, let rgb = HexColour.parse(hex) {
            hex = String(HexColour.string(rgb).dropFirst())
        }
    }

    private func readPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        readingPhoto = true
        var data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            Self.log.error("loading the photo failed: \(error)")
        }
        let colours = await PhotoAccent.dominantColours(in: data)
        readingPhoto = false
        withAnimation(Motion.animation(Motion.reveal, reduced: reduced)) {
            photoColours = colours
            photoFailed = colours.isEmpty
        }
    }

    private func isCurrent(_ rgb: UInt32) -> Bool {
        let fix = Self.fixed(rgb)
        return accent == .custom(light: fix.light, dark: fix.dark, adjusted: fix.adjusted)
    }

    private func applyCustom(_ rgb: UInt32) {
        let fix = Self.fixed(rgb)
        choose(.custom(light: fix.light, dark: fix.dark, adjusted: fix.adjusted))
    }

    private func choose(_ choice: AccentChoice) {
        guard model.settings.accent != choice else { return }
        withAnimation(Motion.animation(Motion.press, reduced: reduced)) {
            model.settings.accent = choice
        }
    }

    private static func fixed(_ rgb: UInt32) -> (light: UInt32, dark: UInt32, adjusted: Bool) {
        AccentContrast.fixed(accent: rgb, paperLight: paperLight, paperDark: paperDark)
    }

    // Read off the token, so the contrast check follows any retune of the paper.
    private static let paperLight = rgb(of: UIColor(Tokens.paper)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
    private static let paperDark = rgb(of: UIColor(Tokens.paper)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))

    static func swatch(_ rgb: UInt32) -> Color {
        Tokens.color(light: rgb, dark: rgb)
    }

    /// Clamped to sRGB: the picker can hand back Display P3 colours outside it.
    private static func rgb(of colour: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        _ = colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

/// The current accent on both papers, so its light and dark halves can be judged together.
private struct AccentSpecimen: View {
    let choice: AccentChoice

    var body: some View {
        ArchiveCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.title3.bold())
                        .foregroundStyle(Tokens.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: code)
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Tokens.inkSecondary)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 10) {
                    SpecimenPane(choice: choice, label: "Light", rgb: pair.light)
                        .environment(\.colorScheme, .light)
                    SpecimenPane(choice: choice, label: "Dark", rgb: pair.dark)
                        .environment(\.colorScheme, .dark)
                }
            }
            .padding(16)
        }
    }

    private var name: LocalizedStringResource {
        switch choice {
        case .preset(let preset): preset.title
        case .custom: "Custom"
        }
    }

    private var code: String {
        switch choice {
        case .preset(let preset):
            let number = (AccentPreset.allCases.firstIndex(of: preset) ?? 0) + 1
            return number < 10 ? "NO.00\(number)" : "NO.0\(number)"
        case .custom:
            return "CUSTOM"
        }
    }

    private var pair: (light: UInt32, dark: UInt32) {
        switch choice {
        case .preset(let preset): (preset.light, preset.dark)
        case .custom(let light, let dark, _): (light, dark)
        }
    }
}

/// One paper of the specimen: the accent as text, a toggle and a progress hairline.
private struct SpecimenPane: View {
    let choice: AccentChoice
    let label: LocalizedStringResource
    let rgb: UInt32

    var body: some View {
        let accent = Tokens.accent(choice)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Tokens.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Toggle(isOn: .constant(true)) { EmptyView() }
                    .labelsHidden()
                    .tint(accent)
                    .allowsHitTesting(false)
            }
            Text(verbatim: "Aa")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(accent)
            Capsule()
                .fill(Tokens.line)
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(accent)
                        .scaleEffect(x: 0.62, anchor: .leading)
                }
            Text(verbatim: HexColour.string(rgb))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Tokens.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.paper, in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.line, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

private struct PresetSwatch: View {
    let number: Int
    let preset: AccentPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                PairChip(light: preset.light, dark: preset.dark, selected: selected)
                    .frame(height: 60)
                VStack(spacing: 2) {
                    Text(verbatim: number < 10 ? "0\(number)" : "\(number)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Tokens.inkSecondary)
                    Text(preset.title)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Tokens.ink : Tokens.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(preset.title))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A preset's light colour with its dark partner folded across the lower corner.
private struct PairChip: View {
    let light: UInt32
    let dark: UInt32
    let selected: Bool
    @Environment(\.motionReduced) private var reduced

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        shape
            .fill(AccentSettingsView.swatch(light))
            .overlay { LowerTriangle().fill(AccentSettingsView.swatch(dark)) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Tokens.line, lineWidth: 1) }
            .padding(4)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Tokens.ink, lineWidth: 1.5)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected || reduced ? 1 : 1.08)
            }
            .animation(Motion.animation(Motion.lens, reduced: reduced), value: selected)
    }
}

private struct LowerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct ColourDot: View {
    let colour: Color
    let selected: Bool
    @Environment(\.motionReduced) private var reduced

    var body: some View {
        Circle()
            .fill(colour)
            .overlay { Circle().strokeBorder(Tokens.line, lineWidth: 1) }
            .frame(width: 36, height: 36)
            .padding(4)
            .overlay {
                Circle()
                    .strokeBorder(Tokens.ink, lineWidth: 1.5)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected || reduced ? 1 : 1.12)
            }
            .animation(Motion.animation(Motion.lens, reduced: reduced), value: selected)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

private struct PressScaleStyle: ButtonStyle {
    @Environment(\.motionReduced) private var reduced

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? 0.94 : 1)
            .opacity(configuration.isPressed && reduced ? 0.7 : 1)
            .animation(Motion.animation(Motion.press, reduced: reduced), value: configuration.isPressed)
    }
}
