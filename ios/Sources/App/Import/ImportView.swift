import ShioriLibrary
import SwiftUI
import UniformTypeIdentifiers

/// The Import tab (spec §8.1): the Files picker, the watched folder and the import log.
struct ImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @State private var showsPicker = false
    @State private var isCopying = false
    @State private var finishedImports = 0

    init() {}

    private var isBusy: Bool { isCopying || model.isImporting }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenHeader(code: "02 / IMPORT", title: "Import")
                    .padding(.bottom, 28)
                    .staggeredReveal(0)
                filesSection
                    .padding(.bottom, 32)
                    .staggeredReveal(1)
                folderSection
                    .padding(.bottom, 32)
                    .staggeredReveal(2)
                SectionLabel(code: "LOG / RECENT", title: "Recent imports")
                    .padding(.bottom, 14)
                    .staggeredReveal(3)
                log
            }
            .animation(Motion.animation(Motion.reveal, reduced: reduced), value: model.importBatches.first?.id)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .fileImporter(isPresented: $showsPicker,
                      allowedContentTypes: [.epub, .plainText, .pdf, .zip],
                      allowsMultipleSelection: true,
                      onCompletion: picked)
        .shioriHaptic(.success, trigger: finishedImports)
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(code: "SOURCES / FILES", title: "From Files")
            Button {
                showsPicker = true
            } label: {
                if isBusy {
                    Text("Importing…")
                } else {
                    Text("Import files")
                }
            }
            .buttonStyle(ImportSlabStyle(busy: isBusy))
            .disabled(isBusy)
            Text("EPUB, TXT, PDF and ZIP files from Files, iCloud Drive or a USB drive.")
                .font(.footnote)
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(code: "SOURCES / FOLDER", title: "Watched folder")
            WatchedFolderCard()
        }
    }

    @ViewBuilder
    private var log: some View {
        if model.importBatches.isEmpty {
            EmptyLog()
                .staggeredReveal(4)
        } else {
            ForEach(Array(model.importBatches.enumerated()), id: \.element.id) { index, batch in
                ImportBatchCard(batch: batch)
                    .padding(.bottom, 18)
                    .staggeredReveal(min(index, 4) + 4)
                    .transition(reduced ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func picked(_ result: Result<[URL], Error>) {
        let urls: [URL]
        switch result {
        case .success(let picked):
            urls = picked
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                model.logFailures([.failed(fileName: "", reason: .unreadable(error.localizedDescription))],
                                  origin: .picker)
            }
            return
        }
        guard !urls.isEmpty else { return }
        isCopying = true
        Task {
            let batch = await ImportInbox.copy(urls)
            await model.importFiles(batch.copies, origin: .picker)
            model.logFailures(batch.failures, origin: .picker)
            await ImportInbox.discard(batch.folders)
            isCopying = false
            finishedImports += 1
        }
    }
}

/// One batch of the log: where it came from and when, then a row per file.
private struct ImportBatchCard: View {
    let batch: ImportBatch

    @Environment(\.motionReduced) private var reduced
    @State private var expanded = false

    /// A first scan of a big folder logs hundreds of files; the rest wait behind "Show all".
    private static let collapsedCount = 6

    private var visible: ArraySlice<ImportOutcome> {
        expanded ? batch.outcomes[...] : batch.outcomes.prefix(Self.collapsedCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ArchiveCard {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, outcome in
                        if index > 0 { Hairline().padding(.leading, 14) }
                        ImportOutcomeRow(outcome: outcome)
                    }
                    if batch.outcomes.count > Self.collapsedCount {
                        Hairline()
                        expandButton
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            IconView(originIcon, size: 16)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            originTitle
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tokens.ink)
            Spacer(minLength: 8)
            Text(batch.date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                .font(.caption.monospaced())
                .foregroundStyle(Tokens.inkSecondary)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var originTitle: Text {
        switch batch.origin {
        case .picker: Text("From Files")
        case .watchedFolder: Text("From the watched folder")
        case .openIn: Text("From Open in")
        }
    }

    private var originIcon: ShioriIcon {
        switch batch.origin {
        case .picker: .document
        case .watchedFolder: .folder
        case .openIn: .share
        }
    }

    private var expandButton: some View {
        Button {
            withAnimation(Motion.animation(Motion.reveal, reduced: reduced)) { expanded.toggle() }
        } label: {
            Group {
                if expanded {
                    Text("Show less")
                } else {
                    Text("Show all \(batch.outcomes.count)")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Tokens.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyLog: View {
    var body: some View {
        VStack(spacing: 10) {
            IconView(.history, size: 28)
                .opacity(0.5)
            Text("No imports yet")
                .font(.subheadline)
                .foregroundStyle(Tokens.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Tokens.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.line)
            .frame(height: 1)
    }
}

/// The big Import files slab. Its glyph is the import icon in paper: the card drops into the
/// tray on press and keeps dropping while files import.
private struct ImportSlabStyle: ButtonStyle {
    let busy: Bool

    func makeBody(configuration: Configuration) -> some View {
        ImportSlab(label: configuration.label, pressed: configuration.isPressed, busy: busy)
    }
}

private struct ImportSlab<Label: View>: View {
    let label: Label
    let pressed: Bool
    let busy: Bool

    @Environment(\.accent) private var accent
    @Environment(\.motionReduced) private var reduced
    @ScaledMetric private var glyphSize: CGFloat = 30
    @State private var activity: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            ImportGlyph(activity: activity, size: glyphSize)
            label
                .font(.headline)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Tokens.paper)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(accent, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(pressed && !reduced ? 0.98 : 1)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: pressed)
        .onChange(of: pressed) { _, _ in settle() }
        .onChange(of: busy) { _, _ in settle() }
    }

    private func settle() {
        if busy, !reduced {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { activity = 1 }
        } else {
            withAnimation(Motion.animation(Motion.lens, reduced: reduced)) {
                activity = pressed || busy ? 1 : 0
            }
        }
    }
}

private struct ImportGlyph: View, Animatable {
    var activity: CGFloat
    let size: CGFloat

    var animatableData: CGFloat {
        get { activity }
        set { activity = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            var context = context
            IconPainter.paint(.import, in: &context, activity: activity,
                              style: IconStyle(size: size, ink: Tokens.paper, active: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
