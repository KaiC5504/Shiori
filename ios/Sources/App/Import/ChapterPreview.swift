import Foundation
import ShioriCore
import ShioriLibrary
import SwiftUI

/// Splits a chosen TXT with the current settings, the same way an import would, and lists
/// what it found. Runs again whenever the settings change.
struct ChapterPreview: View {
    let file: URL
    let settings: ImportSettings

    @Environment(\.motionReduced) private var reduced
    @State private var phase: PreviewPhase?
    @State private var phaseFile: URL?
    @State private var isRunning = true

    init(file: URL, settings: ImportSettings) {
        self.file = file
        self.settings = settings
    }

    private struct Input: Equatable {
        var file: URL
        var settings: ImportSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case nil:
                running
            case .done(let summary):
                results(summary)
                    .opacity(isRunning ? 0.45 : 1)
            case .empty:
                problem(Text("The file is empty."))
            case .unreadable:
                problem(Text("Couldn't read the file."))
            }
        }
        .animation(Motion.animation(Motion.reveal, reduced: reduced), value: phase)
        .animation(Motion.animation(Motion.press, reduced: reduced), value: isRunning)
        .task(id: Input(file: file, settings: settings)) {
            isRunning = true
            if phaseFile != file { phase = nil }
            // A custom pattern changes the settings on every keystroke, so wait for a pause.
            if phase != nil {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            let result = await PreviewRun.run(file: file, settings: settings)
            guard !Task.isCancelled else { return }
            phase = result
            phaseFile = file
            isRunning = false
        }
    }

    private var running: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(verbatim: file.lastPathComponent)
                .font(.footnote.monospaced())
                .foregroundStyle(Tokens.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
    }

    private func problem(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            IconView(.warning, size: 18)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            text
                .font(.subheadline)
                .foregroundStyle(Tokens.ink)
        }
        .padding(14)
    }

    private func results(_ summary: PreviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: summary.encodingName)
                    Text(verbatim: "·")
                    Text(verbatim: file.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption.monospaced())
                .foregroundStyle(Tokens.inkSecondary)
                Text("\(summary.chapterCount) chapters detected")
                    .font(.title3.bold())
                    .foregroundStyle(Tokens.ink)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(summary.entries) { entry in
                if let volume = entry.startsVolume {
                    Text(verbatim: volume)
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(Tokens.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: String(format: "%03d", entry.number))
                        .font(.caption.monospaced())
                        .foregroundStyle(Tokens.inkSecondary)
                    title(entry.title)
                        .font(.subheadline)
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
            if summary.chapterCount > summary.entries.count {
                Text(verbatim: "⋯")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
            }
            Spacer().frame(height: 12)
        }
    }

    private func title(_ title: PreviewSummary.Title) -> Text {
        switch title {
        case .text(let text): Text(verbatim: text)
        case .preface: Text("Preface")
        case .part(let number): Text("Part \(number)")
        }
    }
}

private enum PreviewPhase: Equatable, Sendable {
    case done(PreviewSummary)
    case empty
    case unreadable
}

private struct PreviewSummary: Equatable, Sendable {
    enum Title: Equatable, Sendable {
        case text(String)
        case preface
        case part(Int)
    }

    struct Entry: Identifiable, Equatable, Sendable {
        var number: Int
        var title: Title
        /// Set on the first entry under a new volume line.
        var startsVolume: String?
        var id: Int { number }
    }

    var encodingName: String
    var chapterCount: Int
    var entries: [Entry]
}

/// Kept apart from the view so none of it is tied to the main actor.
private enum PreviewRun {
    static let shownTitles = 50

    static func run(file: URL, settings: ImportSettings) async -> PreviewPhase {
        await Task.detached(priority: .userInitiated) {
            let data: Data
            do {
                data = try Data(contentsOf: file, options: .mappedIfSafe)
            } catch {
                return .unreadable
            }
            guard let decoded = try? TextDecoding.decode(data, preferred: preferredEncoding(settings.encoding)) else {
                return .empty
            }
            let chapters = ChapterSplitter.split(decoded.text, rules: settings.rules)
            return .done(summary(of: chapters, encoding: decoded.encoding))
        }.value
    }

    static func summary(of chapters: [TextChapter], encoding: String.Encoding) -> PreviewSummary {
        // Heading-less text comes back as untitled parts; an untitled chapter among titled
        // ones is the text before the first heading.
        let allUntitled = chapters.allSatisfy { $0.title.isEmpty }
        var entries: [PreviewSummary.Entry] = []
        var volume: String?
        for (index, chapter) in chapters.prefix(shownTitles).enumerated() {
            let title: PreviewSummary.Title = if !chapter.title.isEmpty {
                .text(chapter.title)
            } else if allUntitled {
                .part(index + 1)
            } else {
                .preface
            }
            let startsVolume = chapter.volume != volume ? chapter.volume : nil
            volume = chapter.volume
            entries.append(PreviewSummary.Entry(number: index + 1, title: title, startsVolume: startsVolume))
        }
        return PreviewSummary(encodingName: name(of: encoding), chapterCount: chapters.count, entries: entries)
    }

    static func preferredEncoding(_ choice: TXTEncodingChoice) -> String.Encoding? {
        switch choice {
        case .auto: nil
        case .utf8: .utf8
        case .gb18030: TextDecoding.gb18030
        case .big5: TextDecoding.big5
        case .utf16: .utf16
        }
    }

    static func name(of encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case TextDecoding.gb18030: "GB18030"
        case TextDecoding.big5: "Big5"
        case .utf16, .utf16LittleEndian, .utf16BigEndian: "UTF-16"
        default: encoding.description
        }
    }
}

#if DEBUG
extension ChapterPreview {
    /// A generated TXT for the TXT settings screenshot: a preface, then two volumes.
    static func writeDemoFile() -> (file: URL, folder: URL)? {
        let folder = ImportInbox.root.appending(path: "DemoPreview", directoryHint: .isDirectory)
        let file = folder.appending(path: "示例小说.txt", directoryHint: .notDirectory)
        let titles = ["雨夜", "旧信", "渡口", "灯下", "远行", "回声", "晴日", "归途"]
        var lines = ["序", "这是一段生成的示例前言。"]
        var number = 0
        for volume in ["第一卷 春", "第二卷 夏"] {
            lines.append(volume)
            for title in titles {
                number += 1
                lines.append("第\(chineseNumeral(number))章 \(title)")
                lines.append("　　这是第\(number)章的示例正文，由程序生成。")
            }
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(lines.joined(separator: "\n").utf8).write(to: file)
            return (file, folder)
        } catch {
            return nil
        }
    }

    private static func chineseNumeral(_ n: Int) -> String {
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        switch n {
        case ..<10: return digits[n]
        case 10: return "十"
        case ..<20: return "十" + digits[n % 10]
        default: return digits[n / 10] + "十" + digits[n % 10]
        }
    }
}
#endif
