import Foundation

public enum ChapterBlock: Equatable, Sendable {
    case heading(String, level: Int)
    case paragraph(String)
    /// An archive path.
    case image(path: String)

    /// What the block contributes to the chapter's plain text; an image is one object
    /// replacement character so offsets stay stable around it.
    var text: String {
        switch self {
        case .heading(let text, _), .paragraph(let text): text
        case .image: "\u{FFFC}"
        }
    }
}

/// A parsed chapter. Positions are UTF-16 offsets into `plainText`, the blocks' texts
/// joined with "\n", so they survive any change of typography (spec §7.3).
public struct ChapterContent: Equatable, Sendable {
    public var blocks: [ChapterBlock]
    public var plainText: String
    private var starts: [Int]

    public init(blocks: [ChapterBlock]) {
        self.blocks = blocks
        var starts: [Int] = []
        var offset = 0
        for block in blocks {
            starts.append(offset)
            offset += block.text.utf16.count + 1
        }
        self.starts = starts
        self.plainText = blocks.map(\.text).joined(separator: "\n")
    }

    public func offset(ofBlock index: Int) -> Int {
        guard !starts.isEmpty else { return 0 }
        return starts[min(max(index, 0), starts.count - 1)]
    }

    /// The block whose text holds `offset`; the newline after a block belongs to it.
    public func block(containing offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        guard high >= 0 else { return 0 }
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
