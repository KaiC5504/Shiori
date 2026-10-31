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
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: code)
                .font(.system(size: 12, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Tokens.inkSecondary)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Tokens.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
