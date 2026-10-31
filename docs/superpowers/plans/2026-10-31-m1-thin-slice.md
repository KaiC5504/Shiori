# M1: Thin Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship TestFlight build 1 of Shiori. It imports EPUB and TXT files from the Files
picker into a plain shelf list, reads them in a scroll layout, and remembers the reading
position, all inside the final full-width floating bar.

**Architecture:**

- **App:** a SwiftUI app target (`ios/Sources/App`) over two local Swift packages.
- **`ShioriCore`:** pure Swift with no dependencies. It holds the EPUB package and
  contents parsing, TXT chapter splitting, chapter keys and book identity. It builds and
  tests on Windows.
- **`ShioriLibrary`:** Apple-only. It holds storage, the GRDB database, TXT decoding, ZIP
  access, XHTML-to-content parsing and the importer. It is tested on the macOS CI runner.
- **Pipeline:** GitHub Actions runs the package tests, builds the app and screenshots it
  on an iPhone 17 Pro Max simulator. TestFlight ships it.

**Tech Stack:** Swift 6.4 toolchain in Swift 5 language mode, SwiftUI (iOS 26.0 minimum),
Swift Testing, XcodeGen, GRDB.swift 7.11.1, ZIPFoundation 0.9.20, SwiftSoup 2.14.3,
GitHub Actions (`xcode-27` image, Xcode 27.1), and the `ios-testflight` skill pipeline.

**Spec:** `docs/superpowers/specs/2026-10-31-shiori-design.md`. Roadmap: `docs/roadmap.md`
(this is M1).

## Global Constraints

- iOS deployment target `26.0`; iPhone only (`TARGETED_DEVICE_FAMILY: "1"`). App screens
  are portrait-only. M1's reader is portrait-only too, since rotation arrives in M4b.
- Build with Xcode 27.1 on `runs-on: xcode-27`. If it queues for more than about 10
  minutes repeatedly, switch both workflows to `macos-26` with Xcode 26.6 and say so in
  the commit message.
- `SWIFT_VERSION: "5.0"` and `swiftLanguageModes: [.v5]`. XcodeGen only, with no
  project-level xcconfig (`configFiles:`).
- App and scheme `Shiori`, bundle id `com.kaichuan.shiori`, display name `Shiori` in
  every language.
- The only third-party packages are GRDB.swift (`from: "7.11.1"`), ZIPFoundation
  (`from: "0.9.20"`) and SwiftSoup (`from: "2.14.3"`), all MIT. List them in
  `docs/THIRD_PARTY.md`.
- No network requests and no analytics or crash SDKs.
- Every user-facing string lives in `ios/Sources/App/Resources/Localizable.xcstrings`,
  with English as the source language and a Simplified Chinese (`zh-Hans`) translation.
  No string literal is shown untranslated.
- Never hard-code the 17 Pro Max width (440 pt). Lay out from the available size.
- **Clean-room:** never open, translate or copy code from
  `D:\Repos\Apps\Wenku8_Flutter`, `KaiC5504/Shiori-Flutter` or
  `mikufoxxx/Wenku8_Flutter`. DailyStore (`D:\Repos\Apps\DailyStore`) is KaiC's own
  code and may be reused.
- Test fixtures use public-domain text only, e.g. 《桃花源记》, 《岳阳楼记》, 《兰亭集序》,
  or generated text. KaiC's test book never enters the repo.
- Comments follow the global rule: write the why, not the what.
- **Branches:** GitHub holds only `main`. Work on the local branch `dev`, which is never
  pushed.
- **"Ship" in this plan** means the only way anything reaches GitHub:
  1. Commit on `dev`.
  2. Run `git checkout main && git merge --ff-only dev && git push origin main && git checkout dev`.

  Every push to `main` runs the compile check.
- **Never ship a commit you expect to fail.** Ship only when local checks pass
  (`swift test` for ShioriCore, `bash tools/check-app.sh` once Task 2 exists). If CI goes
  red, fix it on `dev` and ship again.

## Review Focus

Failure modes the spec implies that ordinary feature tests would miss. Each has a test in
the owning task.

1. **Messy chapter markup:** real chapter XHTML often has HTML entities (`&nbsp;`) and
   tags that aren't well-formed. A strict XML parser drops such a chapter or throws. The
   expected behaviour is to read it leniently. Test in Task 10.
2. **A huge single chapter:** the test book's largest chapter file is 555 KB. Parsing must
   stay fast and the reader must not freeze. Test in Task 10 (a 600 KB chapter); reader
   behaviour is checked on the phone in Task 16.
3. **Double import:** tapping Import twice, or picking the same file twice in one batch,
   races the deduplication. Exactly one book must be added. Test in Task 11.
4. **Interrupted import:** a crash or kill mid-import leaves a half-written book folder,
   which must never become a broken shelf entry. Failed imports must leave no files, and
   leftover staging is cleaned on launch. Tests in Task 11.
5. **Windows TXT files:** `\r\n` line endings, full-width indents (`　　`) and a BOM must
   not leak into titles or paragraphs. Tests in Tasks 6 and 9.

## File Structure

```
.github/workflows/ios-compile.yml     compile check: package tests, build, launch, screenshots
.github/workflows/testflight.yml      signed build (from the ios-testflight skill template)
scripts/testflight.py, scripts/testflight-requirements.txt
tools/check-app.sh, tools/check-app.ps1, tools/app-check/{Package.swift,README.md,setup-wsl.sh}
ios/project.yml
ios/Packages/ShioriCore/
  Package.swift
  Sources/ShioriCore/
    XMLSupport.swift          FoundationXML import shim plus a small DOM-less parser helper
    EPUBPath.swift            href resolution and fragment split
    EPUBModels.swift          EPUBMetadata, EPUBPackage, TOCEntry, ChapterEntry, EPUBError
    ContainerParser.swift
    PackageParser.swift
    TOCParser.swift           NCX and nav
    EPUBChapterList.swift     spine plus TOC to chapter entries
    ChapterRule.swift         TXT heading rules and presets
    ChapterSplitter.swift
    ChapterKey.swift          stable chapter keys
    BookIdentity.swift        identifier key and title/author key
    FileNameMetadata.swift    "书名(作者).txt" parsing
    TitleNormalizer.swift     shared normalisation (NFKC, whitespace, case)
  Tests/ShioriCoreTests/      one file per source file above
ios/Packages/ShioriLibrary/
  Package.swift
  Sources/ShioriLibrary/
    LibraryPaths.swift
    LibraryDatabase.swift     DatabaseQueue plus migrator v1 plus queries
    Records.swift             Book, Chapter, Progress, BookFormat, BookListItem
    TextDecoding.swift
    EPUBArchive.swift         ZIPFoundation reader
    EPUBWriter.swift          writes EPUBs (fixtures and demo books)
    ChapterContent.swift      ChapterBlock, ChapterContent, offset mapping
    XHTMLContentParser.swift  SwiftSoup
    BookContentSource.swift   loads a chapter's content for EPUB and TXT
    BookImporter.swift        actor: copy, hash, dedupe, parse, insert
    ImportOutcome.swift
    DemoBooks.swift           public-domain demo files for Debug demo mode
  Tests/ShioriLibraryTests/
ios/Sources/App/
  ShioriApp.swift
  AppModel.swift
  DemoLaunch.swift            #if DEBUG launch-argument handling
  Design/Tokens.swift         M1 paper/ink colours (full system in M2)
  Shell/AppTab.swift
  Shell/RootView.swift
  Shell/ShioriTabBar.swift
  Shelf/ShelfView.swift
  Import/ImportView.swift
  Settings/SettingsView.swift
  Reader/ReaderView.swift
  Reader/ReaderModel.swift
  Reader/ContentsSheet.swift
  Resources/Assets.xcassets/AppIcon.appiconset/   from branding/AppIcon.appiconset
  Resources/Localizable.xcstrings
  Resources/PrivacyInfo.xcprivacy
docs/THIRD_PARTY.md
```

