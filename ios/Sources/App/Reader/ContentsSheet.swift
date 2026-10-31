import ShioriLibrary
import SwiftUI

/// The book's chapters grouped by volume. A `List` builds rows only as they scroll in, which
/// is what keeps a 5,000-chapter book's contents instant.
struct ContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [Chapter]
    let current: Int
    let onSelect: (Int) -> Void
    private let sections: [ContentsSection]

    init(chapters: [Chapter], current: Int, onSelect: @escaping (Int) -> Void) {
        self.chapters = chapters
        self.current = current
        self.onSelect = onSelect
        sections = ContentsSection.group(chapters)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.chapters, id: \.self) { index in
                                row(index)
                            }
                        } header: {
                            if let volume = section.volume {
                                Text(verbatim: volume)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Tokens.inkSecondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .task {
                    // A List in a sheet can drop a scroll asked for before its first layout.
                    await Task.yield()
                    proxy.scrollTo(current, anchor: .center)
                }
            }
        }
        .background(Tokens.surface)
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tokens.surface)
    }

    private var header: some View {
        HStack {
            Text("Contents")
                .font(.title2.bold())
                .foregroundStyle(Tokens.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                    .frame(width: 36, height: 36)
                    .background(Tokens.paper, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func row(_ index: Int) -> some View {
        let isCurrent = index == current
        return Button {
            onSelect(index)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(verbatim: "\(index + 1)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Tokens.inkSecondary)
                    .frame(minWidth: 40, alignment: .leading)
                Self.title(of: chapters[index], at: index)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(Tokens.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Circle()
                        .fill(Tokens.ink)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Tokens.paper : Color.clear)
        .listRowSeparatorTint(Tokens.line)
        .accessibilityValue(isCurrent ? Text("Current chapter") : Text(verbatim: ""))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    static func title(of chapter: Chapter, at index: Int) -> Text {
        if !chapter.title.isEmpty { return Text(verbatim: chapter.title) }
        return index == 0 ? Text("Preface") : Text("Part \(index + 1)")
    }

    /// The same title as a string, in `locale` rather than the process's language, which an
    /// in-app language switch doesn't change.
    static func titleString(of chapter: Chapter, at index: Int, locale: Locale) -> String {
        if !chapter.title.isEmpty { return chapter.title }
        var resource: LocalizedStringResource
        if index == 0 {
            resource = "Preface"
        } else {
            resource = "Part \(index + 1)"
        }
        resource.locale = locale
        return String(localized: resource)
    }
}

/// A run of consecutive chapters that share a volume (or have none).
private struct ContentsSection: Identifiable {
    // Its own type, so `scrollTo(chapterIndex)` can never land on a section header instead.
    struct ID: Hashable {
        let start: Int
    }

    let id: ID
    let volume: String?
    let chapters: Range<Int>

    static func group(_ chapters: [Chapter]) -> [ContentsSection] {
        var sections: [ContentsSection] = []
        var start = 0
        while start < chapters.count {
            let volume = chapters[start].volume
            var end = start + 1
            while end < chapters.count, chapters[end].volume == volume { end += 1 }
            let label = volume.flatMap { $0.isEmpty ? nil : $0 }
            sections.append(ContentsSection(id: ID(start: start), volume: label, chapters: start..<end))
            start = end
        }
        return sections
    }
}
