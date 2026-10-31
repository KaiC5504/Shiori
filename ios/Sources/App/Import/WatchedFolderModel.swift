import Foundation
import Observation
import ShioriLibrary

/// Stub from wave 1's contracts commit; B2 builds the watched folder (spec §8.1).
@MainActor @Observable
final class WatchedFolderModel {
    var folderName: String?
    var lastScan: Date?
    var lastNewBooks = 0
    var autoImport = true
    var formats: Set<ScanFormat> = Set(ScanFormat.allCases)
    var isScanning = false
    var problem: LocalizedStringResource?
    var usesOwnFolder = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let scanner: FolderScanner

    init(defaults: UserDefaults, scanner: FolderScanner) {
        self.defaults = defaults
        self.scanner = scanner
    }

    func choose(_ folder: URL) {}
    func useOwnFolder() {}
    func disconnect() {}
    func scanNow(settings: ImportSettings) async {}
    func scanOnLaunchIfNeeded(settings: ImportSettings) async {}
}
