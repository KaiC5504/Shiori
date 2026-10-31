#if DEBUG
import SwiftUI

/// Every icon at rest and active, for the compile check's screenshot (`-DemoIcons YES`).
struct IconGalleryView: View {
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ShioriIcon.allCases, id: \.self) { icon in
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            IconView(icon, active: false, size: 24)
                            IconView(icon, active: true, size: 24)
                        }
                        Text(verbatim: icon.rawValue)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Tokens.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Tokens.paper.ignoresSafeArea())
    }
}
#endif
