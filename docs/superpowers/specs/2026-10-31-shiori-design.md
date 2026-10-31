# Shiori: design

Status: draft for KaiC's approval. Written 2026-10-31 from a planning session in the
Wenku8_Flutter repo. Everything marked **(builder's call)** or **(planner's call)** was
not decided by KaiC; the rest was.

## 1. What this is and why

Shiori is a local-only novel reader for iPhone, written in SwiftUI. KaiC reads Chinese
web novels from his own EPUB and TXT files, often thousands of chapters long (the test
book has 4,834). Reading, importing and settings are the parts he actually uses.

Shiori replaces a Flutter fork of mikufoxxx/Wenku8_Flutter (`KaiC5504/Shiori-Flutter`).
That fork works, but it is someone else's codebase under GPL with an online catalogue cut
out of it. Shiori is KaiC's own: a new repo with fresh history, not a GitHub fork, MIT
licensed, native Swift. It borrows UI ideas from the old app (the 3D spine shelf, the
archive paper look, folded-paper icons, the paragraph relay page turn, the paper page
turn) and none of its code.

Success looks like this: KaiC reads every day in Shiori on his iPhone 17 Pro Max instead
of the old app; any EPUB or TXT he owns imports without fuss, the 4,834-chapter test book
included; and the app feels presented and alive, not like a settings list with a reader
attached.

## 2. Goals, non-goals, anti-goals

### Goals (v1.0)

- Shelf with a 3D spine carousel above a list or grid, a Continue card, series,
  categories, tags, authors, search and reading history.
- Import of EPUB, TXT, PDF and ZIP from the Files picker, a watched folder, and Open
  in / Share, with files copied into the app.
- A reader for EPUB and TXT with scroll and paged layouts, three page-turn effects, the
  full typography set, paper themes, notes, highlights, bookmarks, search, illustrations,
  auto-scroll, read-aloud with system voices, and reading moments.
- A PDF reader that shows original pages.
- Reading statistics.
- A first-launch guide, two UI languages with an in-app switch, light and dark mode,
  accent colours, a custom icon set, Liquid Glass on the floating layer, subtle haptics.

### Non-goals (cut on purpose, may come later)

| Cut | Note |
| --- | --- |
| Online catalogue, accounts, cloud shelf, LAN sync | Never. Shiori is local-only. |
| Edge / online TTS voices | System voices only. |
| Third-party font downloads | Apple's own downloadable fonts and imported files only. |
| MOBI, AZW3, DOCX, RTF, HTML, Markdown, FB2 | Formats are EPUB, TXT, PDF, ZIP. |
| Offline dictionary (MDX, StarDict) | |
| Simplified ↔ Traditional conversion | |
| Footnote popups and in-book links | Link text renders as plain text; tapping it does nothing. |
| Vertical text (竖排) | |
| Home-screen widgets | Would need an App Group (portal work). Later, maybe. |
| Backup and restore, iCloud sync | Later milestone. Until then data lives only on the phone: it survives an iCloud device backup and restore, but deleting the app wipes it. |
| WebDAV / NAS import | |
| Importing data from the old app | Fresh start. |
| iPad, two-page spread | Later. Layouts stay adaptive so it can come. |
| Performance toggles, frame-rate settings, update checker | Native performance makes them unnecessary; TestFlight handles updates. |

### Anti-goals (would make it a failure even if it works)

- Any network traffic beyond what is listed in §12. No analytics, tracking, crash
  reporting or ad SDKs, ever.
- Code ported or translated from the old app, its fork, or upstream (see §15).
- A static, information-dump UI that looks AI-generated. Screens should feel presented:
  motion, depth, the archive paper identity.
- Glass everywhere. Glass is for the floating layer only (§4.4).
- A reader that stutters or makes you wait on a 5,000-chapter book.

## 3. Constraints

- **Platform:** iPhone, iOS 26.0 minimum. Built with Xcode 27.1 (iOS 27.1 SDK) on GitHub's
  `xcode-27` runner image, which is in public preview as of 2026-10. If that image queues
  badly, fall back to `macos-26` with Xcode 26.6. iOS 27-only APIs go behind
  `if #available(iOS 27, *)` with an iOS 26 path. KaiC's phone runs iOS 27.
- **Target device:** iPhone 17 Pro Max, 440 × 956 pt at 3x, ProMotion 120 Hz. Tune for it
  first, but never hard-code its width: layouts must adapt so iPad can come later.
- **No Mac.** KaiC develops on Windows. All builds run on GitHub Actions: an unsigned
  compile check with simulator screenshots on every push, and signed TestFlight builds
  per milestone. The global `ios-testflight` skill is the playbook; load it before
  touching the project file, workflows or signing.
- **Project:** XcodeGen (`ios/project.yml`), Swift 5 language mode, no project-level
  xcconfig. These settings come from the pipeline template.
- **Identity:** app and scheme `Shiori`, bundle id `com.kaichuan.shiori`, display name
  `Shiori` in both languages. No app extensions. No capabilities that need Apple portal
  work (no App Group, no iCloud, no push). Background audio is an Info.plist background
  mode, not an entitlement, so it is fine.
