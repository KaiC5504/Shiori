import ShioriLibrary
import SwiftUI
import UniformTypeIdentifiers

/// The Import tab's watched folder (spec §8.1): the folder, its last scan, Scan now, the
/// launch toggle and format chips; or, with none chosen, the two ways to pick one.
struct WatchedFolderCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionReduced) private var reduced
    @Environment(\.accent) private var accent
    @ScaledMetric private var tileSize: CGFloat = 44
    @State private var showsPicker = false
    @State private var scansDone = 0
    @State private var scansFailed = 0

    init() {}

    private var folder: WatchedFolderModel { model.watchedFolder }

    var body: some View {
        ArchiveCard {
            ZStack(alignment: .topLeading) {
                if folder.hasFolder {
                    linked.transition(.opacity)
                } else {
                    empty.transition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: folder.hasFolder)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: folder.problem != nil)
        .fileImporter(isPresented: $showsPicker, allowedContentTypes: [.folder], onCompletion: picked)
        .shioriHaptic(.success, trigger: scansDone)
        .shioriHaptic(.warning, trigger: scansFailed)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                tile(.folderAdd)
                Text("New books in this folder are imported automatically.")
                    .font(.subheadline)
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showsPicker = true
            } label: {
                Text("Choose a folder")
                    .font(.headline)
                    .foregroundStyle(Tokens.paper)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Tokens.ink, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PressStyle())
            Button {
                folder.useOwnFolder()
                scan()
            } label: {
                Text("Use Shiori's own folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Tokens.paper, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
            }
            .buttonStyle(PressStyle())
        }
    }

    private var linked: some View {
        @Bindable var folder = self.folder
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                tile(folder.problem != nil ? .warning : folder.usesOwnFolder ? .folder : .link,
                     active: folder.isScanning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: folder.folderName ?? "")
                        .font(.headline)
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    status
                }
                .frame(maxWidth: .infinity, minHeight: tileSize, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                ForEach(ScanFormat.allCases, id: \.self, content: chip)
            }

            Toggle(isOn: $folder.autoImport) {
                Text("Auto-import on launch")
                    .font(.subheadline)
                    .foregroundStyle(Tokens.ink)
            }
            .shioriHaptic(.selection, trigger: folder.autoImport)

            Tokens.line.frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    scanButton
                    Spacer(minLength: 0)
                    folderButtons
                }
                VStack(alignment: .leading, spacing: 12) {
                    scanButton
                    HStack(spacing: 16) { folderButtons }
                }
            }
        }
    }

    private var status: some View {
        Group {
            if let problem = folder.problem {
                Text(problem)
                    .foregroundStyle(Tokens.ink)
                    .fontWeight(.medium)
            } else if folder.isScanning {
                Text("Scanning…")
            } else if let lastScan = folder.lastScan {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    lastScanText(lastScan, now: context.date)
                }
                Text("Found \(folder.lastNewBooks) new books")
                    .foregroundStyle(folder.lastNewBooks > 0 ? accent : Tokens.inkSecondary)
            } else {
                Text("Never scanned")
            }
        }
        .font(.footnote)
        .foregroundStyle(Tokens.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The time for a scan in the last minute: "now" reads oddly after "Last scan".
    private func lastScanText(_ date: Date, now: Date) -> Text {
        if now.timeIntervalSince(date) < 60 {
            Text("Last scan \(date, format: .dateTime.hour().minute())")
        } else {
            Text("Last scan \(date, format: .relative(presentation: .named))")
        }
    }

    private func chip(_ format: ScanFormat) -> some View {
        let on = folder.formats.contains(format)
        return Button {
            withAnimation(Motion.animation(Motion.press, reduced: reduced)) { toggle(format) }
        } label: {
            Text(verbatim: format.rawValue.uppercased())
                .font(.caption.monospaced().weight(.semibold))
                .tracking(1)
                .foregroundStyle(on ? accent : Tokens.inkSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(on ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(on ? accent.opacity(0.5) : Tokens.line, lineWidth: 1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .shioriHaptic(.selection, trigger: on)
    }

    private var scanButton: some View {
        Button(action: scan) {
            HStack(spacing: 8) {
                IconView(.refresh, active: folder.isScanning, size: 18)
                if folder.isScanning {
                    Text("Scanning…")
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Tokens.inkSecondary)
                } else {
                    Text("Scan now")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Tokens.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line, lineWidth: 1) }
            .fixedSize()
        }
        .buttonStyle(PressStyle())
        .disabled(folder.isScanning)
    }

    /// Off while scanning, so the scan's result never lands on a folder that's since changed.
    @ViewBuilder
    private var folderButtons: some View {
        Group {
            Button("Change folder") { showsPicker = true }
                .foregroundStyle(accent)
            Button("Disconnect") { folder.disconnect() }
                .foregroundStyle(Tokens.inkSecondary)
        }
        .buttonStyle(PressStyle())
        .disabled(folder.isScanning)
        .opacity(folder.isScanning ? 0.4 : 1)
    }

    private func tile(_ icon: ShioriIcon, active: Bool = false) -> some View {
        IconView(icon, active: active, size: 24)
            .frame(width: tileSize, height: tileSize)
            .background(Tokens.paper, in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.line, lineWidth: 1) }
    }

    /// The last format can't be switched off: a scan of nothing would look like a broken folder.
    private func toggle(_ format: ScanFormat) {
        if folder.formats.contains(format) {
            guard folder.formats.count > 1 else { return }
            folder.formats.remove(format)
        } else {
            folder.formats.insert(format)
        }
    }

    private func picked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            folder.choose(url)
            scan()
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                folder.problem = "Folder unavailable. Choose it again."
            }
        }
    }

    private func scan() {
        Task {
            await folder.scanNow(settings: model.importSettings)
            if folder.problem == nil { scansDone += 1 } else { scansFailed += 1 }
        }
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration)
    }

    private struct Pressable: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.motionReduced) private var reduced

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.medium))
                .scaleEffect(configuration.isPressed && !reduced ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .animation(Motion.animation(Motion.press, reduced: reduced), value: configuration.isPressed)
        }
    }
}
