import Foundation
import ShioriCore

public struct PaginationKey: Hashable, Sendable {
    public var bookId: UUID
    public var chapter: ChapterKey
    public var typography: ReaderTypography
    public var size: PageSize

    public init(bookId: UUID, chapter: ChapterKey, typography: ReaderTypography, size: PageSize) {
        self.bookId = bookId
        self.chapter = chapter
        self.typography = typography
        self.size = size
    }
}

/// Recent chapter layouts, in memory only: they rebuild in milliseconds, and NSCache lets
/// them go under memory pressure. Thread-safe.
public final class PaginationCache: @unchecked Sendable {
    private let storage = NSCache<Key, ChapterLayout>()

    public init(countLimit: Int = 24) {
        storage.countLimit = countLimit
    }

    public func removeAll() {
        storage.removeAllObjects()
    }

    func layout(for key: PaginationKey) -> ChapterLayout? {
        storage.object(forKey: Key(key))
    }

    func store(_ layout: ChapterLayout, for key: PaginationKey) {
        storage.setObject(layout, forKey: Key(key))
    }

    private final class Key: NSObject {
        let value: PaginationKey

        init(_ value: PaginationKey) {
            self.value = value
        }

        override var hash: Int { value.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? Key)?.value == value
        }
    }
}
