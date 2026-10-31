# M1 Finish (Parallel) Implementation Plan

> **For agentic workers:** REQUIRED: run this plan with the project skill
> `running-a-milestone` (`.claude/skills/running-a-milestone/SKILL.md`). Task 1 is its
> contracts commit, Tasks 2–6 its build round (each brief follows the skill's §3), Task 8
> its merge, Task 9 its check, fix and ship rounds. This plan replaces the *execution
> order* of Tasks 12–16 in `docs/superpowers/plans/2026-10-31-m1-thin-slice.md`; those
> tasks' bodies stay the requirements for each screen (bar spec, strings, reader
> requirements, test steps). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish M1 (TestFlight build 1) as fast as possible by building the four app
screens and the signing pipeline in parallel, with no two agents touching the same file,
then merging and shipping once.

**Architecture:**

- **Wave 0 (controller, one task):** ship Task 11, then lay every shared file: the app
  model, demo launch flags, tokens, the root view, stub screens with their final
  signatures, all M1 strings and all screenshot lines. After this commit, each screen is
  one folder that only one agent edits.
- **Wave 1 (five agents at once, plus KaiC's portal steps):** the bar, Import, Shelf and
  Settings, the reader, and the TestFlight files. Each agent verifies locally and commits
  on its own worktree branch. Agents never push.
- **Wave 2 (controller):** merge the five branches into `dev`, add any strings the agents
  report, verify, ship once, and review every screenshot.
- **Wave 3 (controller plus one reviewer):** a whole-branch review alongside the signing
  dry run, then build 1 and the report.

**Tech Stack:** as in the M1 plan: SwiftUI (iOS 26.0 minimum), Swift 5 mode, GRDB,
ZIPFoundation, SwiftSoup, XcodeGen, GitHub Actions on `xcode-27`.

**Spec:** `docs/superpowers/specs/2026-10-31-shiori-design.md`. The parent plan is
`docs/superpowers/plans/2026-10-31-m1-thin-slice.md` (Tasks 1–11 are done, as recorded in
its ledger at `.superpowers/sdd/2026-10-31-m1-thin-slice/progress.md`).

## Global Constraints

Everything in the parent plan's Global Constraints applies, plus:

- **File ownership is the merge contract.** An agent edits only the files its task lists
  under **Owns**. If it needs a change anywhere else, it says so in its report and the
  controller makes it in Wave 2.
- **Nobody but the controller edits** `Localizable.xcstrings`, `ios-compile.yml`,
  `ios/project.yml`, `tools/app-check/Package.swift`, `RootView.swift`, `AppModel.swift`
  or `DemoLaunch.swift`.
- **Strings:** every M1 string is in the catalog after Wave 0. An agent that needs a new
  one uses it in code as a `LocalizedStringResource` or `Text` key and lists it, with its
  `zh-Hans` translation, in its report.
- **Agents never push, merge, or switch away from their worktree branch.** Only the
  controller ships `main`.
- **Local checks are the agent's gate:** `bash tools/check-app.sh` must print `OK`, and
  so must `bash tools/check-lib-tests.sh` when the task touches `ShioriLibrary`. CI and
  screenshots happen once, in Wave 2.
- **Sample text:** long sample or demo text is generated, never long verbatim passages of
  an existing work. A session's output was blocked by the content filter for that.
- **M1 look:** plain but tidy on `Tokens.paper`, with placeholder SF Symbols. The archive
  look, glass, custom icons and motion are M2. For direction only, see
  `docs/design/concepts/` and `reference/screens/`.

## Review Focus

1. **Reopening at the same paragraph after a kill:** progress must be saved when the app
   goes to the background, not only on close. Task 5 tests the position maths; the kill
   test is step 6 on the phone.
2. **A position saved before a re-import:** restore by chapter key first and fall back to
   the index, so M3's updates can't send KaiC to the wrong chapter. Tested in Task 5
   (`restoresByKeyWhenIndexMoved`).
3. **Contents for 5,000 chapters:** the sheet must be a lazy `List` and must scroll to the
   current chapter without building every row. Checked with the test book on the phone.
4. **iCloud and other providers' files:** picked URLs need security-scoped access and a
   coordinated read, or a file not yet downloaded imports as "couldn't read". Task 3 owns
   this; checked on the phone.
5. **Bar widths:** nothing in the bar is fixed to 440 pt. It must lay out from the
   available width. Task 2; checked in screenshots.

## Execution map

| Wave | Task | Who | Owns (creates or edits) | Needs |
| --- | --- | --- | --- | --- |
| 0 | 1 Ship importer, lay the shell | controller | all shared files (below) | — |
| 1 | 2 Bar | agent A | `Shell/ShioriTabBar.swift` | Task 1 |
| 1 | 3 Import tab | agent B | `Import/` | Task 1 |
| 1 | 4 Shelf and Settings | agent C | `Shelf/`, `Settings/` | Task 1 |
| 1 | 5 Reader | agent D | `Reader/`, `ShioriLibrary/.../ReadingPosition.swift` and its test | Task 1 |
| 1 | 6 TestFlight files | agent E | `.github/workflows/testflight.yml`, `scripts/testflight*` | Task 1 |
| 1 | 7 Portal steps | controller + KaiC | nothing in the repo | Task 1 |
| 2 | 8 Merge and ship | controller | merges; strings; `testflight.yml` `ASC_APP_ID` | 2–7 |
| 3 | 9 Review, dry run, build 1 | controller + 1 reviewer | fixes, docs | 8 |

Suggested models: agents A and D on the session's model, because they handle gestures,
scroll position and lazy loading. Agents B, C and E on `sonnet`.

---

### Task 1: Ship the importer and lay the shell (Wave 0, controller)

**Files:**
- Create: `ios/Sources/App/AppModel.swift`, `DemoLaunch.swift`, `Design/Tokens.swift`,
  `Design/ScreenHeader.swift`, `Shell/AppTab.swift` (with `BarMetrics`), and stubs with
  final signatures: `Shell/ShioriTabBar.swift`, `Import/ImportView.swift`,
  `Shelf/ShelfView.swift`, `Settings/SettingsView.swift`, `Reader/ReaderView.swift`.
  (`tools/check-lib-tests.sh` already exists: it compiles ShioriLibrary's tests in WSL.)
- Modify: `ShioriApp.swift`, `Shell/RootView.swift`, `Resources/Localizable.xcstrings`,
  `.github/workflows/ios-compile.yml`.

**Interfaces (Produces; every Wave 1 agent builds against these):**

```swift
@MainActor @Observable final class AppModel {
    let paths: LibraryPaths
    let database: LibraryDatabase
    let importer: BookImporter
    var books: [BookListItem]            // kept current by observeBookList
    var recentImports: [ImportOutcome]   // newest batch first
    var isImporting: Bool
    var selectedTab: AppTab
    var openBook: Book?                  // non-nil presents the reader full screen
    func importFiles(_ urls: [URL]) async   // urls are already readable local copies
    static func live(paths: LibraryPaths) throws -> AppModel   // runs cleanStaging()
}
enum AppTab: CaseIterable, Hashable { case shelf, imports, settings
    var title: LocalizedStringResource; var systemImage: String }
enum BarMetrics { static let height: CGFloat = 64; static let bottomGap: CGFloat = 12
    static let horizontalInset: CGFloat = 16; static let contentBottomPadding: CGFloat /* height + gap + 20 */ }
enum Tokens { static let paper, surface, line, ink, inkSecondary: Color }   // spec §4.2, light and dark
struct ScreenHeader: View { init(code: String, title: LocalizedStringResource) }  // "02 / IMPORT" mono 12 pt inkSecondary, then large title
struct ShioriTabBar: View { init(selection: Binding<AppTab>) }
struct ImportView: View { init() }                       // reads @Environment(AppModel.self)
struct ShelfView: View { init(onOpen: @escaping (Book) -> Void) }
struct SettingsView: View { init() }
struct ReaderView: View { init(book: Book, showContents: Bool = false) }  // closes by setting model.openBook = nil
#if DEBUG
enum DemoLaunch {   // reads -DemoData, -DemoTab, -DemoReader <n, 1-based shelf order>, -DemoContents, -DemoImportResults
    static var showContents: Bool { get }
    static func paths() -> LibraryPaths?                 // <tmp>/ShioriDemo, wiped each launch; nil without -DemoData YES
    @MainActor static func apply(to model: AppModel) async   // imports DemoBooks, sets tab, fills results, opens the reader
}
#endif
```

`RootView` holds one `NavigationStack` per tab, all kept alive and showing only the
selected one. It overlays `ShioriTabBar` at the bottom, adds
`BarMetrics.contentBottomPadding` of bottom safe-area inset to every stack (screens add
none of their own), and presents `ReaderView` with `.fullScreenCover(item: $model.openBook)`,
which also hides the bar. `ShioriApp` injects the model with `.environment(model)`.

- [ ] **Step 1: Ship Task 11.** Run `git checkout main && git merge --ff-only dev &&
  git push origin main && git checkout dev`, then watch the run. Expected: green, with the
  ShioriLibrary suite at 30 tests (20 earlier plus Task 11's 10), and a "5,000-chapter
  import took … s" line in the log. Record the time.
- [ ] **Step 2: Write the shared files and stubs** to the interfaces above. Stubs render a
  `ScreenHeader` and one placeholder line. The bar stub is a plain `HStack` of three
  buttons.
- [ ] **Step 3: Fill `Localizable.xcstrings`** with every string in the M1 plan's Tasks 12–15
  in English and `zh-Hans`: 书架 · 导入 · 设置; Task 13's table plus
  "Failed" 导入失败, "Importing…" 正在导入…, "Recent imports" 最近导入; Task 14's
  shelf and settings strings plus "About" 关于, "Source code" 源代码,
  "Version %@ (%@)" 版本 %1$@（%2$@）; and the reader's "Back" 返回, "Contents" 目录,
  "Preface" 前言, "Part %lld" 第 %lld 部分, "Couldn't open this chapter." 无法打开这一章。
  Masthead code lines stay `Text(verbatim:)`.
- [ ] **Step 4: Add every screenshot line to `ios-compile.yml` now.** Split the `shoot`
  helper so demo data is opt-in. Lines: `02-shelf-empty` (no demo data), `03-import`,
  `04-shelf`, `05-settings`, `06-reader`, `07-contents`, then dark appearance and
  `04-shelf-dark`, `06-reader-dark`. Use the flags and waits from the M1 plan.
- [ ] **Step 5: Verify.** `bash tools/check-app.sh` and `bash tools/check-lib-tests.sh`.
  Expected: both OK.
- [ ] **Step 6: Commit and ship.** Commit "Lay the app shell: model, demo flags, tokens,
  stub screens". Ship, then check the shots. Expected: every shot launches without a
  crash and shows its stub, and `06-reader` shows the reader stub over no bar.

### Task 2: The full-width bar (Wave 1, agent A)

**Owns:** `ios/Sources/App/Shell/ShioriTabBar.swift`.
**Consumes:** `AppTab`, `BarMetrics`, `Tokens` (Task 1).
**Requirements:** the M1 plan's Task 12 "Bar spec": capsule 64 pt,
`.glassEffect(.regular.tint(Tokens.paper.opacity(0.35)).interactive())`, three equal
lanes with a 24 pt icon over an 11 pt label, and a lens inset 4 pt springing with
`.spring(duration: 0.35, bounce: 0.25)`. Dragging moves the lens, the nearest tab
selects on release, every lane is a button, and the selected lane has `.isSelected`. Lane
widths come from the bar's measured width, never from 440 pt. Respect Reduce Motion with
a quick crossfade.

- [ ] **Step 1: Implement** `ShioriTabBar` to the signature in Task 1.
- [ ] **Step 2: Verify.** Run `bash tools/check-app.sh`. Expected: `OK`.
- [ ] **Step 3: Commit** "Build the full-width floating bar" on your branch. Report
  any strings you used that aren't in the catalog.

### Task 3: Import tab (Wave 1, agent B)

**Owns:** everything under `ios/Sources/App/Import/` (it may add files there).
**Consumes:** `AppModel.importFiles(_:)`, `recentImports`, `isImporting`; `ImportOutcome`,
`ImportFailure`; `ScreenHeader`.
**Requirements:** the M1 plan's Task 13, Step 1. The picker uses
`.fileImporter(allowedContentTypes: [.epub, .plainText], allowsMultipleSelection: true)`.
For each URL, start security-scoped access, copy the file to a temporary folder inside a
coordinated read (`NSFileCoordinator`, so iCloud files download first), stop access,
then hand the temporary copies to `importFiles`. A failed coordinated read becomes a
`.failed(fileName:reason: .unreadable)` row, not a silent drop. Rows: Added / Already in
library / Failed, with the title or file name, and the plain-language reason from the
Task 13 table. `.tooLarge` formats its limit with `ByteCountFormatter`.

- [ ] **Step 1: Implement** `ImportView` and any row views under `Import/`.
- [ ] **Step 2: Verify.** Run `bash tools/check-app.sh`. Expected: `OK`.
- [ ] **Step 3: Commit** "Add the Import tab" on your branch and report strings.

### Task 4: Shelf list and Settings stub (Wave 1, agent C)

**Owns:** everything under `ios/Sources/App/Shelf/` and `ios/Sources/App/Settings/`.
**Consumes:** `AppModel.books`, `selectedTab`; `BookListItem`; `ScreenHeader`; `Tokens`.
**Requirements:** the M1 plan's Task 14, Steps 1–2. The empty state's button sets
`model.selectedTab = .imports`. Rows show the title, the author (the row hides the author
line when there is none), "Unread" or the `fraction` as a whole percent, and a 2 pt
progress bar from `Tokens.line` and `Tokens.ink`. Settings reads the version and build
from the bundle, and its "Source code" link opens `https://github.com/KaiC5504/Shiori`
with `Link`. That opens Safari; Shiori itself makes no request.

- [ ] **Step 1: Implement** `ShelfView` and `SettingsView`.
- [ ] **Step 2: Verify.** Run `bash tools/check-app.sh`. Expected: `OK`.
- [ ] **Step 3: Commit** "Add the shelf list and the settings stub" on your branch and
  report strings.

### Task 5: Scroll reader, contents and saved progress (Wave 1, agent D)

**Owns:** everything under `ios/Sources/App/Reader/`, plus
`ios/Packages/ShioriLibrary/Sources/ShioriLibrary/ReadingPosition.swift` and
`ios/Packages/ShioriLibrary/Tests/ShioriLibraryTests/ReadingPositionTests.swift`.
**Consumes:** `BookContentSource`, `ChapterContent`, `LibraryDatabase.chapters/progress/save`,
`AppModel.database/paths/openBook`, and `DemoLaunch.showContents` through `ReaderView`'s
`showContents` parameter.
**Produces (for the reader and for M3's remapping):**

```swift
public enum ReadingPosition {
    /// fraction = (chapterIndex + block / max(blockCount, 1)) / chapterCount
    public static func progress(bookId: UUID, chapter: Chapter, chapterCount: Int,
                                content: ChapterContent, block: Int, now: Date) -> Progress
    /// The chapter matching the saved key, else the saved index clamped to the book.
    public static func chapterIndex(for progress: Progress, in chapters: [Chapter]) -> Int
    public static func block(for progress: Progress, in content: ChapterContent) -> Int
}
```

**Requirements:** the M1 plan's Task 15 ("Reader requirements" and the `ReaderModel`
interface). The model keeps at most 5 chapters loaded, centred on the visible one, and
loads them off the main actor. The scroll position is tracked per paragraph. Saves are
debounced by 0.5 s, plus `saveNow()` on disappear and when `scenePhase` becomes
`.background`.

- [ ] **Step 1: Write `ReadingPositionTests`:** `fractionCountsChaptersAndBlocks`
  (chapter 2 of 4, block 5 of 10 → 0.625), `restoresByKeyWhenIndexMoved` (saved index 3,
  key now at index 5 → 5), `fallsBackToClampedIndex` (unknown key, index 99 of 10 → 9),
  and `blockFromOffsetRoundTrips` (`block(for: progress(…block: 2…))` → 2).
- [ ] **Step 2: Implement `ReadingPosition`.** Run `bash tools/check-lib-tests.sh`.
  Expected: compiled OK. These tests run on CI in Wave 2.
- [ ] **Step 3: Implement** `ReaderModel`, `ReaderView` and `ContentsSheet` under `Reader/`.
- [ ] **Step 4: Verify.** Run `bash tools/check-app.sh`. Expected: `OK`.
- [ ] **Step 5: Commit** "Add the scroll reader with contents and saved progress" on your
  branch and report strings.

### Task 6: TestFlight pipeline files (Wave 1, agent E)

**Owns:** `.github/workflows/testflight.yml`, `scripts/testflight.py`,
`scripts/testflight-requirements.txt`.
**Requirements:** the M1 plan's Task 16, Step 1. Load the `ios-testflight` skill and copy
its templates. Set `BUNDLE_ID: com.kaichuan.shiori`, `PROJECT: ios/Shiori.xcodeproj`,
`SCHEME: Shiori` and `REPO = "KaiC5504/Shiori"`. Use `runs-on: xcode-27` with
`/Applications/Xcode_27.1.app`. Pin every action to the SHAs in the M1 plan's Task 1,
plus `actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0` (v7.1.0). Leave
`ASC_APP_ID` as the template's placeholder; the controller fills it in Task 8.

- [ ] **Step 1: Copy and fill** the three files.
- [ ] **Step 2: Verify.** Run `python scripts/testflight.py --help` and parse the
  workflow with `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/testflight.yml'))"`.
  Expected: both exit 0.
- [ ] **Step 3: Commit** "Add the TestFlight workflow and scripts" on your branch.

### Task 7: Portal steps with KaiC (Wave 1, controller)

Runs while agents A–E work. The steps are human-paced, so they cost no build time.

- [ ] **Step 1:** Walk KaiC through `ios-testflight` `reference/manual-steps.md` §3 (the App
  Store Connect record; try the name "Shiori Reader"), §4 (internal tester) and §5
  (`testflight` environment and secrets), one section at a time, in its wording.
- [ ] **Step 2: Verify.** Run `gh secret list --env testflight -R KaiC5504/Shiori`.
  Expected: every secret §5 names is listed. Note the Apple ID for `ASC_APP_ID`.

### Task 8: Merge and ship (Wave 2, controller)

- [ ] **Step 1: Merge** each agent's branch into `dev` as it lands
  (`git merge --no-edit <branch>`). Expected: no conflicts, since ownership is disjoint.
  A conflict means an agent strayed: keep the owner's version.
- [ ] **Step 2: Add reported strings** to `Localizable.xcstrings`. Set `ASC_APP_ID` in
  `testflight.yml` and the App Store Connect name and Apple ID in `CLAUDE.md`.
- [ ] **Step 3: Verify locally.** Run `swift test` for ShioriCore, then
  `bash tools/check-lib-tests.sh` and `bash tools/check-app.sh`. Expected: all green.
- [ ] **Step 4: Ship and look.** Ship `main`, watch the run, and download
  `simulator-screenshots`. Expected: the M1 plan's "Expected" lines for Tasks 12–15. The
  bar has a 16 pt inset on both sides, Shelf is selected and import rows read correctly.
  Three demo books are listed, dark mode uses the dark tokens, and the reader shows the
  heading on paper. 《兰亭集序》's contents show volume sections. Fix anything wrong on
  `dev` in one pass and ship again.

### Task 9: Check round, dry run, build 1 (Wave 3, controller + checkers)

- [ ] **Step 1, in ONE message:** the skill's §5 check round over `afcf8de..HEAD`. All of
  M1 gets checked, including Tasks 1–11, which had no review. Give the checkers both
  plans, the spec, this plan's Review Focus and both ledgers' `Ruling:` lines. In the same
  message, run `python scripts/testflight.py start --create-signing --dry-run` in the
  background. Expected: a green dry run.
- [ ] **Step 2: Fix round** per the skill's §6. Each Critical or Important finding gets a
  failing test first where one is possible. Ship once. Defer Minor findings to the ledger.
- [ ] **Step 3: Build 1.** Run `python scripts/testflight.py start --create-signing`, then
  `watch <id>` in the background. Expected: green, which means Apple has processed the
  build. Note the build number.
- [ ] **Step 4: Report and record.** Give KaiC the build number and what's in it, plus the
  M1 plan's Task 16, Step 5 test steps. Mark M1 done in `docs/roadmap.md` with the build
  number, update `docs/THIRD_PARTY.md` if anything changed, then commit and ship.

## Self-review notes

- **Coverage:** the M1 plan's Tasks 12–16 map to Tasks 1–9 here; the screens' content
  requirements are unchanged and referenced, not repeated.
- **Overlap check:** the shared files that Tasks 12–15 edited (strings, workflow, root
  view, model, demo flags) all move to Task 1 or Task 8. The Wave 1 ownership sets are
  disjoint folders plus three pipeline files.
- **The cost of parallelism:** Wave 1 agents never see each other's screens or CI
  screenshots, so layout problems surface only in Task 8, Step 4. One fix pass is planned
  for that.