- **Repo:** `KaiC5504/Shiori`, public (macOS minutes are free on public repos), MIT,
  branches `main` and `dev`. The old fork is renamed `KaiC5504/Shiori-Flutter`.
- **Dependencies:** MIT, BSD or Apache licensed only, listed in `docs/THIRD_PARTY.md`
  and on an in-app Licenses page.

## 4. Look and feel

### 4.1 Identity

- **App icon:** the paper-cut silhouette with closed eyes and violet butterfly ribbons,
  in light, dark and tinted variants. It is KaiC's own asset. Xcode-ready 1024 px RGB
  files and `Contents.json` are in `branding/AppIcon.appiconset/`; 4096 px masters are in
  `branding/`.
- **Name:** "Shiori" everywhere, including the Chinese UI. No Japanese characters.

### 4.2 Colour

Paper and ink tokens. These are the starting values; the builder may tune them, but
they must keep the same character.

| Token | Light | Dark |
| --- | --- | --- |
| `paper` (page background) | `#F2ECE3` | `#1F1F1F` |
| `surface` (cards, rows) | `#FBF8F3` | `#262626` |
| `line` (hairlines, tracks) | `#DDD5CA` | `#343434` |
| `ink` (text) | `#24222A` | `#EDEDED` |
| `inkSecondary` | `#6F6A66` | `#8F8F8F` |
| `ribbon` (brand only) | `#7650C9` | `#B79CF2` |

**Dark mode** is neutral charcoal with no tint, like the old app. KaiC picked it from the
concept samples (`docs/design/concepts/4-tones.png`, option A). **Default appearance**
follows the phone; Settings and the guide can pin Light or Dark.

**Accent.** The default accent is **Ink**: monochrome, so controls, progress and
selection use the ink colour. The icon's ribbon violet is a brand touch only. It appears
on the bookmark ribbon marking the last-read book on the 3D shelf, in onboarding, and on
the About page, never as the everyday accent. KaiC found violet as an accent "hard to
read and weird".

Accent choices in Settings, each a light/dark pair:

| Name | Light | Dark |
| --- | --- | --- |
| Ink (default) | `#24222A` | `#EDEDED` |
| Iris | `#6E6190` | `#B3A8CC` |
| Seal vermilion | `#A9402B` | `#E58A6F` |
| Indigo | `#2E4A78` | `#94AEDA` |
| Fog pine | `#4F6B5F` | `#93B5A6` |
| Shallow sea | `#476C85` | `#8DB3CC` |
| Rouge | `#8E5864` | `#D3A0AC` |
| Wheat | `#7F6A3C` | `#CDB789` |
| Graphite | `#5F636A` | `#A5A9B0` |
| Ribbon violet | `#7650C9` | `#B79CF2` |

Plus **Custom**: the system colour picker or hex entry, and **Pick from a photo**, which
offers 5 dominant colours from an image. A custom accent must reach 4.5:1 contrast
against `paper`. If it doesn't, Shiori derives a darker light-mode and lighter dark-mode
variant and says so.

### 4.3 Shape and type

- Small radii: 4 pt for panels, 8 pt for cards and rows, capsules for floating controls.
- The UI font is the system font (SF Pro / PingFang). **(planner's call: no app-font
  setting; the reader font is separate, §7.4.)**
- **Masthead:** every top-level screen opens with a small monospace code line, e.g.
  `01 / SHELF`, `02 / IMPORT`, `03 / SETTINGS`, then the localised large title. The code
  line stays Latin in both languages; it is a design element.
- **Archive codes:** KaiC chose to keep the old app's archive flavour, made Shiori's own:
  - **Section labels:** a monospace, letter-spaced label ("COLLECTION / SHELF"), then a
    hairline rule ending in a small square dot, then a bold section title.
  - **Serials:** each book gets a short serial, `SH-` plus six digits, stable per book
    and derived from its id. It shows above the title in list rows and on generated
    covers.
  - **Spine numbers:** 3D shelf books carry `NO.001` style numbers by shelf position.
- **Grid:** a very faint 100 pt square grid sits behind the headers, like drafting paper,
  and fades out under the content.
- **Reference:** `docs/design/concepts/` holds the concept sheets KaiC chose from.

### 4.4 Glass

Liquid Glass (`glassEffect`) is used **only on the floating layer**: the bottom bar, the
reader's top bar and bottom tool dock, and floating buttons such as the shelf header
buttons. Tint it with `paper` so it stays calm over the page (the builder tunes the
strength). Everything else is solid paper: book covers, pages, cards, list rows, settings
rows. System menus, alerts and the keyboard are system glass anyway. Use
`GlassEffectContainer` and `glassEffectID` so the bar's selection lens and menus can
morph. Reduce Transparency is respected by the system.

### 4.5 Icons

Shiori has its own icon set of about 60 icons, in the folded-paper-card style KaiC liked
in the old app. The style, described in words:

- A 24 pt grid with a 1.5 pt ink stroke.
- Shapes are built from cards and sheets: rectangles with a small folded corner, stacked
  spines, a ribbon tab.
