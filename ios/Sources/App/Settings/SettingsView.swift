import SwiftUI

struct SettingsView: View {
    private static let sourceCode = URL(string: "https://github.com/KaiC5504/Shiori")!

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ScreenHeader(code: "03 / SETTINGS", title: "Settings")
                    .padding(.bottom, 12)
                Text("About")
                    .font(.system(size: 12, design: .monospaced))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Tokens.inkSecondary)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    Text("Version \(Self.version) (\(Self.build))")
                        .foregroundStyle(Tokens.ink)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    Rectangle().fill(Tokens.line).frame(height: 1)
                    Link(destination: Self.sourceCode) {
                        HStack {
                            Text("Source code")
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Tokens.inkSecondary)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Tokens.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                }
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("More settings arrive in the next builds.")
                    .font(.footnote)
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Tokens.paper)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
