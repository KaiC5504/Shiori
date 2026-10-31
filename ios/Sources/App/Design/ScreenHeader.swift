import SwiftUI

/// The masthead every top-level screen opens with (spec §4.3): a Latin code line such as
/// "01 / SHELF", which stays untranslated, then the localised large title.
struct ScreenHeader: View {
    let code: String
    let title: LocalizedStringResource

    init(code: String, title: LocalizedStringResource) {
        self.code = code
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: code)
                .font(.system(.caption, design: .monospaced))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Tokens.inkSecondary)
                .staggeredReveal(0)
            Text(title)
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(Tokens.ink)
                .staggeredReveal(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The code line is decoration; VoiceOver reads the title alone.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isHeader)
    }
}
