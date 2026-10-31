import Foundation
import ShioriCore
import ZIPFoundation

extension BookImporter {
    func parseEPUB(_ file: URL, in stage: URL, fileName: String) throws -> ParsedBook {
        let archive = try EPUBArchive(url: file)
        if archive.hasDRM { throw ImportFailure.drmProtected }
        let package: EPUBPackage
        do {
            let opfPath = try ContainerParser.rootfilePath(from: try archive.data(at: "META-INF/container.xml"))
            package = try PackageParser.parse(try archive.data(at: opfPath), packagePath: opfPath)
        } catch EPUBError.noSpine {
            throw ImportFailure.noChapters
        }
        if package.metadata.isFixedLayout { throw ImportFailure.fixedLayout }

        let entries = EPUBChapterList.build(spine: package.spine, toc: contents(of: package, in: archive))
        let chapters = entries.map { entry in
            (title: entry.title.isEmpty ? firstHeading(entry.path, in: archive) : entry.title,
             volume: entry.volume, source: entry.path)
        }

        var hasCover = false
        if let coverPath = package.coverPath, let data = try? archive.data(at: coverPath) {
            let ext = (coverPath as NSString).pathExtension.lowercased()
            try data.write(to: stage.appending(path: "cover.\(ext.isEmpty ? "jpg" : ext)"))
            hasCover = true
        }

        let fromName = FileNameMetadata.parse(fileName)
        let title = package.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = package.metadata.creators.first ?? (title.isEmpty ? fromName.author : nil)
        return ParsedBook(title: title.isEmpty ? fromName.title : title, author: author,
                          identifier: BookIdentity.identifierKey(package.metadata.identifier),
                          chapters: chapters, hasCover: hasCover)
    }

    /// The nav document when it parses and lists something, else the NCX.
    private func contents(of package: EPUBPackage, in archive: EPUBArchive) -> [TOCEntry] {
        if let nav = package.navPath, let data = try? archive.data(at: nav),
           let toc = try? TOCParser.nav(data, basePath: nav), !toc.isEmpty {
            return toc
        }
        if let ncx = package.ncxPath, let data = try? archive.data(at: ncx),
           let toc = try? TOCParser.ncx(data, basePath: ncx) {
            return toc
        }
        return []
    }

    private func firstHeading(_ path: String, in archive: EPUBArchive) -> String {
        guard let data = try? archive.data(at: path),
              let blocks = try? XHTMLContentParser.blocks(from: String(decoding: data, as: UTF8.self), documentPath: path)
        else { return "" }
        for case .heading(let text, _) in blocks { return text }
        return ""
    }

    /// Writes the chapters to `folder` inside `bookFolder`. A re-split writes a fresh folder
    /// next to the live one, so the old chapters stay readable until the new rows commit.
    func parseTXT(_ file: URL, into bookFolder: URL, folder: String, fileName: String,
                  options: TXTOptions) throws -> ParsedBook {
        let text = try Self.decodeTXT(try Data(contentsOf: file), encoding: options.encoding)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}\u{FEFF}"))).isEmpty
        else { throw ImportFailure.empty }

