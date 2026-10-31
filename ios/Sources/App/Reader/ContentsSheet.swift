import ShioriLibrary
import SwiftUI

/// The Contents sheet (spec §7.7, §7.8): a glass sheet with search, order and close. Its `List`
/// builds rows only as they scroll in, which is what keeps a 5,000-chapter book's contents
/// instant.
struct ContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionReduced) private var reduced
    let chapters: [Chapter]
    let current: Int
    let onSelect: (Int) -> Void

    @State private var query: String
    @State private var searching: Bool
    @State private var reversed = false
    @State private var focusesField = false
    @FocusState private var fieldFocused: Bool
    @Namespace private var glass

    init(chapters: [Chapter], current: Int, onSelect: @escaping (Int) -> Void) {
        self.chapters = chapters
        self.current = current
        self.onSelect = onSelect
        #if DEBUG
        let demoQuery = DemoLaunch.contentsQuery ?? ""
        #else
        let demoQuery = ""
        #endif
        _query = State(initialValue: demoQuery)
        _searching = State(initialValue: !demoQuery.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                List {
                    ContentsSections(chapters: chapters, current: current, query: query,
                                     reversed: reversed) { index in
                        onSelect(index)
                        dismiss()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                // Thousands of rows swapping at once would stall in an animated diff.
                .animation(nil, value: query)
                .animation(nil, value: reversed)
                .task {
                    // A List in a sheet can drop a scroll asked for before its first layout.
                    await Task.yield()
                    proxy.scrollTo(current, anchor: .center)
                }
                .onChange(of: reversed) {
                    Task {
                        await Task.yield()
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
        .shioriHaptic(.selection, trigger: reversed)
    }

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if searching {
                    searchField
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .modifier(GlassMorph(id: "search", namespace: glass, enabled: !reduced))
                } else {
                    Text("Contents")
                        .font(.title2.bold())
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .transition(reduced ? .opacity : .opacity.combined(with: .offset(x: -16)))
                    Button(action: openSearch) {
                        IconView(.search, size: 20)
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .modifier(GlassMorph(id: "search", namespace: glass, enabled: !reduced))
                    .accessibilityLabel(Text("Search chapters"))
                    .accessibilityIdentifier("contents.search")
                }
                orderButton
                closeButton
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            IconView(.search, size: 18)
            TextField("Search chapters", text: $query)
                .font(.body)
                .foregroundStyle(Tokens.ink)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { fieldFocused = false }
                .onAppear {
                    // Only a tap on search raises the keyboard; a demo query leaves the results clear.
                    if focusesField { fieldFocused = true }
                }
                .accessibilityIdentifier("contents.query")
            Button(action: closeSearch) {
                IconView(.close, size: 14)
                    .frame(width: 36, height: 36)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cancel"))
            .accessibilityIdentifier("contents.cancelSearch")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var orderButton: some View {
        Button {
            reversed.toggle()
        } label: {
            ZStack {
                Text(reversed ? "Reversed" : "In order")
                    .id(reversed)
                    .transition(reduced ? .opacity : .push(from: .bottom))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Tokens.ink)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .clipped()
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(Motion.animation(Motion.lens, reduced: reduced), value: reversed)
        .accessibilityIdentifier("contents.order")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            IconView(.close, size: 18)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Close"))
        .accessibilityIdentifier("contents.close")
    }

    private func openSearch() {
        focusesField = true
        withAnimation(Motion.animation(Motion.lens, reduced: reduced)) { searching = true }
    }

    private func closeSearch() {
        query = ""
        fieldFocused = false
        withAnimation(Motion.animation(Motion.lens, reduced: reduced)) { searching = false }
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

/// The search button and field morph into each other, except under Reduce Motion, where they
/// only fade.
private struct GlassMorph: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}
