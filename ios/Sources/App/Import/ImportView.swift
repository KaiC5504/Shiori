import ShioriLibrary
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(AppModel.self) private var model
    @State private var showsPicker = false
    @State private var isCopying = false

    init() {}

    private var isBusy: Bool { isCopying || model.isImporting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(code: "02 / IMPORT", title: "Import")
                picker
                recentImports
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Tokens.paper)
        .fileImporter(isPresented: $showsPicker,
                      allowedContentTypes: [.epub, .plainText],
                      allowsMultipleSelection: true,
                      onCompletion: picked)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showsPicker = true
            } label: {
                HStack(spacing: 10) {
                    if isBusy {
                        ProgressView().tint(Tokens.paper)
                        Text("Importing…")
                    } else {
                        Image(systemName: "tray.and.arrow.down")
                        Text("Import files")
                    }
                }
                .font(.headline)
                .foregroundStyle(Tokens.paper)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Tokens.ink, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(InkButtonStyle())
            .disabled(isBusy)

            Text("EPUB and TXT files from Files, iCloud Drive or a USB drive.")
                .font(.footnote)
                .foregroundStyle(Tokens.inkSecondary)
        }
    }

    private var recentImports: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent imports")
                .font(.headline)
                .foregroundStyle(Tokens.ink)
                .accessibilityAddTraits(.isHeader)
            if model.importBatches.isEmpty {
                Text("No imports yet")
                    .font(.subheadline)
                    .foregroundStyle(Tokens.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1)
                    }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(model.importBatches) { batch in
                        ForEach(Array(batch.outcomes.enumerated()), id: \.offset) { _, outcome in
                            ImportOutcomeRow(outcome: outcome)
                        }
                    }
                }
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
        }
    }
}

private struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration)
    }

    private struct Pressable: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .opacity(configuration.isPressed || !isEnabled ? 0.8 : 1)
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: configuration.isPressed)
        }
    }
}
