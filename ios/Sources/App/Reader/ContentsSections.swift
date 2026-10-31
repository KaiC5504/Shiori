import ShioriCore
import ShioriLibrary
import SwiftUI

/// The contents rows grouped by volume: a ForEach of Sections, for a List (the sheet) or a
/// LazyVStack (the detail page). Volumes fold; a search lists its matches without volumes,
/// best first.
struct ContentsSections: View {
    let chapters: [Chapter]
    let current: Int?
    let query: String
    let reversed: Bool
    let onSelect: (Int) -> Void
    private var currentLabel: LocalizedStringResource = "Reading now"

    @State private var search = ContentsSearch()
    /// Volumes, by first chapter index, whose fold the reader has flipped from where it started.
    @State private var flipped: Set<Int> = []
    @Environment(\.motionReduced) private var reduced
    @Environment(\.accent) private var accent
    @Environment(\.locale) private var locale

    init(chapters: [Chapter], current: Int?, query: String, reversed: Bool,
         onSelect: @escaping (Int) -> Void) {
        self.chapters = chapters
        self.current = current
        self.query = query
        self.reversed = reversed
        self.onSelect = onSelect
    }

    /// What the current row says: "Reading now" unless set, such as "Last read" on the detail page.
    func currentLabel(_ label: LocalizedStringResource) -> ContentsSections {
        var copy = self
        copy.currentLabel = label
        return copy
    }

    var body: some View {
        // Asked from the body: a ForEach of Sections has no single view to hang a `.task` on, and
        // one on each row would come and go as rows scroll out of a List.
        if let found = search.matches(for: query, in: chapters) {
            Section {
                if found.isEmpty {
                    Text("No chapters match")
                        .font(.subheadline)
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .modifier(ContentsListRow())
                } else {
                    ForEach(reversed ? Array(found.reversed()) : found, id: \.self) { index in
                        row(index, inSearch: true)
                    }
                }
            }
        } else {
            let volumes = ContentsVolume.group(chapters)
            ForEach(reversed ? Array(volumes.reversed()) : volumes) { volume in
                Section {
                    if let title = volume.title {
                        header(volume, title: title)
                    }
                    if isOpen(volume) {
                        ForEach(reversed ? Array(volume.chapters.reversed()) : Array(volume.chapters),
                                id: \.self) { index in
                            row(index, inSearch: false)
                        }
                    }
                }
            }
        }
    }

    private func isOpen(_ volume: ContentsVolume) -> Bool {
        // With no current chapter (a book not yet read), the first volume opens instead.
        let startsOpen = volume.title == nil
            || current.map { volume.chapters.contains($0) } ?? (volume.chapters.lowerBound == 0)
        return startsOpen != flipped.contains(volume.chapters.lowerBound)
    }