- A faint ink fill that deepens when active.
- Each icon has an animatable `activity` value from 0 to 1. Selecting it plays a small
  physical motion: the shelf's spines lift one after another, the import card slides
  down into a tray, the settings card's slider knobs shift.

Draw them as SwiftUI `Shape`s or `Canvas` code. Never copy or trace the old app's
drawings. A debug-only icon gallery screen shows every icon at rest and active, so the
compile check can screenshot it.

Needed at least: shelf, import, settings, book, search, history, filter, sort, layout
(list / grid), add, more, close, back, forward, contents, bookmark, bookmarked, note,
highlight, copy, share, edit, delete, typography, sliders, brightness, moon (night), sun,
theme (paper), image, play, pause, previous, next, headphones, speed, timer, voice,
folder, folder-add, document, refresh / scan, check, warning, info, language, lock
(rotation), stats, calendar, flame (streak), quote, tag, person (author), category, link
(folder linked), eye, eye-off.

### 4.6 Motion

KaiC wants all of it. Every animation falls back to a short crossfade under Reduce
Motion, plus Shiori's own "Reduce motion" switch.

- **Bar:** the selection lens springs between lanes, and you can drag it along the bar,
  selecting on release.
- **Opening a book:** the cover flies from the shelf or detail page and peels open into
  the reader, like paper lifting. The reverse plays on close.
- **Menus:** menus and sheets grow out of the button that opened them (glass morph).
- **Reveals:** content on a newly shown screen arrives in a short stagger.
- **3D shelf:** the scroll-driven wave (§6.2).
- **New imports:** a newly imported book lands on the shelf with a small arrival
  animation.
- **Settings sub-pages:** they expand out of the row that was tapped.

### 4.7 Haptics

Subtle haptics for bar selection, page turns, toggles, long-press selection and import
finished, with an on/off switch in Settings (on by default).

## 5. App structure

### 5.1 Tabs and the bottom bar

Three tabs: **Shelf · Import · Settings** (书架 · 导入 · 设置).

The bottom bar is custom. Apple's tab bar shrinks to a short capsule with three tabs, and
KaiC wants the full width.

- **Placement:** floats 16 pt from the left and right screen edges, which makes it
  408 pt wide on the 17 Pro Max. It sits just above the home indicator. **(builder's
  call: exact bottom gap; the old app used about 12 pt above the safe area.)**
- **Size:** 64 pt tall, capsule-shaped, Liquid Glass tinted with paper.
- **Lanes:** three equal lanes. Each holds a custom icon (24 pt) over a label (11 pt).
- **Selection:** a glass lens sits behind the selected lane (KaiC chose this over a dash
  or an icon pill; `docs/design/concepts/2-bar.png`, option A). Tapping a lane springs the
  lens to it. Dragging along the bar moves the lens with the finger and selects on
  release. The selected icon plays its `activity` animation.
- **Content:** screens scroll under the bar, with enough bottom padding that the last row
  clears it.
- **Reader:** the bar hides while the reader is open.
- **Orientation:** app screens are portrait-only on iPhone, so the bar has no landscape
  layout for now. **(planner's call; the bar's landscape form comes with iPad.)**

Each tab keeps its own navigation stack. The reader is presented full screen above the
tabs with the cover-flight transition.

### 5.2 First-launch guide

The guide runs on first launch. It can be skipped after step 1 and replayed from
Settings → About. Each step has a live preview and a big Continue button.

1. **Language:** 中文 or English, preselected from the phone's language. Choosing one
   switches the guide's language immediately.
2. **Appearance:** System, Light or Dark, plus the accent swatches, previewed on a mini
   shelf.
3. **Books folder:** "Choose a folder" opens the folder picker, "Use Shiori's own
   folder" uses the app's folder in Files, or Skip. It explains in one line that new
   books there are imported automatically.
4. **Reading defaults:** font, text size, and layout (scroll or pages, with the page-turn
   effect), previewed on a sample page of public-domain text.
5. **Gesture tour:** an interactive page. Tap the right side to turn, tap the left to go
   back, tap the centre for menus, long-press to select. Each gesture ticks off when you
   try it, and Done appears after all four.

### 5.3 Launch

The app opens on the Shelf. When there is a last-read book, a **Continue** card sits at
the top: cover, title, current chapter, progress percentage and a Continue button.

## 6. Shelf (书架)

### 6.1 Header

The header has the large title and the masthead `01 / SHELF`, plus two round
glass buttons: **History** and **Search**. There is no import button here; import lives
in its tab and in the empty shelf.

Under each section label, a filter row holds:

- a category pill (All books, a category, Uncategorised, By author), which opens a sheet
- the book count
- a **Filter** button (shelf filter, sort, grouping)
- a **Layout** button that switches between "3D shelf + list" and "3D shelf + grid" and
  sets the grid size (small, medium, large)

### 6.2 The 3D spine shelf

KaiC chose the spine wave over a single featured book or a cover carousel
(`docs/design/concepts/1-shelf.png`, option B).

Books stand in a row as solid 3D blocks, seen slightly from above and in front, so you
see their spines and top edges. The row scrolls sideways and snaps book by book. The
scroll position drives a wave: the book at the centre (the crest) is pulled forward off
the shelf and turned to show its cover, and its neighbours lift partway. Scrolling moves
the crest smoothly from book to book, and the ordering must never pop mid-scroll.

