import ShioriCore
import ShioriLibrary
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Import → TXT settings (spec §8.1): encoding, chapter rules, and a preview of
/// what those rules find in a chosen file.
struct TXTSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @State private var showsPicker = false
    @State private var preview: PreviewFile?
    @State private var pickFailed = false

    private struct PreviewFile: Equatable {
        var file: URL
        /// The inbox folder holding the copy, removed when the preview goes away.
        var folder: URL
    }

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    ScreenHeader(code: "03 / SETTINGS / TXT", title: "TXT settings")
                    Text("Applies to new imports and re-detected books.")
                        .font(.subheadline)
                        .foregroundStyle(Tokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 28)
                .staggeredReveal(0)
                encodingSection
                    .padding(.bottom, 32)
                    .staggeredReveal(1)
                rulesSection
                    .padding(.bottom, 32)
                    .staggeredReveal(2)
                previewSection
                    .staggeredReveal(3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .fileImporter(isPresented: $showsPicker, allowedContentTypes: [.plainText], onCompletion: picked)
        .task { loadDemoPreview() }
        .onDisappear { discardPreview() }
    }

    private var settings: Binding<ImportSettings> {
        Binding(get: { model.importSettings }, set: { model.importSettings = $0 })
    }

    private var encodingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(code: "TXT / ENCODING", title: "Encoding")
            EncodingSelector(selection: settings.encoding)
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(code: "TXT / RULES", title: "Chapter rules")
            ArchiveCard {
                VStack(spacing: 0) {
                    ForEach(ChapterRule.presets, id: \.id) { rule in
                        RuleToggle(rule: rule, isOn: ruleBinding(rule.id))
                        Hairline().padding(.leading, 14)
                    }
                    CustomPatternField(pattern: customPattern)
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(code: "TXT / PREVIEW", title: "Preview")
            ArchiveCard {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        showsPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            IconView(.document, active: preview != nil, size: 22)
                            Text("Choose a TXT file")
                                .font(.body)
                                .foregroundStyle(Tokens.ink)
                            Spacer(minLength: 8)
                            IconView(.forward, size: 16)
                                .opacity(0.5)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let preview {
                        Hairline()
                        ChapterPreview(file: preview.file, settings: model.importSettings)
                            .transition(.opacity)
                    } else if pickFailed {
                        Hairline()
                        Text("Couldn't read the file.")
                            .font(.subheadline)
                            .foregroundStyle(Tokens.ink)
                            .padding(14)
                    }
                }
            }
            .animation(Motion.animation(Motion.reveal, reduced: reduced), value: preview)
        }
    }

    private func ruleBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.importSettings.enabledRuleIDs.contains(id) },
            set: { isOn in
                if isOn {
                    model.importSettings.enabledRuleIDs.insert(id)
                } else {
                    model.importSettings.enabledRuleIDs.remove(id)
                }
            })
    }

    private var customPattern: Binding<String> {
        Binding(
            get: { model.importSettings.customPattern ?? "" },
            set: { model.importSettings.customPattern = $0.isEmpty ? nil : $0 })
    }

    private func picked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            let batch = await ImportInbox.copy([url])
            let previous = preview
            if let file = batch.copies.first, let folder = batch.folders.first {
                preview = PreviewFile(file: file, folder: folder)
                pickFailed = false
            } else {
                preview = nil
                pickFailed = true
            }
            if let previous { await ImportInbox.discard([previous.folder]) }
        }
    }

    private func discardPreview() {
        guard let folder = preview?.folder else { return }
        preview = nil
        Task { await ImportInbox.discard([folder]) }
    }

    private func loadDemoPreview() {
        #if DEBUG
        if DemoLaunch.settingsPage == "txt", preview == nil,
           let demo = ChapterPreview.writeDemoFile() {
            preview = PreviewFile(file: demo.file, folder: demo.folder)
        }
        #endif
    }
}

/// The five encodings as one strip; the chosen one sits under a lens that slides between them.
private struct EncodingSelector: View {
    @Binding var selection: TXTEncodingChoice

    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var lens

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(TXTEncodingChoice.allCases, id: \.self) { choice in
                cell(choice)
            }
        }
        .padding(4)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
        .shioriHaptic(.selection, trigger: selection)
    }

    private func cell(_ choice: TXTEncodingChoice) -> some View {
        let selected = selection == choice
        return Button {
            withAnimation(Motion.animation(Motion.lens, reduced: reduced)) { selection = choice }
        } label: {
            name(choice)
                .font(.footnote.monospaced().weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Tokens.paper : Tokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background { if selected { lensShape } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var lensShape: some View {
        let shape = RoundedRectangle(cornerRadius: 4).fill(accent)
        if reduced {
            shape.transition(.opacity)
        } else {
            shape.matchedGeometryEffect(id: "lens", in: lens)
        }
    }

    private func name(_ choice: TXTEncodingChoice) -> Text {
        switch choice {
        case .auto: Text("Auto")
        case .utf8: Text(verbatim: "UTF-8")
        case .gb18030: Text(verbatim: "GB18030")
        case .big5: Text(verbatim: "Big5")
        case .utf16: Text(verbatim: "UTF-16")
        }
    }
}

private struct RuleToggle: View {
    let rule: ChapterRule
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.body)
                    .foregroundStyle(Tokens.ink)
                if let sample {
                    Text(verbatim: sample)
                        .font(.caption.monospaced())
                        .foregroundStyle(Tokens.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    private var title: Text {
        switch rule.id {
        case "zh-chapter": Text("Chapters (第X章, 回, 节)")
        case "zh-volume": Text("Volumes (第X卷)")
        case "en-chapter": Text("Chapter N")
        case "numbered": Text("Numbered lines")
        default: Text(verbatim: rule.id)
        }
    }

    /// A heading line the rule would match, so the toggle says what it catches.
    private var sample: String? {
        switch rule.id {
        case "zh-chapter": "第十二章 雨夜"
        case "zh-volume": "第三卷 远行"
        case "en-chapter": "Chapter 12"
        case "numbered": "12. 归途"
        default: nil
        }
    }
}

private struct CustomPatternField: View {
    @Binding var pattern: String

    @Environment(\.motionReduced) private var reduced
    @FocusState private var focused: Bool

    private var isInvalid: Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && (try? NSRegularExpression(pattern: trimmed)) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom pattern")
                .font(.body)
                .foregroundStyle(Tokens.ink)
            TextField(text: $pattern, prompt: Text(verbatim: "^番外.{0,30}$")) {
                Text("Custom pattern")
            }
            .font(.callout.monospaced())
            .foregroundStyle(Tokens.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Tokens.paper, in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isInvalid || focused ? Tokens.ink : Tokens.line, lineWidth: 1)
            }
            if isInvalid {
                HStack(spacing: 6) {
                    IconView(.warning, size: 16)
                    Text("Invalid pattern")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Tokens.ink)
                }
                .transition(reduced ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(14)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: isInvalid)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: focused)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 1)
    }
}
