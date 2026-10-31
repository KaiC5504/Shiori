import ShioriLibrary
import SwiftUI

struct ImportOutcomeRow: View {
    let outcome: ImportOutcome

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var iconWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(symbolStyle)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                headline
                if case .failed(_, let reason) = outcome {
                    reasonText(reason)
                        .font(.subheadline)
                        .foregroundStyle(Tokens.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var headline: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                statusLabel
                title
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                statusLabel
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        if case .failed(let fileName, _) = outcome, fileName.isEmpty {
            titleStyle(Text("Import files"))
        } else {
            titleStyle(Text(verbatim: displayName))
        }
    }

    private func titleStyle(_ text: Text) -> some View {
        text
            .font(.body)
            .foregroundStyle(Tokens.ink)
            .lineLimit(2)
            .truncationMode(.middle)
    }

    private var statusLabel: some View {
        status
            .font(.caption2.monospaced().weight(.medium))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(isFailure ? Tokens.ink : Tokens.inkSecondary)
            .fixedSize()
    }

    private var status: Text {
        switch outcome {
        case .added: Text("Added")
        case .alreadyInLibrary: Text("Already in library")
        case .failed: Text("Failed")
        }
    }

    private var displayName: String {
        switch outcome {
        case .added(_, let title), .alreadyInLibrary(_, let title): title
        case .failed(let fileName, _): fileName
        }
    }

    private var symbol: String {
        switch outcome {
        case .added: "checkmark.circle.fill"
        case .alreadyInLibrary: "books.vertical.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var symbolStyle: Color {
        if case .alreadyInLibrary = outcome { Tokens.inkSecondary } else { Tokens.ink }
    }

    private var isFailure: Bool {
        if case .failed = outcome { true } else { false }
    }

    private func reasonText(_ reason: ImportFailure) -> Text {
        switch reason {
        case .drmProtected:
            return Text("This book is DRM-protected.")
        case .fixedLayout:
            return Text("Fixed-layout books aren't supported yet.")
        case .noChapters:
            return Text("No chapters were found.")
        case .empty:
            return Text("The file is empty.")
        case .unsupportedFormat:
            return Text("Only EPUB and TXT for now.")
        case .tooLarge(let limitBytes):
            let limit = ByteCountFormatter.string(fromByteCount: limitBytes, countStyle: .binary)
            return Text(String(localized: "Too large (over \(limit))."))
        case .unreadable:
            return Text("Couldn't read the file.")
        }
    }
}
