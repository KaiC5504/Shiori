import Foundation

public enum ScanFormat: String, Codable, CaseIterable, Sendable {
    case epub, txt, pdf, zip
}

public struct ScanSummary: Sendable {
    public var outcomes: [ImportOutcome]
    public var newBooks: Int
    public var date: Date

    public init(outcomes: [ImportOutcome], newBooks: Int, date: Date) {
        self.outcomes = outcomes
        self.newBooks = newBooks
        self.date = date
    }
}

/// Imports what's new in the watched folder (spec §8.1).
public actor FolderScanner {
    private let database: LibraryDatabase
    private let importer: BookImporter

    public init(database: LibraryDatabase, importer: BookImporter) {
        self.database = database
        self.importer = importer
    }

    public func scan(folder: URL, formats: Set<ScanFormat>, settings: ImportSettings) async throws -> ScanSummary {
        ScanSummary(outcomes: [], newBooks: 0, date: Date())
    }
}
