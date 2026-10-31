#if DEBUG
import PDFKit
import UIKit

/// A generated 12-page PDF with an outline, for the demo library, its screenshots and the
/// PDF reader's UI test. Every word on it is generated filler.
enum DemoPDF {
    static let pageCount = 12

    static func write(to url: URL) throws {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextAuthor as String: author]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let data = renderer.pdfData { context in
            for index in 0..<pageCount {
                context.beginPage()
                draw(page: index, in: context.cgContext)
            }
        }
        // UIGraphicsPDFRenderer can't write an outline, so PDFKit adds it to the rendered file.
        guard let document = PDFDocument(data: data) else { throw CocoaError(.fileWriteUnknown) }
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title,
                                       PDFDocumentAttribute.authorAttribute: author]
        let root = PDFOutline()
        for (n, part) in parts.enumerated() {
            let item = outline(part.title, page: part.page, in: document)
            for (m, child) in part.children.enumerated() {
                item.insertChild(outline(child.title, page: child.page, in: document), at: m)
            }
            root.insertChild(item, at: n)
        }
        document.outlineRoot = root
        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static let title = "纸页样张"
    private static let author = "生成"
    /// A5, in points.
    private static let page = CGRect(x: 0, y: 0, width: 420, height: 595)
    private static let margin = UIEdgeInsets(top: 64, left: 56, bottom: 68, right: 56)

    private struct Part {
        var title: String
        var page: Int
        var children: [(title: String, page: Int)]
    }

    private static let parts: [Part] = [
        Part(title: "扉页", page: 0, children: []),
        Part(title: "第一部分　纸", page: 1, children: [("一　晨光", 1), ("二　书页", 3)]),
        Part(title: "第二部分　墨", page: 5, children: [("三　砚台", 5), ("四　水痕", 7)]),
        Part(title: "第三部分　签", page: 9, children: [("五　标签", 9), ("附　索引", 11)]),
    ]

    /// Pages that carry a drawn plate instead of a full page of text.
    private static let plates: Set<Int> = [4, 8]

    private static func outline(_ label: String, page index: Int, in document: PDFDocument) -> PDFOutline {
        let item = PDFOutline()
        item.label = label
        if let target = document.page(at: index) {
            item.destination = PDFDestination(page: target, at: CGPoint(x: 0, y: target.bounds(for: .cropBox).maxY))
        }
        return item
    }

    private static func draw(page index: Int, in context: CGContext) {
        surface.setFill()
        context.fill(page)
        if index == 0 {
            drawTitlePage()
            return
        }
        let column = page.inset(by: margin)
        drawRunningHead(index, above: column)
        var y = column.minY
        if let part = parts.first(where: { $0.page == index }) {
            y = drawText(part.title, font: .systemFont(ofSize: 20, weight: .semibold), color: ink,
                         at: y, in: column) + 6
        }
        if let section = parts.flatMap(\.children).first(where: { $0.page == index }) {
            y = drawText(section.title, font: .systemFont(ofSize: 15, weight: .medium), color: ink,
                         at: y, in: column) + 14
        }
        if plates.contains(index) {
            y = drawPlate(index, at: y, in: column) + 18
        }
        drawParagraphs(for: index, from: y, in: column)
        drawFolio(index)
    }

    private static func drawTitlePage() {
        let column = page.inset(by: margin)
        let label = NSAttributedString(string: "ARCHIVE / SAMPLE", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium), .kern: 2.4, .foregroundColor: inkSecondary,
        ])
        label.draw(at: CGPoint(x: column.minX, y: column.minY + 120))
        let rule = CGRect(x: column.minX, y: column.minY + 140, width: column.width - 8, height: 0.75)
        line.setFill()
        UIRectFill(rule)
        inkSecondary.setFill()
        UIRectFill(CGRect(x: rule.maxX + 2, y: rule.midY - 2.5, width: 5, height: 5))
        let y = drawText(title, font: .systemFont(ofSize: 32, weight: .bold), color: ink, at: column.minY + 156, in: column)
        _ = drawText("生成文本 · \(pageCount) 页 · 附目录", font: .systemFont(ofSize: 13), color: inkSecondary,
                     at: y + 8, in: column)
        let serial = NSAttributedString(string: "SH-000412", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular), .kern: 1.5, .foregroundColor: inkSecondary,
        ])
        serial.draw(at: CGPoint(x: column.minX, y: column.maxY - 14))
    }

    private static func drawRunningHead(_ index: Int, above column: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular), .kern: 1.2, .foregroundColor: inkSecondary,
        ]
        let left = NSAttributedString(string: title, attributes: attributes)
        left.draw(at: CGPoint(x: column.minX, y: column.minY - 30))
        let right = NSAttributedString(string: String(format: "%02d / %02d", index + 1, pageCount), attributes: attributes)
        right.draw(at: CGPoint(x: column.maxX - right.size().width, y: column.minY - 30))
        line.setFill()
        UIRectFill(CGRect(x: column.minX, y: column.minY - 16, width: column.width, height: 0.5))
    }

    private static func drawFolio(_ index: Int) {
        let folio = NSAttributedString(string: "— \(index + 1) —", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: inkSecondary,
        ])
        let size = folio.size()
        folio.draw(at: CGPoint(x: page.midX - size.width / 2, y: page.maxY - margin.bottom + 24))
    }

    /// A generated print: ridges and a sun in an inked frame, different on each plate page.
    private static func drawPlate(_ index: Int, at y: CGFloat, in column: CGRect) -> CGFloat {
        let frame = CGRect(x: column.minX, y: y, width: column.width, height: column.width * 0.62)
        line.setFill()
        UIRectFill(frame)
        let seed = CGFloat(index)
        for ridge in 0..<4 {
            let path = UIBezierPath()
            let base = frame.maxY - CGFloat(ridge) * frame.height * 0.14
            path.move(to: CGPoint(x: frame.minX, y: frame.maxY))
            for step in 0...24 {
                let x = frame.minX + frame.width * CGFloat(step) / 24
                let wave = sin(CGFloat(step) * 0.55 + seed + CGFloat(ridge) * 1.7) * frame.height * 0.08
                path.addLine(to: CGPoint(x: x, y: base - frame.height * 0.18 + wave))
            }
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
            path.close()
            (ridge.isMultiple(of: 2) ? inkSecondary : ink).withAlphaComponent(0.25 + CGFloat(ridge) * 0.15).setFill()
            path.fill()
        }
        let sun = CGRect(x: frame.minX + frame.width * (0.62 + seed / 100), y: frame.minY + frame.height * 0.16,
                         width: frame.height * 0.22, height: frame.height * 0.22)
        surface.setFill()
        UIBezierPath(ovalIn: sun).fill()
        ink.setStroke()
        let border = UIBezierPath(rect: frame)
        border.lineWidth = 0.75
        border.stroke()
        let caption = index == 4 ? "图一　生成的版画" : "图二　生成的版画"
        return drawText(caption, font: .systemFont(ofSize: 10), color: inkSecondary, at: frame.maxY + 6, in: column)
    }

    /// Whole paragraphs only, as many as fit above the folio.
    private static func drawParagraphs(for index: Int, from top: CGFloat, in column: CGRect) {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 26
        style.lineSpacing = 6
        style.paragraphSpacing = 8
        style.alignment = .justified
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13), .foregroundColor: ink, .paragraphStyle: style,
        ]
        var y = top
        for n in 0..<12 {
            let text = (0..<3).map { filler[(index * 5 + n * 3 + $0) % filler.count] }.joined()
            let paragraph = NSAttributedString(string: text, attributes: attributes)
            let height = paragraph.boundingRect(with: CGSize(width: column.width, height: .greatestFiniteMagnitude),
                                                options: .usesLineFragmentOrigin, context: nil).height.rounded(.up)
            guard y + height <= column.maxY else { break }
            paragraph.draw(with: CGRect(x: column.minX, y: y, width: column.width, height: height),
                           options: .usesLineFragmentOrigin, context: nil)
            y += height + 8
        }
    }

    /// Draws a line of text and returns the y below it.
    private static func drawText(_ text: String, font: UIFont, color: UIColor, at y: CGFloat, in column: CGRect) -> CGFloat {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let height = string.boundingRect(with: CGSize(width: column.width, height: .greatestFiniteMagnitude),
                                         options: .usesLineFragmentOrigin, context: nil).height.rounded(.up)
        string.draw(with: CGRect(x: column.minX, y: y, width: column.width, height: height),
                    options: .usesLineFragmentOrigin, context: nil)
        return y + height
    }

    // The page is printed matter, so it takes the light paper and ink whatever the phone's mode.
    private static let light = UITraitCollection(userInterfaceStyle: .light)
    private static let surface = UIColor(Tokens.surface).resolvedColor(with: light)
    private static let line = UIColor(Tokens.line).resolvedColor(with: light)
    private static let ink = UIColor(Tokens.ink).resolvedColor(with: light)
    private static let inkSecondary = UIColor(Tokens.inkSecondary).resolvedColor(with: light)

    private static let filler = [
        "纸页在灯下微微泛黄，边角留着一道浅浅的折痕。",
        "他把旧信一封封摊开，按日期排好，再用细绳轻轻扎起。",
        "窗外的雨下了一整夜，檐下的水声一直没有停。",
        "墨迹干透以后，字的边缘会晕开一点，像退潮后的沙岸。",
        "档案室里很安静，只听得见翻页时纸张摩擦的声音。",
        "每一张卡片上都写着编号，字迹工整，看得出抄写的人很耐心。",
        "她在书页间夹了一枚书签，记下读到的地方，第二天再接着读。",
        "清晨的光从高窗斜斜地照进来，落在长桌的一角。",
        "有些段落被铅笔轻轻划过，旁边写着几个小字的批注。",
        "装订线已经有些松了，翻到中间时，书脊发出细微的声响。",
        "抽屉里还有一叠没有分类的照片，背面用铅笔写着地名。",
    ]
}
#endif
