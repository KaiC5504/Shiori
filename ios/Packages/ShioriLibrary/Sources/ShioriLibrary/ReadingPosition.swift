import Foundation

/// Converts between the reader's (chapter, block) and a saved `Progress`.
public enum ReadingPosition {
    /// fraction = (chapterIndex + block / max(blockCount, 1)) / chapterCount
    public static func progress(bookId: UUID, chapter: Chapter, chapterCount: Int,
                                content: ChapterContent, block: Int, now: Date) -> Progress {
        let blockFraction = Double(block) / Double(max(content.blocks.count, 1))
        let fraction = (Double(chapter.index) + blockFraction) / Double(max(chapterCount, 1))
        return Progress(bookId: bookId, chapterIndex: chapter.index, keyTitle: chapter.keyTitle,
                        keyOccurrence: chapter.keyOccurrence, offset: content.offset(ofBlock: block),
                        fraction: min(max(fraction, 0), 1), updatedAt: now)
    }

    /// The chapter matching the saved key, else the saved index clamped to the book.
    public static func chapterIndex(for progress: Progress, in chapters: [Chapter]) -> Int {
        guard !chapters.isEmpty else { return 0 }
        if chapters.indices.contains(progress.chapterIndex), matches(chapters[progress.chapterIndex], progress) {
            return progress.chapterIndex
        }
        if let moved = chapters.firstIndex(where: { matches($0, progress) }) {
            return moved
        }
        return min(max(progress.chapterIndex, 0), chapters.count - 1)
    }

    public static func block(for progress: Progress, in content: ChapterContent) -> Int {
        content.block(containing: progress.offset)
    }

    private static func matches(_ chapter: Chapter, _ progress: Progress) -> Bool {
        chapter.keyTitle == progress.keyTitle && chapter.keyOccurrence == progress.keyOccurrence
    }
}