- **Spines:** each spine shows the vertical title and the author. Its colour comes from
  the cover.
- **Last-read book:** carries the violet ribbon bookmark (the brand touch).
- **Tapping the crest book:** opens the detail page, or the reader if "Open book
  directly" is on, with the cover flight. Tapping any other book scrolls it to the crest.
- **Shelf filter:** All, Recently read, Unread, Reading, Finished. **Shelf sort:**
  Original, Recently read, Recently added, Title.
- **Featured count:** 1 to 100 books, default 30. With fewer books than that, the row
  repeats books so the shelf looks full.
- **Rendering:** the builder chooses. SwiftUI 3D transforms, a custom Metal or SceneKit
  scene, or a mix. It must hold 120 fps while scrolling on the 17 Pro Max and stay
  smooth with 500 books.

The reference screenshots show the look.

### 6.3 List and grid

Below the carousel is the full library.

- **List rows:** cover, title, author, status (Unread / Chapter N / Finished) and a thin
  progress bar.
- **Grid:** covers with title under them, in three sizes.
- **Grouping:** by category (user categories plus Uncategorised), by author, or none.
  Sort by recently read, recently added or title.
- **Series:** a series shows as one entry with a volume count. Opening it lists the
  volumes in order.
- **Long-press menu:** Continue, Details, Edit, Add to category, Remove.

### 6.4 Search and history

- **Search** looks across all fields or just title, author, tag or ID. `#word` searches
  tags. Recent searches are kept.
- **History** is a timeline of opened books with dates. You can remove one entry, or
  clear all while keeping progress.

### 6.5 Book detail

- The cover, which opens large when tapped.
- Title, and the author, which opens all of that author's books.
- Tags and category.
- This book's reading time and progress.
- The table of contents grouped by volume, with collapsible volumes. It must be
  virtualised for 5,000 chapters.
- **Start reading** or **Continue** (accent filled), and **Edit**. Both float as glass
  buttons at the bottom while the contents scroll underneath.

**Layout** (from `reference/screens/06-book-detail-dark.png`, as an idea, not a copy):

- The cover sits on the left with a big bold title beside it.
- Under the title: the author with a chevron, the chapter count, the import date, and
  the book's `SH-` serial in a small stamped box.
- A "Reading: <chapter>" progress card drawn with corner-bracket frame marks, showing
  the in-chapter progress.
- A `02 / CONTENTS` section label with the item count and an order toggle. Rows are
  numbered (`01`, `02`…), and the last-read row says "Last read".

### 6.6 Edit book

- Title, author, tags and category.
- **Cover:** choose from Photos or Files, or reset to the extracted or generated cover.
- **Series:** merge volumes. Pick books, order them and name the series. Shiori suggests
  a series on import when file names look like volumes (第一卷, 卷二, Vol. 1, (1), etc.).
- **Remove book:** deletes the copied file and its data, after a confirmation. Shiori
  remembers the removal (by content hash and source path), so the watched folder doesn't
  bring the book back. The import log shows "Skipped: you removed this" with an Import
  anyway button. **(planner's call)**
- **TXT only:** "Re-detect encoding" and "Re-split chapters" (with the current TXT
  settings). Progress and notes are remapped (§7.3). Without this, a wrong encoding
  guess could only be fixed by removing the book and losing its data. **(planner's
  call)**

**Generated covers.** A book without a cover gets a typographic one in the archive style:
title, author, a monospace code line and rule lines. Its paper colour comes from a hash
of the title.

## 7. Reader

### 7.1 Formats and layouts

- **EPUB and TXT** open in Shiori's text reader, which has two layouts: **Vertical
  scroll** and **Horizontal pages**.
- **PDF** opens in the PDF reader (§7.12).

### 7.2 Page-turn effects (paged layout)

There are three effects, switchable in reader settings, at three speeds (gentle,
standard, brisk). KaiC wants both paper-turn versions so he can compare them while he
reads.

1. **Paragraph relay (段落接续), the default.** The paper stays still. The outgoing page's
   paragraphs slide out in the turn direction one after another in a short stagger, and
   the incoming page's paragraphs slide in the same way. During a swipe it follows the
   finger. A tap plays it in full.
2. **Paper turn, Shiori's own 3D sheet.** The page is a sheet hinged at the spine (the
   left edge for left-to-right reading).
   - Dragging from the right lifts it. It rotates around the spine while its free edge
     leads with a soft bend.
   - The back of the sheet shows a faint mirror of the page's ink, as if seen through
     the paper. The page underneath gets a moving shadow.
   - The sheet follows the finger's position and speed. Releasing past halfway, or with
     a fast flick, completes the turn; otherwise the sheet falls back.
   - Build it on Metal: a deformed grid mesh (about 28 × 6) textured with page
     snapshots. SceneKit or RealityKit are acceptable only if they look and perform the
     same.
   - It must hold 120 fps. This is the riskiest piece of the app, so the roadmap gives
     it its own spike.