---

### Task 1: Project skeleton and compile check

**Files:**
- Create: `ios/project.yml`, `ios/Sources/App/ShioriApp.swift`,
  `ios/Sources/App/Shell/RootView.swift`,
  `ios/Sources/App/Resources/Assets.xcassets/` (with
  `AppIcon.appiconset/` copied from `branding/AppIcon.appiconset/` plus the catalog's
  root `Contents.json`), `ios/Sources/App/Resources/Localizable.xcstrings`,
  `ios/Sources/App/Resources/PrivacyInfo.xcprivacy`, `.github/workflows/ios-compile.yml`.

**Interfaces:**
- Produces: the `Shiori` target and scheme, and the `simulator-screenshots` artifact
  with `01-first-launch.png`.

- [ ] **Step 1: Write `ios/project.yml`** from the `ios-testflight` skill's
  `templates/project.yml`, with `__APP__` = `Shiori` and `__BUNDLE_ID__` =
  `com.kaichuan.shiori`. Also:
  - `packages:` `ShioriCore` (`path: Packages/ShioriCore`) and `ShioriLibrary`
    (`path: Packages/ShioriLibrary`), with both as target dependencies.
    (Both packages are created in Tasks 3 and 8. Until then, comment the two package
    entries out and uncomment them in those tasks.)
  - `sources: - path: Sources/App`.
  - Info properties: `CFBundleDevelopmentRegion: en`,
    `CFBundleLocalizations: [en, zh-Hans]`, `UIFileSharingEnabled: true`,
    `LSSupportsOpeningDocumentsInPlace: true` (the Documents folder shows in Files for
    M3), portrait only.
- [ ] **Step 2: Write the stub app.** `ShioriApp` shows `RootView`, and `RootView` shows
  `Text("Shiori")` on the paper colour `#F2ECE3`.
- [ ] **Step 3: Write `PrivacyInfo.xcprivacy`.** Declare `NSPrivacyAccessedAPICategoryUserDefaults`
  with reason `CA92.1` and `NSPrivacyAccessedAPICategoryFileTimestamp` with reason
  `C617.1`; `NSPrivacyTracking` false; no collected data types.
- [ ] **Step 4: Write `ios-compile.yml`** from the skill's `templates/ios-compile.yml`, with
  these changes:
  - `on: push` (branch `main`; `paths`: `ios/**` and the workflow file) plus
    `workflow_dispatch`.
  - `runs-on: xcode-27`. The Toolchain step runs
    `sudo xcode-select -s /Applications/Xcode_27.1.app` and `xcodebuild -version`.
  - `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1) and
    `actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9` (v7.0.2).
  - Simulator choice: the device named exactly `iPhone 17 Pro Max` on the newest iOS
    runtime. If there isn't one, fall back to the last available iPhone and print a
    warning.
  - `__APP__` = `Shiori` and `__BUNDLE_ID__` = `com.kaichuan.shiori` throughout.
- [ ] **Step 5: Commit and ship.**
  ```bash
  git add ios .github && git commit -m "Add the Shiori project skeleton and compile check"
  git checkout main && git merge --ff-only dev && git push origin main && git checkout dev
  ```
- [ ] **Step 6: Verify.** Run `gh run watch <id> --exit-status` on the newest run
  (`gh run list --branch main --limit 1`). Expected: green. Then download it:
  `gh run download <id> -n simulator-screenshots -D <scratch>`. Expected:
  `01-first-launch.png` shows "Shiori" on cream paper on a 1320 × 2868 screenshot (the
  17 Pro Max).

### Task 2: Local compile tool

**Files:**
- Create: `tools/check-app.sh`, `tools/check-app.ps1`, `tools/app-check/Package.swift`,
  `tools/app-check/README.md`, `tools/app-check/setup-wsl.sh`, all adapted from
  `D:\Repos\Apps\DailyStore\tools\` (KaiC's own code).

**Interfaces:**
- Produces: `bash tools/check-app.sh`, which compiles `ios/Sources/App` against the iOS
  27.1 SDK in WSL in about 15 s. It prints errors with repo-relative paths.

- [ ] **Step 1: Copy DailyStore's tool and adapt it.**
  - Change the marker file to `ios/Packages/ShioriCore/Package.swift`.
  - There is one app target, `Shiori`, from `ios/Sources/App`, with no widget and no
    `Shared` folder.
  - Stage `ios/Packages/ShioriCore` and `ios/Packages/ShioriLibrary`.
  - The `app-check/Package.swift` mirrors the app target's dependencies, including GRDB,
    ZIPFoundation and SwiftSoup at the versions in Global Constraints.
  - The stage directory is `~/.cache/shiori-check/`.
  - The `sed` path rewrite maps staged paths back to `ios/Sources/App/` and
    `ios/Packages/<name>/`.
- [ ] **Step 2: Rewrite the README** for Shiori. KaiC's PC already has the WSL install
  from DailyStore and BiliNative, so the setup steps stay "only on a new PC".
- [ ] **Step 3: Run `bash tools/check-app.sh`.** Expected: it ends in success for the stub
  app.
- [ ] **Step 4: Commit.**
  ```bash
  git add tools && git commit -m "Add the local WSL compile check"
  ```

### Task 3: ShioriCore package, EPUB paths and container

**Files:**
- Create: `ios/Packages/ShioriCore/Package.swift`,
  `Sources/ShioriCore/{XMLSupport,EPUBPath,EPUBModels,ContainerParser}.swift`,
  `Tests/ShioriCoreTests/{EPUBPathTests,ContainerParserTests}.swift`.
- Modify: `ios/project.yml` (uncomment the `ShioriCore` package),
  `.github/workflows/ios-compile.yml` (add the step
  `swift test --package-path ios/Packages/ShioriCore` before XcodeGen).

**Interfaces:**
- Produces:
  - `enum EPUBPath { static func resolve(_ href: String, relativeTo documentPath: String) -> String; static func split(_ href: String) -> (path: String, fragment: String?) }`
    `resolve` percent-decodes, drops any fragment, and normalises `.` and `..`.
  - `enum EPUBError: Error, Equatable { case missingContainer, malformedPackage(String), noSpine }`.
  - `enum ContainerParser { static func rootfilePath(from data: Data) throws -> String }`.
  - `XMLSupport.swift`: `#if canImport(FoundationXML) import FoundationXML #endif`, so
    `XMLParser` compiles on Windows.

- [ ] **Step 1: Write `Package.swift`.** Use swift-tools 6.2, name `ShioriCore`, platforms
  `[.iOS(.v26), .macOS(.v14)]`, `swiftLanguageModes: [.v5]`, no dependencies.
- [ ] **Step 2: Write the failing tests.**

```swift
import Foundation
import Testing
@testable import ShioriCore

@Test func resolvesSiblingHref() {
    #expect(EPUBPath.resolve("chapter_1.xhtml", relativeTo: "EPUB/content.opf") == "EPUB/chapter_1.xhtml")
}
@Test func resolvesParentAndPercentEncoding() {
    #expect(EPUBPath.resolve("../Images/a%20b.jpg", relativeTo: "OEBPS/Text/c1.xhtml") == "OEBPS/Images/a b.jpg")
}
@Test func resolveDropsFragment() {
    #expect(EPUBPath.resolve("c1.xhtml#p3", relativeTo: "OEBPS/toc.ncx") == "OEBPS/c1.xhtml")
}
@Test func splitsFragment() {
    let parts = EPUBPath.split("c1.xhtml#p3")
    #expect(parts.path == "c1.xhtml" && parts.fragment == "p3")
}
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
```

- [ ] **Step 3: Run the tests on Windows.**
  `cd ios/Packages/ShioriCore && swift test 2>&1 | grep -E "✘|Test run with"`. Expected:
  a FAIL listing undefined symbols.
