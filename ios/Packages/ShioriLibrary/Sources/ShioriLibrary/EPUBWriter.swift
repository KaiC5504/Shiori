import Foundation
import ZIPFoundation

/// Writes EPUBs in the shape SoNovel produces (spec §14): EPUB 3 with both NCX and nav,
/// one `<h2>` plus `<p>` file per chapter. Used for test fixtures and the demo library.
public enum EPUBWriter {
    public struct Book {
        public var title: String
        public var author: String
        public var identifier: String
        public var chapters: [(title: String, volume: String?, paragraphs: [String])]
        public var coverJPEG: Data?
        public var fixedLayout: Bool = false
        public var encrypted: Bool = false

        public init(title: String, author: String, identifier: String,
                    chapters: [(title: String, volume: String?, paragraphs: [String])],
                    coverJPEG: Data?, fixedLayout: Bool = false, encrypted: Bool = false) {
            self.title = title
            self.author = author
            self.identifier = identifier
            self.chapters = chapters
            self.coverJPEG = coverJPEG
            self.fixedLayout = fixedLayout
            self.encrypted = encrypted
        }
    }

    public static func write(_ book: Book, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)
        // Readers find the type from the first entry, which must be stored uncompressed.
        try add("mimetype", Data("application/epub+zip".utf8), to: archive, compressed: false)
        try add("META-INF/container.xml", Data(container.utf8), to: archive)
        if book.encrypted {
            try add("META-INF/encryption.xml", Data(encryption.utf8), to: archive)
        }
        try add("EPUB/content.opf", Data(opf(book).utf8), to: archive)
        try add("EPUB/toc.ncx", Data(ncx(book).utf8), to: archive)
        try add("EPUB/nav.xhtml", Data(nav(book).utf8), to: archive)
        if let cover = book.coverJPEG {
            try add("EPUB/cover.jpg", cover, to: archive, compressed: false)
        }
        for (i, chapter) in book.chapters.enumerated() {
            let paragraphs = chapter.paragraphs.map { "<p>\(escape($0))</p>" }.joined()
            let html = """
            <?xml version='1.0' encoding='utf-8'?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN"><head><title>\(escape(chapter.title))</title></head>
            <body><h2>\(escape(chapter.title))</h2>\(paragraphs)</body></html>
            """
            try add("EPUB/chapter_\(i + 1).xhtml", Data(html.utf8), to: archive)
        }
    }

    private static func add(_ path: String, _ data: Data, to archive: Archive, compressed: Bool = true) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: compressed ? .deflate : .none) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let container = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """

    private static let encryption = """
    <?xml version="1.0" encoding="UTF-8"?>
    <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
      <enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
      <enc:CipherData><enc:CipherReference URI="EPUB/chapter_1.xhtml"/></enc:CipherData></enc:EncryptedData>
    </encryption>
    """

    private static func opf(_ book: Book) -> String {
        var manifest = """
        <item href="nav.xhtml" id="nav" media-type="application/xhtml+xml" properties="nav"/>
        <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
        """
        if book.coverJPEG != nil {
            manifest += #"<item href="cover.jpg" id="cover-img" media-type="image/jpeg" properties="cover-image"/>"#
        }
        var spine = #"<itemref idref="nav" linear="no"/>"#
        for i in book.chapters.indices {
            manifest += #"<item href="chapter_\#(i + 1).xhtml" id="chapter_\#(i + 1)" media-type="application/xhtml+xml"/>"#
            spine += #"<itemref idref="chapter_\#(i + 1)"/>"#
        }
        let layout = book.fixedLayout ? #"<meta property="rendition:layout">pre-paginated</meta>"# : ""
        let cover = book.coverJPEG != nil ? #"<meta name="cover" content="cover-img"/>"# : ""
        return """
        <?xml version='1.0' encoding='utf-8'?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="id" version="3.0">
         <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
          <dc:identifier id="id">\(escape(book.identifier))</dc:identifier>
          <dc:title>\(escape(book.title))</dc:title>
          <dc:language>zh-CN</dc:language>
          <dc:creator id="creator">\(escape(book.author))</dc:creator>
          <meta name="generator" content="Shiori EPUBWriter"/>\(layout)\(cover)
         </metadata>
         <manifest>\(manifest)</manifest>
         <spine toc="ncx">\(spine)</spine>
        </package>
        """
    }

    /// Consecutive chapters with the same volume, so volumes nest in the contents.
    private static func groups(_ book: Book) -> [(volume: String?, chapters: [(index: Int, title: String)])] {
        var groups: [(volume: String?, chapters: [(index: Int, title: String)])] = []
        for (i, chapter) in book.chapters.enumerated() {
            if let last = groups.last, last.volume == chapter.volume, chapter.volume != nil {
                groups[groups.count - 1].chapters.append((i, chapter.title))
            } else {
                groups.append((chapter.volume, [(i, chapter.title)]))
            }
        }
        return groups
    }

    private static func ncx(_ book: Book) -> String {
        var order = 0
        func point(_ title: String, _ index: Int, _ inner: String = "") -> String {
            order += 1
            return #"<navPoint id="p\#(order)" playOrder="\#(order)"><navLabel><text>\#(escape(title))</text></navLabel><content src="chapter_\#(index + 1).xhtml"/>\#(inner)</navPoint>"#
        }
        var map = ""
        for group in groups(book) {
            if let volume = group.volume, let first = group.chapters.first {
                order += 1
                let volumeOrder = order
                let inner = group.chapters.map { point($0.title, $0.index) }.joined()
                map += #"<navPoint id="v\#(volumeOrder)" playOrder="\#(volumeOrder)"><navLabel><text>\#(escape(volume))</text></navLabel><content src="chapter_\#(first.index + 1).xhtml"/>\#(inner)</navPoint>"#
            } else {
                map += group.chapters.map { point($0.title, $0.index) }.joined()
            }
        }
        return """
        <?xml version='1.0' encoding='utf-8'?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <head><meta name="dtb:uid" content="\(escape(book.identifier))"/></head>
        <docTitle><text>\(escape(book.title))</text></docTitle>
        <navMap>\(map)</navMap></ncx>
        """
    }

    private static func nav(_ book: Book) -> String {
        func item(_ title: String, _ index: Int) -> String {
            #"<li><a href="chapter_\#(index + 1).xhtml">\#(escape(title))</a></li>"#
        }
        var list = ""
        for group in groups(book) {
            if let volume = group.volume {
                list += "<li><span>\(escape(volume))</span><ol>\(group.chapters.map { item($0.title, $0.index) }.joined())</ol></li>"
            } else {
                list += group.chapters.map { item($0.title, $0.index) }.joined()
            }
        }
        return """
        <?xml version='1.0' encoding='utf-8'?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>\(escape(book.title))</title></head>
        <body><nav epub:type="toc" id="id"><h2>\(escape(book.title))</h2><ol>\(list)</ol></nav></body></html>
        """
    }
}