        let split = ChapterSplitter.split(text, rules: options.rules)
        let directory = bookFolder.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var chapters: [(title: String, volume: String?, source: String)] = []
        for (index, chapter) in split.enumerated() {
            let source = folder + "/" + String(format: "%05d.txt", index + 1)
            try Data(chapter.body.utf8).write(to: bookFolder.appending(path: source))
            chapters.append((chapter.title, chapter.volume, source))
        }
        let meta = FileNameMetadata.parse(fileName)
        return ParsedBook(title: meta.title, author: meta.author, identifier: nil, chapters: chapters, hasCover: false)
    }

    /// A chosen encoding is tried first; text that isn't valid in it falls back to detection
    /// rather than failing the import.
    static func decodeTXT(_ data: Data, encoding: TXTEncodingChoice) throws -> String {
        let preferred: String.Encoding? = switch encoding {
        case .auto: nil
        case .utf8: .utf8
        case .gb18030: TextDecoding.gb18030
        case .big5: TextDecoding.big5
        case .utf16: utf16ByteOrder(of: data)
        }
        do {
            return try TextDecoding.decode(data, preferred: preferred).text
        } catch is TextDecodingError {
            throw ImportFailure.empty
        }
    }

    /// The BOM's byte order, else the one whose high bytes look like text: zero for ASCII,
    /// 0x30 for CJK punctuation, 0x4E–0x9F for common ideographs, 0xFF for full-width forms.
    /// Low bytes are arbitrary, so the right order scores far higher.
    static func utf16ByteOrder(of data: Data) -> String.Encoding {
        if data.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        func likelyHigh(_ byte: UInt8) -> Bool {
            byte == 0 || byte == 0x30 || (0x4E...0x9F).contains(byte) || byte == 0xFF
        }
        var little = 0
        var big = 0
        data.prefix(1 << 16).withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var i = 0
            while i + 1 < bytes.count {
                if likelyHigh(bytes[i + 1]) { little += 1 }
                if likelyHigh(bytes[i]) { big += 1 }
                i += 2
            }
        }
        return big > little ? .utf16BigEndian : .utf16LittleEndian
    }

    func parsePDF(_ file: URL, in stage: URL, fileName: String) throws -> ParsedBook {
        let info = try PDFImport.read(file)
        var hasCover = false
        if let cover = info.coverJPEG {
            try cover.write(to: stage.appending(path: "cover.jpg"))
            hasCover = true
        }
        let fromName = FileNameMetadata.parse(fileName)
        return ParsedBook(title: info.title ?? fromName.title, author: info.author ?? (info.title == nil ? fromName.author : nil),
                          identifier: nil, chapters: [], hasCover: hasCover)
    }

    /// Imports each book inside, one by one (spec §8.3). Nested archives are skipped, and
    /// anything that isn't a book (images, readmes, macOS's `__MACOSX` forks) is ignored.
    func importZIP(_ url: URL, origin: ImportOrigin, txt: TXTOptions) -> [ImportOutcome] {
        let zipName = url.lastPathComponent
        let fm = FileManager.default
        do {
            guard try Self.fileSize(url) <= Self.zipLimit else {
                return [.failed(fileName: zipName, reason: .tooLarge(limitBytes: Self.zipLimit))]
            }
            let archive = try Archive(url: url, accessMode: .read)
            try paths.prepare()
            let stage = paths.staging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stage) }

            var outcomes: [ImportOutcome] = []
            for (index, entry) in archive.enumerated() where entry.type == .file {
                let components = ZIPNames.path(of: entry).split(whereSeparator: { $0 == "/" || $0 == "\\" })
                guard let last = components.last, !last.hasPrefix("."), !components.contains("__MACOSX") else { continue }
                let name = String(last)
                let ext = (name as NSString).pathExtension.lowercased()
                if ext == "zip" {
                    outcomes.append(.skipped(fileName: name, reason: .nestedArchive))
                    continue
                }
                guard let format = Self.format(forExtension: ext) else { continue }
                // The declared size, so an oversized entry is never extracted at all.
                let limit = Self.limit(for: format)
                guard Int64(clamping: entry.uncompressedSize) <= limit else {
                    outcomes.append(.failed(fileName: name, reason: .tooLarge(limitBytes: limit)))
                    continue
                }
                let file = stage.appending(path: "entry-\(index).\(ext)")
                do {
                    _ = try archive.extract(entry, to: file)
                } catch {
                    Self.log.error("extracting a .\(ext, privacy: .public) from a ZIP failed: \(Self.loggable(error), privacy: .public)")
                    outcomes.append(.failed(fileName: name, reason: .unreadable(Self.loggable(error))))
                    continue
                }
                outcomes.append(importOne(file, fileName: name, origin: origin, txt: txt))
                try? fm.removeItem(at: file)
            }
            return outcomes.isEmpty ? [.failed(fileName: zipName, reason: .unsupportedFormat)] : outcomes
        } catch {
            Self.log.error("opening a ZIP failed: \(Self.loggable(error), privacy: .public)")
            return [.failed(fileName: zipName, reason: .unreadable(Self.loggable(error)))]
        }
    }
}