- [ ] **Step 4: Implement** `EPUBPath`, `EPUBError` and `ContainerParser` (`XMLParser`
  with a delegate, taking the first `rootfile@full-path`).
- [ ] **Step 5: Run the tests.** Same command. Expected: "Test run with 6 tests passed".
- [ ] **Step 6: Commit, ship, and check CI is green.** CI now runs the ShioriCore tests.
  ```bash
  git add ios .github && git commit -m "Add ShioriCore with EPUB path and container parsing"
  git checkout main && git merge --ff-only dev && git push origin main && git checkout dev
  ```

### Task 4: OPF package parsing

**Files:**
- Create: `Sources/ShioriCore/PackageParser.swift`; extend `EPUBModels.swift`; add
  `Tests/ShioriCoreTests/PackageParserTests.swift`.

**Interfaces:**
- Produces:
  - `struct EPUBMetadata: Equatable, Sendable { var title: String; var creators: [String]; var identifier: String?; var language: String?; var isFixedLayout: Bool }`
  - `struct EPUBPackage: Equatable, Sendable { var metadata: EPUBMetadata; var spine: [String]; var coverPath: String?; var navPath: String?; var ncxPath: String? }`
    `spine` holds resolved archive paths of linear items only.
  - `enum PackageParser { static func parse(_ data: Data, packagePath: String) throws -> EPUBPackage }`

- [ ] **Step 1: Write the failing tests.** The fixture mirrors the test book's real OPF
  (spec §14).

```swift
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
```

- [ ] **Step 2: Run the tests.** Expected: FAIL (`PackageParser` undefined).
- [ ] **Step 3: Implement `PackageParser.parse`.**
  - **Identifier:** the `dc:identifier` whose `id` equals `package@unique-identifier`,
    else the first one.
  - **Cover:** the manifest item with property `cover-image`, else the item named by
    `<meta name="cover">`.
  - **Nav:** the item with property `nav`. **NCX:** `spine@toc`, else the item with
    media type `application/x-dtbncx+xml`.
  - **Spine:** drop `linear="no"` items. An empty result throws `.noSpine`.
- [ ] **Step 4: Run the tests.** Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -am "Parse EPUB package metadata, spine and cover"`
  (after `git add` of the new files).

### Task 5: Contents (NCX and nav) and the chapter list

**Files:**
- Create: `Sources/ShioriCore/TOCParser.swift` and
  `Sources/ShioriCore/EPUBChapterList.swift`; add `TOCEntry` and `ChapterEntry` to
  `EPUBModels.swift`; add tests `TOCParserTests.swift` and `EPUBChapterListTests.swift`.

**Interfaces:**
- Produces:
  - `struct TOCEntry: Equatable, Sendable { var title: String; var path: String; var fragment: String?; var children: [TOCEntry] }`
  - `enum TOCParser { static func ncx(_ data: Data, basePath: String) throws -> [TOCEntry]; static func nav(_ data: Data, basePath: String) throws -> [TOCEntry] }`
  - `struct ChapterEntry: Equatable, Sendable { var index: Int; var path: String; var title: String; var volume: String? }`
  - `enum EPUBChapterList { static func build(spine: [String], toc: [TOCEntry]) -> [ChapterEntry] }`

- [ ] **Step 1: Write the failing tests.**

```swift
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
@Test func chapterListUsesDeepestTitleAndVolume() {
    let toc = [
        TOCEntry(title: "简介", path: "E/intro.xhtml", fragment: nil, children: []),
        TOCEntry(title: "第一卷", path: "E/c1.xhtml", fragment: nil, children: [
            TOCEntry(title: "第一章", path: "E/c1.xhtml", fragment: nil, children: []),
            TOCEntry(title: "第二章", path: "E/c2.xhtml", fragment: nil, children: []),
        ]),
    ]
    let chapters = EPUBChapterList.build(spine: ["E/intro.xhtml", "E/c1.xhtml", "E/c2.xhtml", "E/c3.xhtml"], toc: toc)
    #expect(chapters.map(\.title) == ["简介", "第一章", "第二章", ""])
    #expect(chapters.map(\.volume) == [nil, "第一卷", "第一卷", "第一卷"])
    #expect(chapters.map(\.index) == [0, 1, 2, 3])
}
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **`nav`:** use only the `nav` whose `epub:type` contains `toc`. A `span` heading
    gives an entry with an empty path.
  - **`build`:** a spine item's title comes from the deepest TOC entry pointing at its
    path; at equal depth, the first in reading order wins. Its volume is the title of the
    top-level entry when the match is nested.
  - **Untitled spine items:** they get `""` and inherit the previous item's volume. The
    importer fills their title (Task 11).
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "Parse EPUB contents and build the chapter list"`

### Task 6: TXT chapter splitting

**Files:**
- Create: `Sources/ShioriCore/ChapterRule.swift`, `Sources/ShioriCore/ChapterSplitter.swift`,
  `Tests/ShioriCoreTests/ChapterSplitterTests.swift`.

**Interfaces:**
- Produces:
  - `struct ChapterRule: Codable, Hashable, Sendable { var id: String; var pattern: String; var isVolume: Bool }`
    with `static let presets: [ChapterRule]`. The ids are `zh-chapter`, `zh-volume`,
    `en-chapter` and `numbered`.
  - `struct TextChapter: Equatable, Sendable { var title: String; var volume: String?; var body: String }`
    `body` excludes the heading line; lines are trimmed, empty lines dropped, joined with
    `\n`.
  - `enum ChapterSplitter { static func split(_ text: String, rules: [ChapterRule], fallbackLength: Int = 20_000) -> [TextChapter] }`

**Preset patterns** (line-anchored; a heading is the whole trimmed line):

| id | pattern |
| --- | --- |
| `zh-chapter` | `^第[0-9０-９零〇一二两三四五六七八九十百千万]+[章回节话集].{0,40}$` |
| `zh-volume` | `^第[0-9０-９零〇一二两三四五六七八九十百千万]+[卷部].{0,40}$` (isVolume) |
| `en-chapter` | `^(?i:chapter)\s*\d+.{0,60}$` |
| `numbered` | `^\d{1,5}[.、．]\s*\S.{0,40}$` |

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func splitsChineseChaptersWithPreface() {
    let text = "序言内容\n第一章 开始\n正文一\n第二章 继续\n正文二\n"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["", "第一章 开始", "第二章 继续"])
    #expect(ch.map(\.body) == ["序言内容", "正文一", "正文二"])
}
@Test func volumesTagFollowingChapters() {
    let text = "第一卷 风起\n第一章 甲\n内容\n第二卷 云涌\n第二章 乙\n内容"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第一章 甲", "第二章 乙"])
    #expect(ch.map(\.volume) == ["第一卷 风起", "第二卷 云涌"])
}
@Test func handlesCRLFIndentsAndFullWidthDigits() {
    let text = "\u{FEFF}第１２章　标题\r\n　　第一段\r\n\r\n　　第二段\r\n"
    let ch = ChapterSplitter.split(text, rules: ChapterRule.presets)
    #expect(ch.map(\.title) == ["第１２章　标题"])
    #expect(ch.first?.body == "第一段\n第二段")
}
@Test func englishAndNumberedHeadings() {
    #expect(ChapterSplitter.split("Chapter 3: The Road\nText", rules: ChapterRule.presets).map(\.title) == ["Chapter 3: The Road"])
    #expect(ChapterSplitter.split("12. 回家\n内容", rules: ChapterRule.presets).map(\.title) == ["12. 回家"])
}
@Test func longLinesAreNotHeadings() {
    let line = "第一章" + String(repeating: "很", count: 60)
    #expect(ChapterSplitter.split(line + "\n内容", rules: ChapterRule.presets).map(\.title) == [""])
}
@Test func fallsBackToNumberedPartsAtLineBoundaries() {
    let text = (1...10).map { "第\($0)行" + String(repeating: "字", count: 5) }.joined(separator: "\n")
    let parts = ChapterSplitter.split(text, rules: [], fallbackLength: 20)
    #expect(parts.count > 1)
    #expect(parts.allSatisfy { $0.title.isEmpty })
    #expect(parts.map(\.body).joined(separator: "\n") == text)
}
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement `ChapterSplitter.split`.**
  - Normalise `\r\n` and `\r` to `\n` and strip a leading BOM.
  - Trim each line of ASCII and full-width spaces (U+3000).
  - Test rules in preset order against the trimmed line.
  - Text before the first heading becomes a preface chapter with title `""`, and only
    if it is non-empty.
  - With no headings at all, cut parts of at most `fallbackLength` characters at line
    boundaries, titled `""`.
  - Use `NSRegularExpression`, which exists on Windows Foundation.
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "Split TXT books into chapters and volumes"`