    private func header(_ volume: ContentsVolume, title: String) -> some View {
        let open = isOpen(volume)
        return Button {
            withAnimation(Motion.animation(Motion.lens, reduced: reduced)) {
                flipped.formSymmetricDifference([volume.chapters.lowerBound])
            }
        } label: {
            HStack(spacing: 10) {
                IconView(.forward, size: 14)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .animation(reduced ? nil : Motion.lens, value: open)
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "\(volume.chapters.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Tokens.inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Tokens.line)
                    .frame(height: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(ContentsPressStyle())
        .shioriHaptic(.selection, trigger: flipped.contains(volume.chapters.lowerBound))
        .modifier(ContentsListRow())
        .accessibilityLabel(Text(verbatim: "\(title), \(chapterCount(volume.chapters.count))"))
        .accessibilityValue(open ? Text("Expanded") : Text("Collapsed"))
        .accessibilityAddTraits(.isHeader)
    }

    /// In the view's locale, which an in-app language switch changes and the process's doesn't.
    private func chapterCount(_ count: Int) -> String {
        var resource: LocalizedStringResource = "\(count) chapters"
        resource.locale = locale
        return String(localized: resource)
    }

    private func row(_ index: Int, inSearch: Bool) -> some View {
        let chapter = chapters[index]
        let isCurrent = index == current
        return Button {
            onSelect(index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                // The widest number sets the column, so titles line up and numbers never wrap.
                ZStack(alignment: .leading) {
                    Text(verbatim: String(repeating: "0", count: max(2, String(chapters.count).count)))
                        .hidden()
                    Text(verbatim: index < 9 ? "0\(index + 1)" : "\(index + 1)")
                }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(isCurrent ? accent : Tokens.inkSecondary)
                .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    title(of: chapter, at: index, marking: inSearch ? query : nil)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(Tokens.ink)
                        .multilineTextAlignment(.leading)
                    if inSearch, let volume = chapter.volume, !volume.isEmpty {
                        Text(verbatim: volume)
                            .font(.caption)
                            .foregroundStyle(Tokens.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Text(currentLabel)
                        .font(.caption)
                        .foregroundStyle(Tokens.inkSecondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Tokens.ink.opacity(0.07))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(ContentsPressStyle())
        .modifier(ContentsListRow())
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("contents.chapter.\(index)")
    }

    /// The title, with the searched text picked out in the accent.
    private func title(of chapter: Chapter, at index: Int, marking query: String?) -> Text {
        let needle = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !needle.isEmpty, !chapter.title.isEmpty,
              let found = chapter.title.range(of: needle, options: [.caseInsensitive, .widthInsensitive])
        else { return ContentsSheet.title(of: chapter, at: index) }
        var marked = AttributedString(chapter.title)
        if let range = Range(found, in: marked) {
            marked[range].foregroundColor = accent
            marked[range].font = Font.body.weight(.bold)
        }
        return Text(marked)
    }
}

/// Rows draw their own band and padding, so they look the same in a List and a LazyVStack.
private struct ContentsListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct ContentsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Tokens.ink.opacity(configuration.isPressed ? 0.06 : 0))
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A run of consecutive chapters that share a volume (or have none).
private struct ContentsVolume: Identifiable {
    // Its own type, so `scrollTo(chapterIndex)` can never land on a volume instead.
    struct ID: Hashable {
        let start: Int
    }

    let title: String?
    let chapters: Range<Int>

    var id: ID { ID(start: chapters.lowerBound) }

    static func group(_ chapters: [Chapter]) -> [ContentsVolume] {
        var volumes: [ContentsVolume] = []
        var start = 0
        while start < chapters.count {
            let volume = chapters[start].volume
            var end = start + 1
            while end < chapters.count, chapters[end].volume == volume { end += 1 }
            let title = volume.flatMap { $0.isEmpty ? nil : $0 }
            volumes.append(ContentsVolume(title: title, chapters: start..<end))
            start = end
        }
        return volumes
    }
}

/// Runs the search off the main actor. The book's titles are prepared once, and typing is
/// debounced; until a query's matches arrive, the previous query's stay up.
@MainActor @Observable
private final class ContentsSearch {
    private struct Key: Equatable {
        let query: String
        let book: UUID?
        let count: Int
    }

    private struct Found {
        let session: Int
        let count: Int
        let indices: [Int]
    }

    private var found: Found?
    // Read and written while the view's body runs, so none of these may be observed.
    @ObservationIgnored private var asked: Key?
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var prepared: (book: UUID?, count: Int, index: ChapterSearch.Index)?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The matching chapter indices, or nil to show every chapter.
    func matches(for query: String, in chapters: [Chapter]) -> [Int]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if asked != nil {
                task?.cancel()
                asked = nil
                session += 1
            }
            return nil
        }
        let key = Key(query: trimmed, book: chapters.first?.bookId, count: chapters.count)
        if key != asked { ask(key, chapters) }
        // Matches for a longer chapter list could point past the end of this one.
        guard let found, found.session == session, found.count == chapters.count else { return nil }
        return found.indices
    }

    private func ask(_ key: Key, _ chapters: [Chapter]) {
        // The first letter searches at once; the ones typed after it wait for a pause.
        let debounces = asked != nil
        asked = key
        task?.cancel()
        let session = session
        let cached = prepared.flatMap { $0.book == key.book && $0.count == key.count ? $0.index : nil }
        task = Task { [weak self] in
            if debounces {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            let (index, indices) = await Task.detached(priority: .userInitiated) {
                let index = cached ?? ChapterSearch.Index(titles: chapters.map(\.title))
                return (index, index.matches(key.query))
            }.value
            guard let self else { return }
            prepared = (key.book, key.count, index)
            if Task.isCancelled { return }
            found = Found(session: session, count: key.count, indices: indices)
        }
    }
}
