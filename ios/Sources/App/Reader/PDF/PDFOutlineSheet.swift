import PDFKit
import SwiftUI

/// One entry of a PDF's outline, flattened in document order.
struct PDFOutlineRow: Identifiable {
    let id: Int
    let title: String
    let depth: Int
    /// 0-based; nil when the entry points nowhere in this file.
    let page: Int?
    let destination: PDFDestination?

    /// Every entry, children under their parent. Capped, since a broken outline can loop.
    @MainActor
    static func rows(of document: PDFDocument) -> [PDFOutlineRow] {
        guard let root = document.outlineRoot else { return [] }
        var rows: [PDFOutlineRow] = []
        func walk(_ item: PDFOutline, depth: Int) {
            for n in 0..<item.numberOfChildren {
                guard rows.count < 10_000, let child = item.child(at: n) else { return }
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                let page = destination?.page.map { document.index(for: $0) }
                    .flatMap { $0 >= 0 && $0 < document.pageCount ? $0 : nil }
                let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                rows.append(PDFOutlineRow(id: rows.count, title: title, depth: depth, page: page,
                                          destination: destination))
                if depth < 12 { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return rows
    }

    /// The entry a page is in: the last one at or before it.
    static func row(containing page: Int, in rows: [PDFOutlineRow]) -> PDFOutlineRow? {
        var best: PDFOutlineRow?
        for row in rows {
            guard let start = row.page, start <= page else { continue }
            if start >= (best?.page ?? Int.min) { best = row }
        }
        return best
    }
}

/// The PDF's outline as an indented list; a tap jumps there.
struct PDFOutlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [PDFOutlineRow]
    /// The row of the page being read.
    let current: Int?
    let onSelect: (PDFOutlineRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PDFSheetHeader(title: "Contents")
            ScrollViewReader { proxy in
                List(rows) { row in
                    self.row(row)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .task {
                    // A List in a sheet can drop a scroll asked for before its first layout.
                    await Task.yield()
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
        .background(Tokens.surface)
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tokens.surface)
    }

    private func row(_ row: PDFOutlineRow) -> some View {
        let isCurrent = row.id == current
        return Button {
            onSelect(row)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                title(of: row)
                    .font(row.depth == 0 ? .body.weight(isCurrent ? .bold : .semibold)
                                         : .body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(row.page == nil ? Tokens.inkSecondary : Tokens.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, CGFloat(min(row.depth, 6)) * 18)
                if isCurrent {
                    Circle()
                        .fill(Tokens.ink)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                if let page = row.page {
                    Text(verbatim: "\(page + 1)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(minWidth: 32, alignment: .trailing)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(row.page == nil && row.destination == nil)
        .listRowBackground(isCurrent ? Tokens.paper : Color.clear)
        .listRowSeparatorTint(Tokens.line)
        .accessibilityValue(isCurrent ? Text("Reading now") : Text(verbatim: ""))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func title(of row: PDFOutlineRow) -> Text {
        if !row.title.isEmpty { return Text(verbatim: row.title) }
        if let page = row.page { return Text("Page \(page + 1)") }
        return Text(verbatim: "—")
    }
}

/// The bold title and round close button the reader's sheets share (spec §7.7).
struct PDFSheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
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
}