### Task 7: Chapter keys, identity and file-name metadata

**Files:**
- Create: `Sources/ShioriCore/{TitleNormalizer,ChapterKey,BookIdentity,FileNameMetadata}.swift`,
  and a test file for each.

**Interfaces:**
- Produces:
  - `enum TitleNormalizer { static func normalize(_ s: String) -> String }`: NFKC
    (`precomposedStringWithCompatibilityMapping`), trim, collapse whitespace runs to
    one space, lowercase.
  - `struct ChapterKey: Hashable, Codable, Sendable { var title: String; var occurrence: Int }`
  - `enum ChapterKeys { static func make(titles: [String]) -> [ChapterKey] }`:
    `occurrence` counts earlier chapters with the same normalised title.
  - `enum BookIdentity { static func identifierKey(_ identifier: String?) -> String?; static func titleAuthorKey(title: String, author: String?) -> String }`
  - `struct FileNameMetadata: Equatable { var title: String; var author: String?; static func parse(_ fileName: String) -> FileNameMetadata }`

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func chapterKeysCountRepeats() {
    let keys = ChapterKeys.make(titles: ["第一章 开始", "番外", "番外", "  第一章  开始 "])
    #expect(keys == [
        ChapterKey(title: "第一章 开始", occurrence: 0), ChapterKey(title: "番外", occurrence: 0),
        ChapterKey(title: "番外", occurrence: 1), ChapterKey(title: "第一章 开始", occurrence: 1),
    ])
}
@Test func identityKeys() {
    #expect(BookIdentity.identifierKey("  trxs-https://www.trxs.cc/tongren/11502/1.html ") == "trxs-https://www.trxs.cc/tongren/11502/1.html")
    #expect(BookIdentity.identifierKey("   ") == nil)
    #expect(BookIdentity.titleAuthorKey(title: "全民转职：死灵法师！", author: "慢途的猪") == "全民转职:死灵法师!|慢途的猪")
    #expect(BookIdentity.titleAuthorKey(title: "Book", author: nil) == "book|")
}
@Test func fileNameMetadata() {
    #expect(FileNameMetadata.parse("全民转职：死灵法师！我即是天灾(慢途的猪).epub") == .init(title: "全民转职：死灵法师！我即是天灾", author: "慢途的猪"))
    #expect(FileNameMetadata.parse("斗破苍穹（天蚕土豆）.txt") == .init(title: "斗破苍穹", author: "天蚕土豆"))
    #expect(FileNameMetadata.parse("《诡秘之主》作者：爱潜水的乌贼.txt") == .init(title: "诡秘之主", author: "爱潜水的乌贼"))
    #expect(FileNameMetadata.parse("无职转生 (1).txt") == .init(title: "无职转生 (1)", author: nil))
    #expect(FileNameMetadata.parse("plain name.txt") == .init(title: "plain name", author: nil))
}
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **Parenthetical author:** a trailing `(…)` or `（…）` is an author only if it is 1–20
    characters and does not match `^\d+$|^(vol|卷)`.
  - **《》 form:** for `《title》作者：author` the title is inside 《》, and the author
    follows `作者：` or `作者:`.
- [ ] **Step 4: Run the tests.** Expected: pass. Run the whole ShioriCore suite: all green.
- [ ] **Step 5: Commit and ship.** Commit "Add chapter keys, book identity and
  file-name metadata", then ship. CI must be green.

### Task 8: ShioriLibrary package, storage and database v1

**Files:**
- Create: `ios/Packages/ShioriLibrary/Package.swift`,
  `Sources/ShioriLibrary/{LibraryPaths,Records,LibraryDatabase}.swift`,
  `Tests/ShioriLibraryTests/LibraryDatabaseTests.swift`.
- Modify: `ios/project.yml` (uncomment `ShioriLibrary`), `ios-compile.yml` (add
  `swift test --package-path ios/Packages/ShioriLibrary`), and `tools/app-check/Package.swift`.

**Interfaces:**
- Consumes: `ChapterKey` (Task 7).
- Produces:
  - `struct LibraryPaths: Sendable { let root: URL; init(root: URL); static func standard() throws -> LibraryPaths; var database: URL; var books: URL; var staging: URL; func bookDirectory(_ id: UUID) -> URL; func prepare() throws }`.
    `standard()` is `Application Support/Shiori`; `database` is `root/library.sqlite`;
    `books` is `root/Books`; `staging` is `root/Staging`.
  - `enum BookFormat: String, Codable, Sendable { case epub, txt, pdf }`
  - `struct Book: Codable, Identifiable, Equatable, Sendable, FetchableRecord, PersistableRecord { var id: UUID; var title: String; var author: String?; var format: BookFormat; var sourceIdentifier: String?; var titleAuthorKey: String; var contentHash: String; var originalFileName: String; var addedAt: Date; var chapterCount: Int; var hasCover: Bool }`
  - `struct Chapter: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord { var bookId: UUID; var index: Int; var title: String; var volume: String?; var keyTitle: String; var keyOccurrence: Int; var source: String }`.
    `source` is the archive path for EPUB, or `chapters/00001.txt` for TXT.
  - `struct Progress: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord { var bookId: UUID; var chapterIndex: Int; var keyTitle: String; var keyOccurrence: Int; var offset: Int; var fraction: Double; var updatedAt: Date }`
  - `struct BookListItem: Equatable, Sendable, Identifiable { var book: Book; var progress: Progress?; var id: UUID { book.id } }`
  - `final class LibraryDatabase: Sendable`, with:
    - `init(path: URL) throws` and `static func inMemory() throws -> LibraryDatabase`
    - `func insert(book: Book, chapters: [Chapter]) throws` (one transaction)
    - `func book(withContentHash: String) throws -> Book?`
    - `func bookList() throws -> [BookListItem]`
    - `func chapters(bookId: UUID) throws -> [Chapter]`
    - `func progress(bookId: UUID) throws -> Progress?` and `func save(_ progress: Progress) throws`
    - `func observeBookList(_ onChange: @escaping @Sendable ([BookListItem]) -> Void) -> AnyDatabaseCancellable`

- [ ] **Step 1: Write `Package.swift`.** Use swift-tools 6.2, platforms
  `[.iOS(.v26), .macOS(.v14)]`, and Swift 5 mode. Dependencies: `ShioriCore` by path,
  GRDB `from: "7.11.1"`, ZIPFoundation `from: "0.9.20"` and SwiftSoup `from: "2.14.3"`.
  Products: the library `ShioriLibrary`.
- [ ] **Step 2: Write the failing tests.**

