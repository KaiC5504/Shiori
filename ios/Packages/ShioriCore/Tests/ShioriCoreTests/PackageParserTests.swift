import Foundation
import Testing
@testable import ShioriCore

let sonovelOPF = """
<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="id" version="3.0">
 <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
  <dc:identifier id="id">trxs-https://www.trxs.cc/tongren/11502/1.html</dc:identifier>
  <dc:title>全民转职：死灵法师！我即是天灾</dc:title>
  <dc:language>zh-CN</dc:language>
  <dc:creator id="creator">慢途的猪</dc:creator>
  <meta name="generator" content="Ebook-lib 0.20.0"/>
  <meta name="cover" content="cover-img"/>
 </metadata>
 <manifest>
  <item href="cover.jpg" id="cover-img" media-type="image/jpeg" properties="cover-image"/>
  <item href="intro.xhtml" id="intro" media-type="application/xhtml+xml"/>
  <item href="chapter_1.xhtml" id="chapter_1" media-type="application/xhtml+xml"/>
  <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
  <item href="nav.xhtml" id="nav" media-type="application/xhtml+xml" properties="nav"/>
 </manifest>
 <spine toc="ncx"><itemref idref="nav" linear="no"/><itemref idref="intro"/><itemref idref="chapter_1"/></spine>
</package>
"""

@Test func parsesSoNovelPackage() throws {
    let pkg = try PackageParser.parse(Data(sonovelOPF.utf8), packagePath: "EPUB/content.opf")
    #expect(pkg.metadata.title == "全民转职：死灵法师！我即是天灾")
    #expect(pkg.metadata.creators == ["慢途的猪"])
    #expect(pkg.metadata.identifier == "trxs-https://www.trxs.cc/tongren/11502/1.html")
    #expect(pkg.metadata.language == "zh-CN")
    #expect(pkg.metadata.isFixedLayout == false)
    #expect(pkg.spine == ["EPUB/intro.xhtml", "EPUB/chapter_1.xhtml"])
    #expect(pkg.coverPath == "EPUB/cover.jpg")
    #expect(pkg.navPath == "EPUB/nav.xhtml")
    #expect(pkg.ncxPath == "EPUB/toc.ncx")
}
@Test func detectsFixedLayout() throws {
    let opf = sonovelOPF.replacingOccurrences(of: "<meta name=\"cover\"",
        with: "<meta property=\"rendition:layout\">pre-paginated</meta><meta name=\"cover\"")
    #expect(try PackageParser.parse(Data(opf.utf8), packagePath: "EPUB/content.opf").metadata.isFixedLayout)
}
@Test func coverFallsBackToMetaCoverWhenNoProperty() throws {
    let opf = sonovelOPF.replacingOccurrences(of: " properties=\"cover-image\"", with: "")
    #expect(try PackageParser.parse(Data(opf.utf8), packagePath: "EPUB/content.opf").coverPath == "EPUB/cover.jpg")
}
@Test func emptySpineThrows() {
    let opf = sonovelOPF.replacingOccurrences(of: #"<itemref idref="intro"/><itemref idref="chapter_1"/>"#, with: "")
    #expect(throws: EPUBError.noSpine) { try PackageParser.parse(Data(opf.utf8), packagePath: "EPUB/content.opf") }
}
