import SwiftUI

/// The pages one tap below the tab. Raw values match `-DemoSettingsPage`.
enum SettingsPage: String, Hashable {
    case accent, txt
}

/// Spec §9: compact grouped rows that change in place, with deeper pages that zoom out of
/// the row that opened them.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced
    @State private var page: SettingsPage?
    @State private var revealPass = 0
    @Namespace private var zoom
    #if DEBUG
    @State private var demoPushed = false
    #endif

    private static let sourceCode = URL(string: "https://github.com/KaiC5504/Shiori")!

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(code: "03 / SETTINGS", title: localized("Settings"))
                    .staggeredReveal(0)
                    .padding(.bottom, 28)
                group(1, code: "SYSTEM / GENERAL", title: "General") { general }
                group(3, code: "SYSTEM / APPEARANCE", title: "Appearance") { appearance }
                group(5, code: "SOURCES / IMPORT", title: "Import") { imports }
                group(7, code: "COLOPHON / ABOUT", title: "About", ribbon: true) { about }
            }
            // The tabs stay alive behind the bar, so the stagger replays each time the tab
            // comes forward instead of only once at launch.
            .id(revealPass)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .paperBackground()
        .navigationDestination(item: $page) { page in
            destination(page)
        }
        .onChange(of: model.selectedTab) { _, tab in
            if tab == .settings { revealPass += 1 }
        }
        #if DEBUG
        .task {
            guard !demoPushed, let demo = DemoLaunch.settingsPage.flatMap(SettingsPage.init) else { return }
            demoPushed = true
            page = demo
        }
        #endif
    }

    private func group<Rows: View>(_ index: Int, code: String, title: LocalizedStringResource,
                                   ribbon: Bool = false,
                                   @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(code: code, title: localized(title))
                .staggeredReveal(index)
            ArchiveCard {
                VStack(spacing: 0) { rows() }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .overlay(alignment: .topTrailing) {
                if ribbon {
                    SettingsRibbon()
                        .fill(Tokens.ribbon)
                        .frame(width: 10, height: 26)
                        .padding(.trailing, 22)
                        .accessibilityHidden(true)
                }
            }
            .staggeredReveal(index + 1)
        }
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var general: some View {
        @Bindable var settings = model.settings
        menuRow("Language", value: name(of: settings.language),
                selection: $settings.language.animation(changeAnimation)) {
            ForEach(AppLanguage.allCases, id: \.self) { name(of: $0).tag($0) }
        }
        .shioriHaptic(.selection, trigger: settings.language)
        SettingsDivider()
        SettingsToggleRow("Haptics", isOn: $settings.haptics)
            .shioriHaptic(.selection, trigger: settings.haptics)
    }

    @ViewBuilder
    private var appearance: some View {
        @Bindable var settings = model.settings
        menuRow("Mode", value: name(of: settings.appearance),
                selection: $settings.appearance.animation(changeAnimation)) {
            ForEach(AppearanceMode.allCases, id: \.self) { name(of: $0).tag($0) }
        }
        .shioriHaptic(.selection, trigger: settings.appearance)
        SettingsDivider()
        pageRow(.accent) {
            SettingsRow("Accent") {
                SettingsValue(accentName)
                Circle()
                    .fill(accent)
                    .overlay { Circle().strokeBorder(Tokens.line, lineWidth: 1) }
                    .frame(width: 14, height: 14)
                    .animation(changeAnimation, value: settings.accent)
                    .accessibilityHidden(true)
                SettingsGlyph.push.image
            }
        }
        SettingsDivider()
        SettingsToggleRow("Reduce motion in Shiori",
                          footnote: Text("Animations become short fades."),
                          isOn: $settings.reduceMotion.animation(changeAnimation))
            .shioriHaptic(.selection, trigger: settings.reduceMotion)
    }

    @ViewBuilder
    private var imports: some View {
        let folder = model.watchedFolder
        pageRow(.txt) {
            SettingsRow("TXT settings") { SettingsGlyph.push.image }
        }
        SettingsDivider()
        Button {
            withAnimation(Motion.animation(Motion.lens, reduced: reduced)) {
                model.selectedTab = .imports
            }
        } label: {
            SettingsRow("Watched folder", footnote: folder.problem.map { Text(localized($0)) }) {
                SettingsValue(folderValue(folder))
                    .animation(changeAnimation, value: folder.isScanning)
                SettingsGlyph.push.image
            }
        }
        .buttonStyle(SettingsPressStyle())
    }

    @ViewBuilder
    private var about: some View {
        SettingsRow("Version \(Self.version) (\(Self.build))")
        SettingsDivider()
        Link(destination: Self.sourceCode) {
            SettingsRow("Source code") { SettingsGlyph.external.image }
        }
        .buttonStyle(SettingsPressStyle())
    }

    private func menuRow<Value: Hashable, Options: View>(_ title: LocalizedStringKey, value: Text,
                                                         selection: Binding<Value>,
                                                         @ViewBuilder options: () -> Options) -> some View {
        Menu {
            Picker(selection: selection) {
                options()
            } label: {
                Text(title)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            SettingsRow(title) {
                SettingsValue(value)
                SettingsGlyph.menu.image
            }
        }
        .menuStyle(.button)
        .buttonStyle(SettingsPressStyle())
    }

    private func pageRow<Label: View>(_ target: SettingsPage, @ViewBuilder label: () -> Label) -> some View {
        Button {
            page = target
        } label: {
            label()
        }
        .buttonStyle(SettingsPressStyle())
        .matchedTransitionSource(id: target, in: zoom) { source in
            source
                .background(Tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func destination(_ page: SettingsPage) -> some View {
        Group {
            switch page {
            case .accent: AccentSettingsView()
            case .txt: TXTSettingsView()
            }
        }
        .modifier(ZoomOutOfRow(id: page, namespace: zoom))
    }

    private var changeAnimation: Animation {
        Motion.animation(Motion.reveal, reduced: reduced)
    }

    private var accentName: Text {
        switch model.settings.accent {
        case .preset(let preset): Text(localized(preset.title))
        case .custom: Text("Custom")
        }
    }

    private func folderValue(_ folder: WatchedFolderModel) -> Text {
        if folder.isScanning { return Text("Scanning…") }
        if let name = folder.folderName { return Text(verbatim: name) }
        if folder.usesOwnFolder { return Text(verbatim: "Shiori") }
        return Text("Choose a folder")
    }

    /// The language names stay in their own script whatever the app's language.
    private func name(of language: AppLanguage) -> Text {
        switch language {
        case .system: Text("Follow System")
        case .zhHans: Text(verbatim: "简体中文")
        case .english: Text(verbatim: "English")
        }
    }

    private func name(of mode: AppearanceMode) -> Text {
        switch mode {
        case .system: Text("System")
        case .light: Text("Light")
        case .dark: Text("Dark")
        }
    }

    /// Resources resolve in the in-app language, which can differ from the phone's.
    private func localized(_ resource: LocalizedStringResource) -> LocalizedStringResource {
        var resource = resource
        resource.locale = locale
        return resource
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}

/// Under reduced motion the page arrives with the default push instead.
private struct ZoomOutOfRow: ViewModifier {
    let id: SettingsPage
    let namespace: Namespace.ID
    @Environment(\.motionReduced) private var reduced

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduced {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        }
    }
}