```swift
@Test func migrationCreatesTablesAndRoundTrips() throws {
    let db = try LibraryDatabase.inMemory()
    let id = UUID()
    let book = Book(id: id, title: "桃花源记", author: "陶渊明", format: .epub, sourceIdentifier: "demo-1",
                    titleAuthorKey: "桃花源记|陶渊明", contentHash: "abc", originalFileName: "桃花源记.epub",
                    addedAt: Date(timeIntervalSince1970: 0), chapterCount: 2, hasCover: false)
    let chapters = [
        Chapter(bookId: id, index: 0, title: "第一章", volume: nil, keyTitle: "第一章", keyOccurrence: 0, source: "E/c1.xhtml"),
        Chapter(bookId: id, index: 1, title: "第二章", volume: nil, keyTitle: "第二章", keyOccurrence: 0, source: "E/c2.xhtml"),
    ]
    try db.insert(book: book, chapters: chapters)
    #expect(try db.book(withContentHash: "abc") == book)
    #expect(try db.chapters(bookId: id) == chapters)
}
@Test func bookListOrdersRecentlyReadFirstThenNewest() throws {
    let db = try LibraryDatabase.inMemory()
    let a = Book.fixture(title: "A", addedAt: 1), b = Book.fixture(title: "B", addedAt: 2), c = Book.fixture(title: "C", addedAt: 3)
    for book in [a, b, c] { try db.insert(book: book, chapters: []) }
    try db.save(Progress(bookId: a.id, chapterIndex: 0, keyTitle: "", keyOccurrence: 0, offset: 0, fraction: 0.1, updatedAt: Date(timeIntervalSince1970: 10)))
    #expect(try db.bookList().map(\.book.title) == ["A", "C", "B"])
}
@Test func saveProgressReplaces() throws {
    let db = try LibraryDatabase.inMemory()
    let book = Book.fixture(title: "A", addedAt: 1)
    try db.insert(book: book, chapters: [])
    var p = Progress(bookId: book.id, chapterIndex: 3, keyTitle: "第四章", keyOccurrence: 0, offset: 120, fraction: 0.4, updatedAt: .now)
    try db.save(p); p.offset = 200; try db.save(p)
    #expect(try db.progress(bookId: book.id)?.offset == 200)
}
```

  `Book.fixture(title:addedAt:)` is a test-only helper in
  `Tests/ShioriLibraryTests/Fixtures.swift`. It fills the other fields with unique
  values and sets `addedAt` from seconds.
- [ ] **Step 3: Implement.**
  - **Schema:** migrator `"v1"` creates `book` (primary key `id`, unique index on
    `contentHash`), `chapter` (primary key `bookId`+`index`, cascade delete) and
    `progress` (primary key `bookId`, cascade delete).
  - **Book list order:** books with progress come first, newest `updatedAt` first; the
    rest follow by `addedAt` descending.
  - **Connections:** `DatabaseQueue` for both the in-memory and file databases.
- [ ] **Step 4: Check locally.** Run `bash tools/check-app.sh`, which compiles the
  package sources (not the tests). These tests can't run on Windows, because GRDB needs
  Apple's SQLite, and `main` never gets a commit expected to fail. So there is no red run
  for CI-only tests: write the tests and the code together.
- [ ] **Step 5: Commit "Add ShioriLibrary storage and database v1", ship, and watch CI.**
  Expected: the ShioriLibrary tests pass on the runner.

### Task 9: TXT decoding

**Files:**
- Create: `Sources/ShioriLibrary/TextDecoding.swift` and
  `Tests/ShioriLibraryTests/TextDecodingTests.swift`.

