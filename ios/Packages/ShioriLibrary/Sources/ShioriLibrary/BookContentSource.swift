import Foundation

public enum BookContentError: Error, Equatable {
    case unsupportedFormat
}

/// Loads one chapter's content from an imported book's folder.
public final class BookContentSource: Sendable {
    private let book: Book
    private let directory: URL
    private let archive: EPUBArchive?

    public init(book: Book, paths: LibraryPaths) throws {
        self.book = book
        directory = paths.bookDirectory(book.id)
        archive = book.format == .epub ? try EPUBArchive(url: directory.appending(path: "original.epub")) : nil
    }

    public func content(of chapter: Chapter) throws -> ChapterContent {
        switch book.format {
        case .epub:
            guard let archive else { throw BookContentError.unsupportedFormat }
            let html = String(decoding: try archive.data(at: chapter.source), as: UTF8.self)
            let blocks = try XHTMLContentParser.blocks(from: html, documentPath: chapter.source)
            return ChapterContent(blocks: Self.withHeading(blocks, title: chapter.title))
        case .txt:
            let body = try String(contentsOf: directory.appending(path: chapter.source), encoding: .utf8)
            let lines = body.split(separator: "\n").map { ChapterBlock.paragraph(String($0)) }
            return ChapterContent(blocks: Self.withHeading(lines, title: chapter.title))
        case .pdf:
            throw BookContentError.unsupportedFormat
        }
    }

    /// The reader shows a chapter's title from its first heading, so a chapter file without
    /// one gets its contents title. Deterministic, so offsets stay stable.
    static func withHeading(_ blocks: [ChapterBlock], title: String) -> [ChapterBlock] {
        if case .heading = blocks.first { return blocks }
        guard !title.isEmpty else { return blocks }
        return [.heading(title, level: 2)] + blocks
    }
}
