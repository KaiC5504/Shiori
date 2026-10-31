import ShioriLibrary
import SwiftUI

/// One file's result in the import log: what it was, then what happened to it in plain words.
struct ImportOutcomeRow: View {
    let outcome: ImportOutcome

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var iconSize: CGFloat = 22

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconView(icon, size: iconSize)
                .opacity(isQuiet ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 3) {
                if dynamicTypeSize.isAccessibilitySize {
                    if isFailure { failedStamp }
                    title
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title.frame(maxWidth: .infinity, alignment: .leading)
                        if isFailure { failedStamp }
                    }
                }
                detail
                    .font(.footnote)
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var title: some View {
        Group {
            if case .failed(let fileName, _) = outcome, fileName.isEmpty {
                Text("Import files")
            } else {
                Text(verbatim: displayName)
            }
        }
        .font(.body)
        .foregroundStyle(isQuiet ? Tokens.inkSecondary : Tokens.ink)
        .lineLimit(2)
        .truncationMode(.middle)
    }

    /// A rubber-stamp mark, so a failure reads at a glance in a long log.
    private var failedStamp: some View {
        Text("Failed")
            .font(.caption2.monospaced().weight(.semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.ink, lineWidth: 1) }
            .fixedSize()
    }

    private var detail: Text {
        switch outcome {
        case .added:
            Text("Added")
        case .alreadyInLibrary:
            Text("Already in library")
        case .updated(_, _, .addedChapters(let count)):
            Text("Updated: +\(count) chapters")
        case .updated(_, _, .changed):
            Text("Updated: changed")
        case .resplit(_, _, let chapters):
            Text("Re-detected: \(chapters) chapters")
        case .skipped(_, let reason):
            skipText(reason)
        case .failed(_, let reason):
            failureText(reason)
        }
    }

    private var displayName: String {
        switch outcome {
        case .added(_, let title), .alreadyInLibrary(_, let title), .updated(_, let title, _),
             .resplit(_, let title, _): title
        case .skipped(let fileName, _), .failed(let fileName, _): fileName
        }
    }

    private var icon: ShioriIcon {
        switch outcome {
        case .added: .check
        case .alreadyInLibrary: .book
        case .updated, .resplit: .refresh
        case .skipped: .info
        case .failed: .warning
        }
    }

    /// Nothing changed in the library, so the row steps back.
    private var isQuiet: Bool {
        switch outcome {
        case .alreadyInLibrary, .skipped: true
        default: false
        }
    }

    private var isFailure: Bool {
        if case .failed = outcome { true } else { false }
    }

    private func skipText(_ reason: SkipReason) -> Text {
        switch reason {
        case .removedEarlier: Text("Removed earlier, skipped")
        case .nestedArchive: Text("Nested ZIP skipped")
        case .waitingForDownload: Text("Waiting for iCloud download")
        case .tooManyFiles(let limit): Text("Too many files: only the first \(limit) were scanned")
        }
    }

    private func failureText(_ reason: ImportFailure) -> Text {
        switch reason {
        case .drmProtected:
            Text("This book is DRM-protected.")
        case .fixedLayout:
            Text("Fixed-layout books aren't supported yet.")
        case .noChapters:
            Text("No chapters were found.")
        case .empty:
            Text("The file is empty.")
        case .unsupportedFormat:
            Text("Only EPUB, TXT, PDF and ZIP files.")
        case .tooLarge(let limitBytes):
            // Interpolated into the key (not String(localized:)) so the in-app language applies.
            Text("Too large (over \(limitBytes, format: .byteCount(style: .binary))).")
        case .unreadable:
            Text("Couldn't read the file.")
        }
    }
}