**Interfaces:**
- Produces:
  - `enum TextDecoding { static let gb18030: String.Encoding; static let big5: String.Encoding; static func decode(_ data: Data, preferred: String.Encoding? = nil) throws -> (text: String, encoding: String.Encoding) }`
  - `struct TextDecodingError: Error, Equatable { }`, thrown only for empty data.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func decodesGB18030() throws {
    let data = try #require("第一章 测试\n内容".data(using: TextDecoding.gb18030))
    let r = try TextDecoding.decode(data)
    #expect(r.text == "第一章 测试\n内容")
    #expect(r.encoding == TextDecoding.gb18030)
}
@Test func decodesBig5() throws {
    let data = try #require("第一章 測試\n內容很長的一段繁體中文文字".data(using: TextDecoding.big5))
    #expect(try TextDecoding.decode(data).text == "第一章 測試\n內容很長的一段繁體中文文字")
}
@Test func honoursBOMs() throws {
    #expect(try TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("甲".utf8)).text == "甲")
    var le = Data([0xFF, 0xFE]); le.append(try #require("乙".data(using: .utf16LittleEndian)))
    #expect(try TextDecoding.decode(le).text == "乙")
}
@Test func plainUTF8() throws { #expect(try TextDecoding.decode(Data("丙丁".utf8)).encoding == .utf8) }
@Test func preferredEncodingWins() throws {
    let data = try #require("內容".data(using: TextDecoding.big5))
    #expect(try TextDecoding.decode(data, preferred: TextDecoding.big5).text == "內容")
}
@Test func emptyThrows() { #expect(throws: TextDecodingError()) { try TextDecoding.decode(Data()) } }
```

- [ ] **Step 2: **No red run.** These tests run only on CI and `main` never gets a commit expected to fail; go straight to the implementation.**
- [ ] **Step 3: Implement.** Detection order:
  1. a preferred encoding, if one is given
  2. a BOM (UTF-8, UTF-16 LE or BE)
  3. strict UTF-8
  4. `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)`
     with suggested encodings `[gb18030, big5]`, lossy disallowed
  5. GB18030 with lossy repair

  Strip a leading U+FEFF from the result. The encodings come from
  `CFStringConvertEncodingToNSStringEncoding` with `.GB_18030_2000` and `.big5`.
- [ ] **Step 4: Run `bash tools/check-app.sh`, commit "Detect TXT encodings", ship, and watch CI.** Expected: pass.

### Task 10: EPUB archive, chapter content and the XHTML parser

**Files:**
- Create: `Sources/ShioriLibrary/{EPUBArchive,EPUBWriter,ChapterContent,XHTMLContentParser}.swift`
  and `Tests/ShioriLibraryTests/{ChapterContentTests,XHTMLContentParserTests,EPUBArchiveTests}.swift`.

**Interfaces:**
- Consumes: `ContainerParser`, `PackageParser`, `TOCParser` and `EPUBPath` (Tasks 3–5).
- Produces:
  - `final class EPUBArchive { init(url: URL) throws; func data(at path: String) throws -> Data; func contains(_ path: String) -> Bool; var hasDRM: Bool }`.
    `hasDRM` is true when `META-INF/encryption.xml` lists an algorithm other than the
    font-obfuscation ones (`http://www.idpf.org/2008/embedding`,
    `http://ns.adobe.com/pdf/enc#RC`).
  - `enum EPUBWriter`, with:
    - `struct Book { var title: String; var author: String; var identifier: String; var chapters: [(title: String, volume: String?, paragraphs: [String])]; var coverJPEG: Data?; var fixedLayout: Bool = false; var encrypted: Bool = false }`
    - `static func write(_ book: Book, to url: URL) throws`
    - It writes the SoNovel shape: `mimetype` stored first and uncompressed,
      `EPUB/content.opf`, `EPUB/toc.ncx`, `EPUB/nav.xhtml`, one `chapter_N.xhtml` per
      chapter with `<h2>` and `<p>`, and nested NCX points when volumes are set.
  - `enum ChapterBlock: Equatable, Sendable { case heading(String, level: Int); case paragraph(String); case image(path: String) }`
  - `struct ChapterContent: Equatable, Sendable { var blocks: [ChapterBlock]; var plainText: String; func offset(ofBlock index: Int) -> Int; func block(containing offset: Int) -> Int }`.
    `plainText` joins block texts with `\n`; an image counts as `\u{FFFC}`; offsets are
    UTF-16.
  - `enum XHTMLContentParser { static func blocks(from html: String, documentPath: String) throws -> [ChapterBlock] }`

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func offsetsMapBothWays() {
    let c = ChapterContent(blocks: [.heading("第一章", level: 2), .paragraph("甲乙"), .paragraph("丙")])
    #expect(c.plainText == "第一章\n甲乙\n丙")
    #expect(c.offset(ofBlock: 2) == 7)
    #expect(c.block(containing: 5) == 1)
    #expect(c.block(containing: 7) == 2)
    #expect(c.block(containing: 999) == 2)
}
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
@Test func archiveRoundTripsWriterAndDetectsDRM() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).epub")
    try EPUBWriter.write(.init(title: "桃花源记", author: "陶渊明", identifier: "demo-1",
        chapters: [("第一章", nil, ["晋太元中，武陵人捕鱼为业。"])], coverJPEG: nil), to: url)
    let archive = try EPUBArchive(url: url)
    #expect(archive.contains("EPUB/content.opf"))
    #expect(archive.hasDRM == false)
    let locked = url.deletingLastPathComponent().appending(path: "\(UUID()).epub")
    try EPUBWriter.write(.init(title: "x", author: "y", identifier: "z", chapters: [("c", nil, ["p"])], coverJPEG: nil, encrypted: true), to: locked)
    #expect(try EPUBArchive(url: locked).hasDRM)
}
```

- [ ] **Step 2: **No red run.** These tests run only on CI and `main` never gets a commit expected to fail; go straight to the implementation.**
- [ ] **Step 3: Implement.**
  - **Parser:** SwiftSoup's lenient HTML parsing.
  - **Blocks:** `h1`–`h6` become headings. `p`, `div` leaf text and `li` become
    paragraphs, and `<br>` splits a paragraph. `img` and `image@xlink:href` become
    images, resolved with `EPUBPath.resolve`.
  - **Text:** collapse whitespace runs (including U+00A0 from `&nbsp;`) to one space,
    trim ASCII and U+3000, drop empty paragraphs.
- [ ] **Step 4: Run `bash tools/check-app.sh`, commit "Read EPUB archives and chapter content", ship, and watch CI.** Expected: pass.

### Task 11: Importer

**Files:**
- Create: `Sources/ShioriLibrary/{ImportOutcome,BookImporter,BookContentSource,DemoBooks}.swift`
  and `Tests/ShioriLibraryTests/{BookImporterTests,BookContentSourceTests}.swift`.

**Interfaces:**
- Consumes: everything from Tasks 3–10.
- Produces:
  - `enum ImportFailure: Error, Equatable, Sendable { case unsupportedFormat, tooLarge(limitBytes: Int64), drmProtected, fixedLayout, noChapters, empty, unreadable(String) }`
  - `enum ImportOutcome: Equatable, Sendable { case added(bookId: UUID, title: String); case alreadyInLibrary(bookId: UUID, title: String); case failed(fileName: String, reason: ImportFailure) }`
  - `actor BookImporter`, with:
    - `init(database: LibraryDatabase, paths: LibraryPaths, rules: [ChapterRule] = ChapterRule.presets)`
    - `func importFile(at url: URL) async -> ImportOutcome`
    - `func cleanStaging() throws`
  - `final class BookContentSource: Sendable { init(book: Book, paths: LibraryPaths) throws; func content(of chapter: Chapter) throws -> ChapterContent }`.
    A TXT chapter yields `.heading(title, level: 2)` followed by one paragraph per stored
    line.
  - `enum DemoBooks { static func write(into directory: URL) throws -> [URL] }`. It
    writes three public-domain books:
    - 《桃花源记》 (EPUB, 12 chapters)
    - 《岳阳楼记》 (TXT in GB18030, with 第X章 headings and a preface)
    - 《兰亭集序》 (EPUB with two volumes)
    Chapters repeat the source text to give realistic lengths.

**Import pipeline:**

1. **Check:** the extension must be `epub` or `txt` (`pdf` and `zip` come in M3, as
   `unsupportedFormat`). Size limits: EPUB 512 MiB, TXT 128 MiB.
2. **Hash:** stream SHA-256 with CryptoKit. On a hit in `book(withContentHash:)`, return
   `.alreadyInLibrary`.
3. **Copy:** copy into `staging/<uuid>/original.<ext>`.
4. **EPUB:**
   - DRM gives `drmProtected`, fixed layout gives `fixedLayout`.
   - Build the chapter list with `EPUBChapterList`, preferring nav over NCX and falling
     back to NCX when nav fails to parse.
   - Fill empty titles from the chapter's first heading.
   - Write the cover to `cover.<ext>`.
   - Title, author and identifier come from the metadata. If the title is empty, use
     `FileNameMetadata`.
5. **TXT:**
   - Decode it; empty text gives `empty`.
   - Split it into chapters with `ChapterSplitter`.
   - Write each body to `chapters/%05d.txt` (UTF-8).
   - Title and author come from `FileNameMetadata`. The identifier is nil.
6. **Keys:** `ChapterKeys.make` over the titles. An empty title keys as `""`.
7. **Commit:** move staging to `bookDirectory(id)`, then `insert(book:chapters:)`.
   - If the insert throws, remove the directory.
   - On any failure, remove the staging folder.
   - Imports run one at a time (actor), so a file in the same batch or a second tap
     dedupes.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func importsEPUBAndDedupes() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 3)
    guard case .added(let id, let title) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    #expect(title == "测试书")
    #expect(try env.db.chapters(bookId: id).map(\.title) == ["第1章", "第2章", "第3章"])
    #expect(await env.importer.importFile(at: url) == .alreadyInLibrary(bookId: id, title: "测试书"))
}
@Test func concurrentImportsOfSameFileAddOnce() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 2)
    async let a = env.importer.importFile(at: url)
    async let b = env.importer.importFile(at: url)
    let outcomes = await [a, b]
    #expect(outcomes.filter { if case .added = $0 { true } else { false } }.count == 1)
    #expect(try env.db.bookList().count == 1)
}
@Test func importsGB18030TXTWithFileNameMetadata() async throws {
    let env = try TestEnvironment()
    let url = try env.writeTXT(name: "岳阳楼记(范仲淹).txt", text: "序\n第一章 庆历\n正文\n第二章 洞庭\n正文", encoding: TextDecoding.gb18030)
    guard case .added(let id, let title) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    #expect(title == "岳阳楼记")
    let book = try #require(try env.db.bookList().first?.book)
    #expect(book.author == "范仲淹")
    let chapters = try env.db.chapters(bookId: id)
    #expect(chapters.map(\.title) == ["", "第一章 庆历", "第二章 洞庭"])
    let content = try BookContentSource(book: book, paths: env.paths).content(of: chapters[1])
    #expect(content.blocks == [.heading("第一章 庆历", level: 2), .paragraph("正文")])
}
@Test func rejectsDRMFixedLayoutEmptyAndUnsupported() async throws {
    let env = try TestEnvironment()
    #expect(await env.importer.importFile(at: try env.writeEPUB(chapters: 1, encrypted: true)) == .failed(fileName: "测试书.epub", reason: .drmProtected))
    #expect(await env.importer.importFile(at: try env.writeEPUB(chapters: 1, fixedLayout: true)) == .failed(fileName: "测试书.epub", reason: .fixedLayout))
    #expect(await env.importer.importFile(at: try env.writeTXT(name: "空.txt", text: "", encoding: .utf8)) == .failed(fileName: "空.txt", reason: .empty))
    #expect(await env.importer.importFile(at: try env.writeTXT(name: "a.mobi", text: "x", encoding: .utf8)) == .failed(fileName: "a.mobi", reason: .unsupportedFormat))
}
@Test func failedImportLeavesNoFiles() async throws {
    let env = try TestEnvironment()
    _ = await env.importer.importFile(at: try env.writeEPUB(chapters: 1, encrypted: true))
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.books.path).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.staging.path).isEmpty)
}
@Test func cleanStagingRemovesLeftovers() async throws {
    let env = try TestEnvironment()
    try FileManager.default.createDirectory(at: env.paths.staging.appending(path: "orphan"), withIntermediateDirectories: true)
    try await env.importer.cleanStaging()
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.paths.staging.path).isEmpty)
}
@Test func fiveThousandChapterBookImports() async throws {
    let env = try TestEnvironment()
    let url = try env.writeEPUB(chapters: 5_000)
    let start = Date()
    guard case .added(let id, _) = await env.importer.importFile(at: url) else { Issue.record("not added"); return }
    print("5,000-chapter import took \(Date().timeIntervalSince(start)) s")
    #expect(try env.db.chapters(bookId: id).count == 5_000)
}
```

  `TestEnvironment` lives in `Fixtures.swift`. It holds a temporary `LibraryPaths`, an
  in-memory `LibraryDatabase` and a `BookImporter`, plus these helpers:
  - `writeEPUB(chapters:encrypted:fixedLayout:)` writes the title `测试书` and author
    `测试`, with chapters `第N章` of three paragraphs each, via `EPUBWriter`, to a file
    named `测试书.epub`.
  - `writeTXT(name:text:encoding:)`.
