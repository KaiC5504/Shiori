import CoreText
import ShioriLibrary
import SwiftUI

/// Apple's downloadable Simplified Chinese families. `family` is the non-localised family
/// name, which is what `ReaderTypography.fontFamily` stores.
enum FontCatalog {
    struct Entry: Identifiable {
        let family: String
        let name: LocalizedStringResource
        var id: String { family }
    }

    static let apple: [Entry] = [
        Entry(family: "Songti SC", name: "Songti SC"),
        Entry(family: "Kaiti SC", name: "Kaiti SC"),
        Entry(family: "Yuanti SC", name: "Yuanti SC"),
        Entry(family: "Libian SC", name: "Libian SC"),
        Entry(family: "Weibei SC", name: "Weibei SC"),
        Entry(family: "Hannotate SC", name: "Hannotate SC"),
        Entry(family: "Wawati SC", name: "Wawati SC"),
        Entry(family: "Xingkai SC", name: "Xingkai SC"),
        Entry(family: "HanziPen SC", name: "HanziPen SC"),
        Entry(family: "Baoli SC", name: "Baoli SC"),
        Entry(family: "Lantinghei SC", name: "Lantinghei SC"),
        Entry(family: "Yuppy SC", name: "Yuppy SC"),
    ]

    static func name(_ family: String?) -> Text {
        guard let family else { return Text("System font") }
        if let entry = apple.first(where: { $0.family == family }) { return Text(entry.name) }
        return Text(verbatim: family)
    }

    /// The family's own face once it's on the phone, else the system font.
    @MainActor static func face(_ family: String?, size: CGFloat) -> Font {
        guard let family, FontDownloads.shared.isAvailable(family) else { return .system(size: size) }
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute as String: family] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

/// The font picker inside the Aa sheet: the system font, then Apple's downloadable Chinese
/// fonts, each drawn in its own face once it's on the phone. Tapping one that isn't downloads
/// it with progress, then selects it.
struct FontList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    private let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    var body: some View {
        let downloads = FontDownloads.shared
        let selected = model.readerPreferences.typography.fontFamily
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ArchiveCard {
                        FontRow(name: FontCatalog.name(nil), face: .system(size: 19), state: selected == nil ? .selected : .ready) {
                            choose(nil)
                        }
                    }
                    .staggeredReveal(0)
                    AppearanceLabel(code: "APPLE", title: "Apple fonts")
                        .padding(.top, 12)
                        .staggeredReveal(1)
                    ArchiveCard {
                        VStack(spacing: 0) {
                            ForEach(Array(FontCatalog.apple.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { AppearanceHairline().padding(.leading, 16) }
                                FontRow(name: Text(entry.name), face: FontCatalog.face(entry.family, size: 19),
                                        state: state(of: entry.family, selected: selected, downloads: downloads)) {
                                    choose(entry.family)
                                }
                                .accessibilityIdentifier("aa.font.\(entry.family)")
                            }
                        }
                    }
                    .staggeredReveal(2)
                    Text("Apple's fonts download from Apple the first time you pick one, then stay on this device.")
                        .font(.footnote)
                        .foregroundStyle(Tokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .staggeredReveal(3)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .shioriHaptic(.selection, trigger: selected)
        .task {
            for entry in FontCatalog.apple {
                await downloads.activate(entry.family)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                IconView(.back, size: 20)
                    .frame(width: 36, height: 36)
                    .background(Tokens.surface, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))
            .accessibilityIdentifier("aa.fonts.back")
            Text("Font")
                .font(.title2.bold())
                .foregroundStyle(Tokens.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func state(of family: String, selected: String?, downloads: FontDownloads) -> FontRow.Status {
        if let fraction = downloads.progress[family] { return .downloading(fraction) }
        if downloads.failed.contains(family) { return .failed }
        guard downloads.isAvailable(family) else { return .notDownloaded }
        return selected == family ? .selected : .ready
    }

    private func choose(_ family: String?) {
        let preferences = model.readerPreferences
        FontDownloads.shared.choose(family) { chosen in
            guard preferences.typography.fontFamily != chosen else { return }
            preferences.typography.fontFamily = chosen
        }
    }
}

private struct FontRow: View {
    enum Status: Equatable {
        case ready, selected, notDownloaded, failed
        case downloading(Double)
    }

    let name: Text
    let face: Font
    let state: Status
    let action: () -> Void

    @Environment(\.motionReduced) private var reduced

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    name
                        .font(face)
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                    if state == .failed {
                        Text("Couldn't download. Tap to try again.")
                            .font(.footnote)
                            .foregroundStyle(Tokens.inkSecondary)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 12)
                trailing
                    .frame(minWidth: 28, minHeight: 28)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(SettingsPressStyle())
        .disabled(isDownloading)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(state == .selected ? [.isButton, .isSelected] : .isButton)
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .selected:
            IconView(.check, active: true, size: 20)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .notDownloaded, .failed:
            IconView(.import, size: 20)
                .opacity(0.7)
        case .downloading(let fraction):
            DownloadRing(fraction: fraction)
        case .ready:
            EmptyView()
        }
    }

    private var accessibilityValue: Text {
        switch state {
        case .notDownloaded: Text("Not downloaded")
        case .failed: Text("Couldn't download. Tap to try again.")
        case .downloading(let fraction): Text(fraction, format: .percent.precision(.fractionLength(0)))
        case .ready, .selected: Text(verbatim: "")
        }
    }
}

private struct DownloadRing: View {
    let fraction: Double

    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            if fraction > 0 {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary)
                    .contentTransition(.numericText(value: fraction))
                ZStack {
                    Circle().stroke(Tokens.line, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
                .animation(.easeOut(duration: 0.2), value: fraction)
            } else {
                // Before the first byte arrives Core Text is still asking Apple for the font.
                ProgressView()
                    .controlSize(.small)
                    .tint(Tokens.inkSecondary)
            }
        }
    }
}