3. **Page curl, Apple's.** `UIPageViewController` with `.pageCurl`, wrapped for SwiftUI.

Under Reduce Motion, every effect becomes a quick crossfade.

### 7.3 Text engine

All of this is the builder's call, within these requirements:

- **Parsing:** parse EPUB XHTML into Shiori's own content model (paragraphs, headings,
  emphasis, images, ruby if present), then lay it out with the current typography.
- **Pagination:** paginate one chapter at a time, lazily, and cache the result keyed by
  book, chapter, typography and page size. Never paginate a whole book up front.
- **Position:** store the reading position as (chapter key, character offset in that
  chapter's normalised text), so it survives font, size and rotation changes. A chapter
  key must stay stable when a book is updated with new chapters (§8.4) or a TXT is
  re-split: for example, the chapter title plus its occurrence number, with a content
  hash as a tie-breaker. Re-imports then remap positions and anchors, using the quoted
  text to repair any that drift. **(planner's call on the method; the requirement that
  progress and notes survive updates is KaiC's.)**
- **Scroll layout:** a continuous, lazily loaded run of chapters with chapter headers.
- **Speed:** the 4,834-chapter test book must open at the saved position within 300 ms
  of the cover flight ending. Turning pages and scrolling must never drop frames.
- **Engine:** TextKit 2 or Core Text, either is fine.

### 7.4 Typography (the full set)

- **Font:**
  - system fonts
  - Apple's downloadable Chinese fonts (Songti, Kaiti, Yuanti, Libian, Weibei, Hannotate
    and others), downloaded on request through Core Text
  - TTF or OTF files the user imports
- **Text:**
  - size from 10 to 27 pt
  - weight: regular, medium or bold
  - letter spacing from −0.5 to 3
  - line height from 1.3 to 2.2
- **Margins:** left, right, top and bottom, either linked or separate, 0 to 80 pt.
- **Paragraphs:**
  - gap from 0 to 32 pt, or "as in the book"
  - first-line indent (2 em) on or off
  - justify on or off
- **Scope:** "All books" or "This book only", with a Reset.

### 7.5 Themes and screen

- **Paper themes:** Follow appearance, Milk (奶白), Parchment (羊皮纸), Light moss (浅苔) and
  Night (夜读). Night has a text-brightness slider from 35 to 100%.
- **Custom background:** your own colour or photo, with a strength slider and fill or
  fit.
- **Day/night:** a one-tap toggle in the tool dock.
- **Screen options:**
  - hide the status bar
  - show the time and battery in the reader's info strip
  - keep the screen awake
  - brightness: follow the system, or use the reader's slider (a vertical swipe on the
    left edge adjusts it)
  - a chapter entrance animation on or off
- **Hands-free:** auto-scroll in the scroll layout (speed in points per second), or
  auto-turn in the paged layout (every N seconds).