- [ ] **Step 2: **No red run.** These tests run only on CI and `main` never gets a commit expected to fail; go straight to the implementation.**
- [ ] **Step 3: Implement** `BookImporter`, `BookContentSource` and `DemoBooks` as the
  pipeline above describes.
- [ ] **Step 4: Run `bash tools/check-app.sh`, commit, ship, and watch CI. Expected: pass.** Note the 5,000-chapter timing from the log in the
  commit message body. Commit "Import EPUB and TXT books".

### Task 12: App model, tokens and the full-width bar

**Files:**
- Create: `ios/Sources/App/{AppModel,DemoLaunch}.swift`, `Design/Tokens.swift`,
  `Shell/AppTab.swift` and `Shell/ShioriTabBar.swift`.
- Modify: `Shell/RootView.swift`, `ShioriApp.swift` and `Localizable.xcstrings`.

**Interfaces:**
- Consumes: `LibraryPaths`, `LibraryDatabase`, `BookImporter`, `BookListItem` and
  `ImportOutcome`.
- Produces:
  - `@MainActor @Observable final class AppModel`, with:
    - `let paths: LibraryPaths`, `let database: LibraryDatabase`, `let importer: BookImporter`
    - `var books: [BookListItem]` (kept current by `observeBookList`)
    - `var recentImports: [ImportOutcome]` (newest batch first) and `var isImporting: Bool`
    - `func importFiles(_ urls: [URL]) async`
    - `static func live() throws -> AppModel`, which runs `cleanStaging()` on launch
  - `enum AppTab: CaseIterable { case shelf, imports, settings }`, with `title: LocalizedStringResource` and `systemImage: String`
    (placeholders `books.vertical`, `square.and.arrow.down`, `gearshape`; the custom
    icons arrive in M2).
  - `struct ShioriTabBar: View { @Binding var selection: AppTab }`
  - `enum Tokens`: `paper`, `surface`, `line`, `ink` and `inkSecondary` as `Color`s with
    the light and dark values from spec §4.2.
  - `DemoLaunch` (Debug only) reads these launch arguments:
    - `-DemoData YES` builds `AppModel` over `LibraryPaths(root: <tmp>/ShioriDemo)` and
      imports `DemoBooks` through the real importer, so demo data never touches the
      real library.
    - `-DemoTab shelf|imports|settings`.
    - `-DemoReader <n>` opens the n-th shelf book in the reader.
    - `-DemoContents YES` also opens the contents sheet.

**Bar spec (spec §5.1):**

- **Placement:** horizontal inset 16 pt from the screen edges; height 64 pt; bottom gap
  12 pt above the safe-area bottom.
- **Shape:** capsule, `.glassEffect(.regular.tint(Tokens.paper.opacity(0.35)).interactive())`.
- **Lanes:** three equal-width lanes, each with a 24 pt icon over an 11 pt label.
- **Selection lens:** an inner capsule inset 4 pt that springs (`.spring(duration: 0.35, bounce: 0.25)`)
  to the selected lane.
- **Drag:** dragging horizontally moves the lens with the finger, and the tab nearest
  the lens selects on release.
- **Accessibility:** each lane is a button with its title as the label, and the selected
  lane has the `.isSelected` trait.
- **Root:** `RootView` keeps one `NavigationStack` per tab, with the bar overlaid at the
  bottom. Content gets bottom padding of bar height + gap + 20 pt.

- [ ] **Step 1: Implement** the model, tokens, tab enum, bar and root. Add every new
  string to `Localizable.xcstrings` with its `zh-Hans` translation: 书架, 导入, 设置.
- [ ] **Step 2: Run `bash tools/check-app.sh`.** Expected: success.
- [ ] **Step 3: Add screenshot lines to `ios-compile.yml`.**
  `shoot 02-shelf-empty 8 -DemoTab shelf` (this one without `-DemoData`; split the
  `shoot` helper so demo data is opt-in per line).
- [ ] **Step 4: Ship and watch CI. Look at the screenshots.** Expected: the bar spans the
  width with a 16 pt inset on both sides, three lanes, Shelf selected, on paper.
- [ ] **Step 5: Commit.** "Add the app model and the full-width floating bar"

### Task 13: Import tab

**Files:**
- Create: `ios/Sources/App/Import/ImportView.swift`.
- Modify: `Localizable.xcstrings` and `ios-compile.yml`.

**Interfaces:**
- Consumes: `AppModel.importFiles(_:)`, `recentImports` and `isImporting`.

- [ ] **Step 1: Implement `ImportView`.**
  - **Header:** the masthead line `02 / IMPORT` in `.monospaced` 12 pt, `inkSecondary`;
    then the large title 导入 / Import.
  - **Import files button:** opens `.fileImporter` with
    `allowedContentTypes: [.epub, .plainText]` and multiple selection.
  - **File access:** for each URL, run `startAccessingSecurityScopedResource()` and read
    through `NSFileCoordinator` so iCloud files download first. Hand the URLs to
    `importFiles`.
  - **Results:** each outcome as a row: Added / Already in library / Failed, with the
    title or file name and a plain-language reason.

  Localise the strings:

  | English | zh-Hans |
  | --- | --- |
  | Import files | 导入文件 |
  | Added | 已添加 |
  | Already in library | 已在书架中 |
  | This book is DRM-protected. | 此书受 DRM 保护，无法导入。 |
  | Fixed-layout books aren't supported yet. | 暂不支持固定版式的书。 |
  | No chapters were found. | 没有找到章节。 |
  | The file is empty. | 文件是空的。 |
  | Only EPUB and TXT for now. | 目前只支持 EPUB 和 TXT。 |
  | Too large (over %@). | 文件过大（超过 %@）。 |
  | Couldn't read the file. | 无法读取文件。 |
- [ ] **Step 2: Add a demo hook** in `DemoLaunch`. `-DemoImportResults YES` fills
  `recentImports` with one of each outcome kind, so the screenshot shows every row style.
- [ ] **Step 3: Add the screenshot line.**
  `shoot 03-import 10 -DemoTab imports -DemoImportResults YES`.
