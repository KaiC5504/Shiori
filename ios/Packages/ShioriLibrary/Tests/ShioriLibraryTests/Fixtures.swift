import Foundation
@testable import ShioriLibrary

extension Book {
    static func fixture(title: String, addedAt seconds: TimeInterval) -> Book {
        Book(id: UUID(), title: title, author: nil, format: .epub, sourceIdentifier: nil,
             titleAuthorKey: "\(title.lowercased())|", contentHash: UUID().uuidString,
             originalFileName: "\(title).epub", addedAt: Date(timeIntervalSince1970: seconds),
             chapterCount: 0, hasCover: false)
    }
}
