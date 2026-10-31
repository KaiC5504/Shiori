import Foundation
import Testing
@testable import ShioriCore

@Test func containerFindsRootfile() throws {
    let xml = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """
    #expect(try ContainerParser.rootfilePath(from: Data(xml.utf8)) == "EPUB/content.opf")
}
@Test func containerWithoutRootfileThrows() {
    #expect(throws: EPUBError.missingContainer) {
        try ContainerParser.rootfilePath(from: Data("<container/>".utf8))
    }
}
