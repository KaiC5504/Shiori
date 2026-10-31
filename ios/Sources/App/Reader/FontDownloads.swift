import CoreText
import Foundation
import Observation

/// Apple's downloadable fonts (spec §7.4). They are fetched from Apple only when the reader
/// picks one (the one network exception, spec §12). Core Text registers a downloaded font for
/// this process only, so a font downloaded on an earlier launch has to be matched again
/// before it draws; that finds it on the phone and never downloads.
@MainActor @Observable
final class FontDownloads {
    static let shared = FontDownloads()

    /// Family name to 0...1, while it downloads.
    private(set) var progress: [String: Double] = [:]
    private(set) var failed: Set<String> = []
    /// Families made usable since launch; reading it lets rows redraw in their own face.
    private(set) var registered: Set<String> = []

    /// Only the newest tap selects when its download lands, so a slow one can't override it.
    @ObservationIgnored private var latestRequest: String?
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let downloadedKey = "reader.downloadedFonts"

    func isAvailable(_ family: String) -> Bool {
        registered.contains(family) || Self.installed(family)
    }

    /// Selects `family` now if it's on the phone, else downloads it and selects it when done.
    /// `nil` is the system font.
    func choose(_ family: String?, select: @escaping (String?) -> Void) {
        latestRequest = family
        guard let family else {
            select(nil)
            return
        }
        if isAvailable(family) {
            select(family)
            return
        }
        guard progress[family] == nil else { return }
        failed.remove(family)
        progress[family] = 0
        Task {
            let matched = await match(family, allowsDownload: true)
            progress[family] = nil
            guard matched else {
                failed.insert(family)
                return
            }
            remember(family)
            registered.insert(family)
            if latestRequest == family { select(family) }
        }
    }

    /// Registers a font this app downloaded on an earlier launch. A font the system has since
    /// removed is forgotten rather than downloaded again unasked.
    func activate(_ family: String?) async {
        guard let family, !isAvailable(family), downloaded.contains(family) else { return }
        if await match(family, allowsDownload: false) {
            registered.insert(family)
        } else {
            forget(family)
        }
    }

    private var downloaded: Set<String> {
        Set(defaults.stringArray(forKey: Self.downloadedKey) ?? [])
    }

    private func remember(_ family: String) {
        defaults.set(Array(downloaded.union([family])).sorted(), forKey: Self.downloadedKey)
    }

    private func forget(_ family: String) {
        defaults.set(Array(downloaded.subtracting([family])).sorted(), forKey: Self.downloadedKey)
    }

    private func match(_ family: String, allowsDownload: Bool) async -> Bool {
        for await fraction in Self.matching(family, allowsDownload: allowsDownload) where progress[family] != nil {
            progress[family] = fraction
        }
        return Self.installed(family)
    }

    /// Yields download progress as 0...1 and finishes when Core Text is done.
    private nonisolated static func matching(_ family: String, allowsDownload: Bool) -> AsyncStream<Double> {
        AsyncStream { continuation in
            let descriptor = CTFontDescriptorCreateWithAttributes(
                [kCTFontFamilyNameAttribute as String: family] as CFDictionary)
            // Called on Core Text's own queue, so it must not inherit the main actor.
            let started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler(
                [descriptor] as CFArray, nil
            ) { @Sendable state, info in
                switch state {
                case .willBeginDownloading where !allowsDownload:
                    continuation.finish()
                    return false
                case .downloading:
                    let percent = (info as NSDictionary)[kCTFontDescriptorMatchingPercentage as String] as? Double
                    if let percent { continuation.yield(min(max(percent / 100, 0), 1)) }
                case .didFailWithError, .didFinish:
                    continuation.finish()
                default:
                    break
                }
                return true
            }
            if !started { continuation.finish() }
        }
    }

    /// Core Text substitutes another font for a missing family rather than failing.
    nonisolated static func installed(_ family: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute as String: family] as CFDictionary)
        return CTFontCopyFamilyName(CTFontCreateWithFontDescriptor(descriptor, 17, nil)) as String == family
    }
}