- **Orientation:** the reader rotates freely, with a rotation lock in its settings.
  **(planner's call: every other screen is portrait-only on iPhone.)**

### 7.6 Taps and gestures

- **Tap zones:** three layouts. Standard: left goes back, right goes forward, the centre
  opens the menus. Right-handed and left-handed variants move the zones. An option makes
  both sides go forward.
- **Swipes:** swipe to turn pages. A vertical swipe on the left edge sets brightness.
- **Selection:** long-press selects a sentence, with handles to adjust.
- **Exiting:** the top bar's back button. **(builder's call: whether an edge swipe also
  exits, as long as it can't fight page turns.)**

### 7.7 Reader chrome

A tap in the centre shows the floating glass chrome.

KaiC chose this layout from the samples (`docs/design/concepts/5-reader-menus.png`,
option B; the reference is `reference/screens/08-reader-menus-dark.png`).

- **Top:** a round glass back button, the book title in the middle (opens the detail
  page), and a round glass Listen button. The page's info footer fades while the menus
  are open.
- **Bottom: one glass panel** your thumb reaches, holding:
  - a line with the chapter name on the left and "chapter / total · %" on the right in
    the archive monospace
  - the chapter slider with previous and next chapter buttons
  - a hairline, then five tools: Contents, Notes (bookmarks, notes and highlights),
    Appearance (Aa), Find, Day/Night
- **Info footer** (on by default; KaiC chose it from `7-reader-info.png`, option B):
  - one slim line at the bottom of the page
  - the chapter name on the left
  - "page / pages in chapter · time · battery" on the right, in the archive monospace
  - no header: the chapter title is part of the text

  Settings can switch it to the old header + footer, a hairline progress line only, or
  nothing.
- **Sheets** (Contents, Notes, Find) rise from the bottom as glass sheets with a grabber,
  a bold title and a round close button, as in the reference screenshots 10–13.
- **Find:** the sheet toggles between This chapter and Whole book.

**Appearance (Aa) sheet:** KaiC chose controls inline over tiles or tabs
(`6-reader-aa.png`, option B). The page re-lays out live behind the sheet. In order:

1. Text size (A− / value / A+) and the current font (opens the font list).
2. Line spacing: Compact, Standard, Loose, Custom.
3. Paper theme swatches.
4. Page turn: Scroll, Paragraph relay, Paper, Curl.
5. "More typography, screen and gestures" opens the full set (§7.4–§7.6).

### 7.8 Contents

Volumes collapse and expand. You can search chapters, the current chapter is marked, the
order can be reversed, and tapping jumps. It is virtualised for 5,000 chapters.

### 7.9 Notes, highlights and bookmarks

- **Selection toolbar:** Copy, Highlight, Note, Bookmark, Share as image.
- **Highlight styles:** underline, highlight, box, or none (a note with no visible mark).
- **Colours:** original (ink), amber, mint, lake blue, rose and wisteria.
- **Notes:** any highlight can carry a note, and its range can be adjusted afterwards.
- **Anchoring:** chapter key plus start and end offsets, plus the quoted text, so
  marks can be repaired if offsets drift (§7.3).
- **Per book:** a list of bookmarks and notes, with jump-to.
- **Bookmark library** (from Settings): every bookmark and note across all books, with
  search, filtering by book and colour, and sharing an excerpt as an image (a quote card
  in a few archive styles, saved or shared through the share sheet).

### 7.10 Search

- **Find in chapter:** highlights matches, with next and previous.
- **Search the whole book:** runs in the background and streams results with the
  chapter name and a snippet. It stops at 500 hits, and tapping a result jumps there.

### 7.11 Illustrations, reading moments

- **Illustrations:**
  - inline EPUB images scale to fit the page
  - tapping one opens a zoom viewer: pinch, double-tap, swipe between the chapter's
    images, and save to Photos (add-only permission)
  - an "Illustrations in this volume" grid
- **Reading moments** (a toggle in Settings, on by default):
  - small cards at milestones: first hour in a book, every 100 chapters read, a 7-day
    streak
  - a book-end card when you finish a book: time spent, days, highlights made
  - they look like archive cards and never block reading for more than a tap

### 7.12 PDF reader

- PDFKit shows the original pages. **Layout:** pages left to right, with optional page
  curl, or a vertical continuous scroll.
- **Viewing:** pinch zoom, an auto-crop-margins toggle, a thumbnail grid, and contents
  from the PDF outline.
- **Marks and search:** page bookmarks, and search through PDFKit.
- **Not available:** typography and paper themes. **(builder's call: an optional
  dark-mode page invert.)**
- **Progress:** the page index.

### 7.13 Listening (听书)

System voices only (`AVSpeechSynthesizer`), fully offline.

- **Voices:** a voice per language (Mandarin, Cantonese, Taiwanese Mandarin, English...).
  Shiori explains how to download Enhanced and Premium voices in iOS Settings.
- **Controls:**
  - play and pause; previous and next paragraph; previous and next chapter
  - speed from 0.5× to 3.0×, and a pause between paragraphs of 0 to 3 s
- **Follow-along:** highlights the sentence being spoken and turns pages automatically.
- **Sleep timer:** 15, 30 or 60 minutes, or end of chapter.
- **Start point:** start from the reading position, or resume where listening stopped.
- **Background play:** the `audio` background mode, with lock-screen and headphone
  controls (Now Playing info with the cover, and remote commands).
- **Mini player:** shown in the reader chrome and above the bar on the shelf while
  playing.

## 8. Import (导入)

### 8.1 The Import tab

The masthead is `02 / IMPORT`.

- **Import files:** a big button that opens the document picker (multiple selection;
  EPUB, TXT, PDF, ZIP).
- **Watched folder card:**
  - the folder name, last scan time and the count of new books found
  - Scan now, Auto-import on launch, and format chips (EPUB, TXT, PDF, ZIP)
  - Change folder and Disconnect
  - the folder is held as a security-scoped bookmark
  - "Use Shiori's own folder" points it at the app's Documents folder, which shows in
    Files as "Shiori"
- **Recent imports:** batches with a result for each file: added, already in library,
  skipped (and why), or failed (and why, in plain words).
- **TXT settings** (one tap deeper):
  - encoding: Auto, UTF-8, GB18030, Big5 or UTF-16
  - chapter rules: presets for 第X章 / 回 / 节, volume lines (第X卷), "Chapter N" and
    numbered lines, plus a custom regex
  - a preview of the chapters detected in a chosen file

### 8.2 Sources

- **Files picker:** iCloud Drive, On My iPhone, USB drives and SMB servers all appear
  there.
- **Watched folder:** scanned on launch when auto-import is on, and on Scan now. New or
  changed files are imported; already-imported ones are skipped by path, size and date,
  then by content hash.
- **Open in / Share:** Shiori registers document types for EPUB, TXT, PDF and ZIP, so it
  appears in the share sheet as "Open in Shiori". Incoming files are copied in, and a
  toast offers to open the book. No share extension.

### 8.3 Pipeline

1. **Copy** the file into Shiori's storage (§10). Files are always copied; nothing is
   read in place after import.
2. **Deduplicate** by SHA-256 of the file content. A match reports "already in library".
3. **Parse:**
   - **EPUB:** read the container, OPF, nav or NCX, and spine. Extract the title,
     author, cover and table of contents with volumes. DRM-protected files fail with a
     clear message.
   - **TXT:** detect the encoding (BOM first, then UTF-8 validity, then
     `NSString.stringEncoding(for:)` heuristics; GB18030 and Big5 matter most). Split
     into chapters with the active rules, convert to UTF-8, and store the chapters. With
     no chapters detected, split into numbered parts of about 20k characters.
   - **PDF:** title and author from the document attributes or the file name. The cover
     is a first-page thumbnail.
   - **ZIP:** expand the entries. Decode GBK/GB18030 file names when the UTF-8 flag is
     absent. Import supported files inside; nested ZIPs are skipped.
4. **Recognise updates** (§8.4) before treating the file as a new book.
5. **Suggest a series** when names look like volumes.
6. **Show the book** on the shelf with the arrival animation.

Fixed-layout or image-only EPUBs (`rendition:layout` set to `pre-paginated`, such as
comics or scans) are refused with a clear "not supported yet" message. **(planner's
call: KaiC's books are reflowable web novels.)**

**Limits:**

- Size: EPUB, PDF and ZIP up to 512 MiB; TXT up to 128 MiB.
- At most 2,000 files per scan.
- iCloud placeholders (`.icloud`) trigger a download and are picked up on the next scan.
- The `Inbox` folder is skipped.

**Bar to clear:** the 4,834-chapter test EPUB imports in under 10 s on the 17 Pro Max.

### 8.4 Book updates

KaiC downloads ongoing web novels with SoNovel and downloads them again when new chapters
come out. When an incoming file is a newer version of a book already in the library,
Shiori **updates it in place** rather than adding a second copy:

- **Same book:**
  - EPUB: the same `dc:identifier`. SoNovel writes the source page URL there, e.g.
    `trxs-https://www.trxs.cc/tongren/11502/1.html`.
  - Otherwise: the same normalised title and author.
  - TXT: the same title (from the file name, or the first line) and author, if
    present.
- **Different file:** the content hash differs, otherwise it is simply "already in
  library".
- **What happens:** the stored file is swapped and the book re-parsed. Progress,
  bookmarks, notes, highlights, history, category, tags, series membership and a custom
  cover are all kept, remapped by chapter key (§7.3).
- **Import log:** says "Updated: +37 chapters" (or "Updated: changed" when the count
  didn't grow).
- **On the shelf:** the book briefly shows an "Updated" badge.
- **Lost marks:** a note whose text can't be found in the new version stays in the
  book's notes list, flagged "Text changed".

## 9. Settings (设置)

The tab's masthead is `03 / SETTINGS`.

The layout is a summary header followed by compact grouped rows that change in place,
with deeper pages one tap away. KaiC chose it from the samples
(`docs/design/concepts/3-settings.png`, option B).

1. **Reading summary header.** Today's minutes, the current streak and this week's mini
   bars. Tapping it opens Stats.
2. **Bookmarks and notes**, which opens the library (§7.9).
3. **General:**
   - Language (中文 / English), which switches instantly
   - Open book directly (skips the detail page)
   - Haptics
   - Reading moments
4. **Appearance:**
   - Mode: System, Light or Dark
   - Accent (§4.2)
   - Reduce motion in Shiori
5. **Reading:**
   - default typography (opens the reader settings over a sample page)
   - page-turn default
   - tap zones
   - fonts: Apple's downloadable fonts (download and remove) and imported fonts (add
     and remove)
6. **Listening:** a default voice per language, and the default speed.
7. **Import:** the TXT settings, and a shortcut to the watched folder.
8. **Storage:** space used by books and caches, Clear caches, and Reading history.
9. **About:**
   - version and build
   - Licenses (third-party notices)
   - Source code (a link to the GitHub repo)
   - Replay guide

**Stats page:**

- an overview: total time, books finished, chapters read
- a rhythm chart by hour of day
- a calendar heatmap with streaks
- time per book
- a custom date range

No report export.

**Reading time:** a session is counted while the reader is in front and the user is
active. Two minutes without a touch, a page turn or listening pauses it.

## 10. Data and storage

**(planner's call, the builder may change it with a reason in the plan)**

- **Books** live at `Application Support/Books/<book id>/`: the original file, the cover
  image, the parsed index (TOC and chapter offsets), and TXT chapter text as UTF-8.
- **Caches** (pagination, thumbnails) live in `Caches/` and can be rebuilt any time.
- **Documents** is exposed in Files (`UIFileSharingEnabled`,
  `LSSupportsOpeningDocumentsInPlace`) as the "Shiori's own folder" option for the
  watched folder.
- **Database:** SQLite through GRDB. Tables cover books, series, categories, tags,
  progress, bookmarks and notes, reading sessions, history and the import log. Simple
  preferences live in `UserDefaults`.
- **Identifiers:** UUIDs for books, and a content hash for deduplication.
- **Migrations:** the schema is versioned from the first build, so a TestFlight update
  never loses KaiC's data.

## 11. Localisation

- **Strings:** Simplified Chinese and English, in a String Catalog. Every user-facing
  string is localised from the first milestone, with no hard-coded text.
- **Switching:** the language follows the guide's choice, can be switched in Settings
  without relaunching, and should agree with iOS's per-app language setting. **(builder's
  call: how the instant switch is done.)**
- **Tone:** plain and short. Errors say what happened and what to do.

## 12. Network and privacy

Shiori makes no network requests of its own. The only traffic it causes is Apple's:
downloading Apple's Chinese fonts when the user asks (Core Text), and voices the user
downloads in iOS Settings. Other requirements:

- a privacy manifest (`PrivacyInfo.xcprivacy`) with the required-reason APIs (UserDefaults,
  file timestamps)
- `ITSAppUsesNonExemptEncryption = false`
- photo access is add-only, for saving illustrations

## 13. Third-party code

**(planner's call: buy plumbing, build what users see)**

- **ZIPFoundation** (MIT): EPUB and ZIP reading.
- **GRDB.swift** (MIT): SQLite.
- **SwiftSoup** (MIT): XHTML parsing, if `XMLParser` proves too strict for real-world
  EPUBs.

Nothing else without a reason in the plan and an entry in `docs/THIRD_PARTY.md`.

## 14. Testing and verification

- **Core tests:** pure logic lives in a local Swift package (`ios/Packages/ShioriCore`)
  with unit tests run in CI. It covers EPUB parsing, TXT encoding detection and chapter
  splitting, ZIP name decoding, deduplication, series suggestion, and position and
  anchor mapping.
- **Fixtures:**
  - small EPUB and TXT files we make ourselves (public-domain text, never a
    copyrighted book in the repo)
  - a generated 5,000-chapter EPUB, built at test time, for performance. It must match
    the real test book's structure (below).
  - an "updated" pair (the same identifier, with chapters appended) to test §8.4
- **Screenshots:** Debug builds take launch arguments for demo data and for opening a
  given screen. The compile check screenshots every main screen on an **iPhone 17 Pro
  Max simulator** in light and dark, and those screenshots are reviewed before
  anything ships.
- **On the phone:** a TestFlight build per milestone, with numbered test steps for KaiC.
  The real test book stays on his PC at
  `D:\Tools\SoNovel\downloads\全民转职：死灵法师！我即是天灾(慢途的猪).epub`. It is never
  committed, and KaiC imports it on the phone.

**The test book, measured 2026-10-31:**

| Property | Value |
| --- | --- |
| Source | SoNovel, generator `Ebook-lib 0.20.0` (EPUB 3 with NCX and nav) |
| Size | 18.8 MB |
| Spine | 4,835 items: one XHTML file per chapter, plus a 简介 (intro) |
| Contents | Flat: 4,834 NCX entries, no volumes |
| Chapter files | Median 8 KB, largest 555 KB |
| Markup | One stylesheet. Each chapter is `<h2>` then `<p>` paragraphs. |
| Images | Only the cover |
| Identity | `dc:identifier` is the source URL |
| Layout | Reflowable (no `rendition:layout`) |

This is what KaiC's library looks like: SoNovel web-novel EPUBs. Treat other generators
as a robustness concern, not a design driver.

## 15. Clean-room rule

Shiori's code is written from this document and the reference screenshots, never from
the old app's code.

- **Don't port:** do not open, translate or copy code from `Wenku8_Flutter`,
  `Shiori-Flutter` or `mikufoxxx/Wenku8_Flutter`.
- **Unclear behaviour:** ask KaiC.
- **What carries over:** only the app icon, which is KaiC's own.
- **Screenshots:** `reference/screens/` holds screenshots and screen recordings of the
  old app, supplied by KaiC, for look and feel. They stay local and gitignored, because
  they show real book covers. The build session runs on this PC, so it can see them.
  Watching recordings of the app is look-and-feel reference, not code, so it fits this
  rule.

## 15a. Release scope

The smallest Shiori KaiC will switch to for daily reading, the **reading core**:

- **Import:** the picker, the watched folder, and Open in / Share.
- **Shelf:** the 3D carousel and the list.
- **Reader:**
  - scroll and paged layouts
  - paragraph relay and Apple's page curl
  - full typography and paper themes
  - contents
  - saved progress
  - book updates (§8.4)

Notes and highlights, search, listening, stats and the rest follow in that order (see
`docs/roadmap.md`).

Shiori's own 3D paper turn does not block any release. It ships when it holds 120 fps on
the 17 Pro Max; until then, relay and curl cover paged reading.

**Look approval:** the 3D shelf gets a look-approval step before it is polished. A
TestFlight prototype is checked against the reference recordings, so the most expensive
screen isn't built twice.

**Bundle id:** `com.kaichuan.shiori` is new. The Flutter fork was only ever an unsigned
IPA under `org.mewx.wenku8Flutter.sourcePreview`, and KaiC's daily app is the upstream
Wenku8 app. Neither has an App Store Connect record under this id, so the first install
can't replace anything, and Shiori gets its own App Store Connect record (pipeline
setup).

## 16. Left to the builder

- Exact spacing, sizes and curves beyond those given.
- The architecture and file layout.
- How pagination is cached.
- How the 3D shelf is rendered.
- Metal versus SceneKit for the paper turn.
- How the instant language switch works.
- The exact icon drawings, within the style.
- The test structure.

Each choice goes in the milestone's plan with a one-line reason.
