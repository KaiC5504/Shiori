import Foundation
import Testing
@testable import ShioriCore

@Test func parsesNestedNCX() throws {
    let ncx = """
    <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><navMap>
     <navPoint id="n1" playOrder="1"><navLabel><text>简介</text></navLabel><content src="intro.xhtml"/></navPoint>
     <navPoint id="n2" playOrder="2"><navLabel><text>第一卷 起始</text></navLabel><content src="chapter_1.xhtml"/>
       <navPoint id="n3" playOrder="3"><navLabel><text>第一章 转职仪式开始</text></navLabel><content src="chapter_1.xhtml#c1"/></navPoint>
     </navPoint>
    </navMap></ncx>
    """
    let toc = try TOCParser.ncx(Data(ncx.utf8), basePath: "EPUB/toc.ncx")
    #expect(toc.map(\.title) == ["简介", "第一卷 起始"])
    let child = try #require(toc[1].children.first)
    #expect(child.title == "第一章 转职仪式开始")
    #expect(child.path == "EPUB/chapter_1.xhtml")
    #expect(child.fragment == "c1")
}
@Test func parsesNav() throws {
    let nav = """
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
    <nav epub:type="landmarks"><ol><li><a href="cover.xhtml">Cover</a></li></ol></nav>
    <nav epub:type="toc"><ol>
      <li><a href="intro.xhtml">简介</a></li>
      <li><span>第一卷</span><ol><li><a href="c1.xhtml">第一章</a></li></ol></li>
    </ol></nav></body></html>
    """
    let toc = try TOCParser.nav(Data(nav.utf8), basePath: "EPUB/nav.xhtml")
    #expect(toc.map(\.title) == ["简介", "第一卷"])
    #expect(toc[1].path == "")
    #expect(toc[1].children.map(\.path) == ["EPUB/c1.xhtml"])
}
