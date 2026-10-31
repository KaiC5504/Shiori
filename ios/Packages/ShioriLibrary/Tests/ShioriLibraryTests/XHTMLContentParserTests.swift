import Foundation
import Testing
@testable import ShioriLibrary

@Test func parsesSoNovelChapter() throws {
    let html = """
    <?xml version='1.0' encoding='utf-8'?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN">
    <head><title>第一章</title><link href="style.css" rel="stylesheet" type="text/css"/></head>
    <body><h2>第一章 转职仪式开始</h2><p>　　第一段。</p><p>第二段<br/>同段换行</p></body></html>
    """
    #expect(try XHTMLContentParser.blocks(from: html, documentPath: "EPUB/chapter_1.xhtml") == [
        .heading("第一章 转职仪式开始", level: 2), .paragraph("第一段。"), .paragraph("第二段"), .paragraph("同段换行"),
    ])
}
@Test func tolerantOfEntitiesAndBrokenMarkup() throws {
    let html = "<html><body><p>甲&nbsp;乙<p>丙 &amp; 丁<div><img src=\"../Images/i1.jpg\"></div></body>"
    #expect(try XHTMLContentParser.blocks(from: html, documentPath: "OEBPS/Text/c1.xhtml") == [
        .paragraph("甲 乙"), .paragraph("丙 & 丁"), .image(path: "OEBPS/Images/i1.jpg"),
    ])
}
@Test func hugeChapterParsesQuickly() throws {
    let para = "<p>" + String(repeating: "很长的段落文字。", count: 40) + "</p>"
    let html = "<html><body>" + String(repeating: para, count: 640) + "</body></html>"
    #expect(html.utf8.count > 600_000)
    let start = Date()
    let blocks = try XHTMLContentParser.blocks(from: html, documentPath: "E/c.xhtml")
    #expect(blocks.count == 640)
    #expect(Date().timeIntervalSince(start) < 2.0)
}
@Test func looseTextInlineMarkupAndScriptsAreHandled() throws {
    let html = "<body><div>甲<b>乙</b>丙</div><script>x()</script><section>丁<p>戊</p></section></body>"
    #expect(try XHTMLContentParser.blocks(from: html, documentPath: "E/c.xhtml") == [
        .paragraph("甲乙丙"), .paragraph("丁"), .paragraph("戊"),
    ])
}