- [ ] **Step 4: Run `tools/check-app.sh`, then commit, ship and check the screenshot.** Expected:
  every row reads correctly in English (the simulator's locale).
- [ ] **Step 5: Commit.** "Add the Import tab"

### Task 14: Shelf list and Settings stub

**Files:**
- Create: `ios/Sources/App/Shelf/ShelfView.swift` and `Settings/SettingsView.swift`.
- Modify: `Localizable.xcstrings` and `ios-compile.yml`.

**Interfaces:**
- Consumes: `AppModel.books`.
- Produces: `ShelfView(onOpen: (Book) -> Void)`.

- [ ] **Step 1: Implement `ShelfView`.**
  - **Header:** masthead `01 / SHELF` and the large title 书架 / Shelf.
  - **List:** a `List` of `BookListItem`. Each row shows the title, author, and a status
    of "Unread" (未读) or "%lld%%" from `progress.fraction`, plus a 2 pt progress bar.
  - **Tap:** calls `onOpen`.
  - **Empty state:** the title "Your shelf is empty" (书架还是空的), the body
    "Import EPUB or TXT books to start reading." (导入 EPUB 或 TXT 书籍开始阅读。) and a
    button that switches to the Import tab.
- [ ] **Step 2: Implement `SettingsView`.**
  - **Header:** masthead `03 / SETTINGS` and the large title.
  - **About section:** "Version %@ (%@)" from the bundle, plus a "Source code" link to
    `https://github.com/KaiC5504/Shiori`.
- [ ] **Step 3: Add the screenshot lines.** `shoot 04-shelf 10 -DemoTab shelf` and
  `shoot 05-settings 8 -DemoTab settings`. Then add the dark set: run
  `xcrun simctl ui "$UDID" appearance dark` and repeat `04-shelf` as `04-shelf-dark`.
- [ ] **Step 4: Run `tools/check-app.sh`, then commit, ship and look at the shots.** Expected:
  three demo books with titles and authors; dark mode uses the dark tokens.
- [ ] **Step 5: Commit.** "Add the shelf list and the settings stub"

### Task 15: Scroll reader, contents and saved progress

**Files:**
- Create: `ios/Sources/App/Reader/{ReaderModel,ReaderView,ContentsSheet}.swift`.
- Modify: `RootView.swift` (present the reader with `.fullScreenCover`, which also hides
  the bar), `Localizable.xcstrings` and `ios-compile.yml`.

**Interfaces:**
- Consumes: `BookContentSource`, `ChapterContent.offset(ofBlock:)` and
  `block(containing:)`, and `LibraryDatabase.chapters`, `progress` and `save`.
- Produces:
  - `struct ParagraphAnchor: Hashable { var chapter: Int; var block: Int }`
  - `@MainActor @Observable final class ReaderModel`, with:
    - `init(book: Book, database: LibraryDatabase, paths: LibraryPaths) throws`
    - `let chapters: [Chapter]`
    - `func content(for chapter: Int) async -> ChapterContent?` (loaded off the main
      actor; keeps at most 5 chapters in memory, centred on the visible one)
    - `var initialAnchor: ParagraphAnchor` (from saved progress, else chapter 0 block 0)
    - `func visibleAnchorChanged(_ anchor: ParagraphAnchor)` (debounced 0.5 s, then
      saves)
    - `func saveNow()`

**Reader requirements:**

- Continuous vertical scroll through chapters, loaded lazily in both directions, with
  each chapter's heading block shown as its title.
- Placeholder typography until M4a: system serif 19 pt, line spacing 8 pt, side margins
  24 pt, paragraph gap 12 pt, all on `Tokens.paper`.
- The saved position is (chapter key, `offset(ofBlock:)` of the top visible paragraph),
  with `fraction = (chapterIndex + blockFraction) / chapterCount`.
- `saveNow()` runs on disappear and when `scenePhase` becomes `.background`.
- **Top bar:** a minimal bar shown on a centre tap, with Back and Contents. M4b replaces
  it with the glass chrome.
- **Contents sheet:**
  - a virtualised `List` of chapters, with the volume as a section header when present
  - the current chapter marked
  - tapping jumps there and closes the sheet
  - empty titles show "Preface" (前言) for a first chapter with no heading, else
    "Part %lld" (第 %lld 部分)

- [ ] **Step 1: Implement the model and views.**
- [ ] **Step 2: Add the screenshot lines.** `shoot 06-reader 12 -DemoTab shelf -DemoReader 1`
  and `shoot 07-contents 12 -DemoTab shelf -DemoReader 1 -DemoContents YES`.
- [ ] **Step 3: Run `tools/check-app.sh`, then commit, ship and look.** Expected: reader text on
  paper with the chapter heading; the contents sheet has volume sections for 《兰亭集序》.
- [ ] **Step 4: Commit.** "Add the scroll reader with contents and saved progress"

### Task 16: TestFlight and the first build

**Files:**
- Create: `.github/workflows/testflight.yml`, `scripts/testflight.py` and
  `scripts/testflight-requirements.txt`, from the `ios-testflight` skill.
- Modify: `CLAUDE.md` (fill in the App Store Connect name and Apple ID) and
  `docs/THIRD_PARTY.md`.

- [ ] **Step 1: Load the `ios-testflight` skill.** Copy its `templates/testflight.yml`,
  `templates/testflight-requirements.txt` and `scripts/testflight.py`, then:
  - set `BUNDLE_ID: com.kaichuan.shiori`, `PROJECT: ios/Shiori.xcodeproj`,
    `SCHEME: Shiori` and `REPO = "KaiC5504/Shiori"`
  - set `runs-on: xcode-27` and select `/Applications/Xcode_27.1.app`, as in the
    compile check
  - pin every action to the commit SHAs in Task 1, plus
    `actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0` (v7.1.0)
- [ ] **Step 2: OWNER: walk KaiC through the skill's `reference/manual-steps.md`**, one
  section at a time, in its wording:
  - **§3:** the App Store Connect record. App Store names must be unique, so try
    "Shiori Reader". If it's taken, KaiC picks a variant; the home-screen name stays
    "Shiori" from `CFBundleDisplayName`.
  - **§4:** the internal tester.
  - **§5:** the `testflight` environment and secrets.

  Verify with `gh secret list --env testflight -R KaiC5504/Shiori`. Put the Apple ID
  into `ASC_APP_ID`, commit and ship.
- [ ] **Step 3: Dry run.** With everything shipped to `main`, run
  `python scripts/testflight.py start --create-signing --dry-run` and watch it. Expected:
  green signing and checks with no upload. Fix failures with the skill's
  `reference/troubleshooting.md`.
- [ ] **Step 4: First build.** Run `python scripts/testflight.py start --create-signing`,
  then `python scripts/testflight.py watch <id>` in the background. Expected: green,
  meaning Apple has processed the build. Note the build number.
- [ ] **Step 5: Report to KaiC.** Give the build number, what's in it, and these test
  steps:
  1. Install from TestFlight (manual-steps §6). The home-screen icon is the
     butterfly-ribbon face, and its name is "Shiori".
  2. The bottom bar spans the screen with equal side gaps. Drag your finger along it:
     the lens follows and selects on release.
  3. Import → Import files → pick the test book from Files. It shows "Added" (time it:
     the bar to clear is under 10 s).
  4. Import the same file again. It shows "Already in library".
  5. Shelf → tap the book. It opens at 简介. Open Contents and jump to chapter 2,000,
     then scroll a few paragraphs.
  6. Swipe the app away from the app switcher. Reopen the book: it is at the same
     paragraph.
  7. Import any SoNovel TXT. Its chapters are split and the author comes from the file
     name.
  8. Switch the phone to 中文: every label is in Chinese.
- [ ] **Step 6: Commit** the workflow and scripts. Update the roadmap's M1 line to done,
  with the build number.

---

## Self-review notes

- **Spec coverage for M1:**
  - §3: identity, iOS 26 minimum and CI are in Tasks 1 and 16.
  - §5.1: the bar is in Task 12.
  - §8.3: the EPUB and TXT pipeline is in Task 11. The other import pieces (watched
    folder, share, ZIP, PDF, updates) are M3.
  - §7.3: positions by chapter key are in Tasks 7, 8 and 15.
  - §11: strings are localised from Task 12 on.
  - §12: the privacy manifest is in Task 1.
  - §14: core tests, fixtures and demo screenshots are in Tasks 3–15.
  - §15: the clean-room rule is in Global Constraints.
- **Deferred on purpose:** the instant in-app language switch (M2; M1 follows the phone's
  language), custom icons (M2), pagination and typography (M4a).
