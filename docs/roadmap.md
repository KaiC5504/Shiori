# Shiori roadmap

What gets built in what order, and when KaiC can test it. The design is
`docs/superpowers/specs/2026-10-31-shiori-design.md` (the spec); section numbers below
point into it.

How each milestone runs:

1. At the start of a milestone, the build session writes its detailed plan with the
   `superpowers:writing-plans` skill, as `docs/superpowers/plans/<date>-m<N>-<name>.md`.
   It plans from the spec and from what the earlier milestones actually built. M1's plan
   already exists.
2. Work happens on the local `dev` branch. GitHub holds only `main`. Finished work merges
   into `main` locally, then `main` is pushed. Each push runs the compile check and
   simulator screenshots on an iPhone 17 Pro Max simulator.
3. When the milestone's "done when" list passes in screenshots, a TestFlight build ships
   from `main`, and KaiC gets the build number, what changed and numbered test steps.
4. KaiC tests on his phone. Fixes go in before the next milestone starts.

Rough sizes are relative, not dates.

## M1: Thin slice, end to end (TestFlight 1)

The whole loop works, ugly bits allowed.

- **Pipeline:** repo, XcodeGen project, compile check with screenshots, TestFlight
  workflow, local WSL compile tool, and KaiC's portal steps (App Store Connect record,
  tester, secrets).
- **`ShioriCore`:** EPUB container, package and contents parsing; TXT chapter splitting;
  chapter keys; book identity; file-name metadata.
- **`ShioriLibrary`:** database schema v1, storage, TXT decoding, EPUB reading, chapter
  content, and the importer (copy, deduplication).
- **App:**
  - the full-width floating bar (§5.1) with the lens and drag, using placeholder system
    icons
  - Import tab: Import files and the results list
  - Shelf tab: a plain list with progress
  - Settings tab: a stub with the version
  - reader: the scroll layout, contents, saved progress
- **Strings:** Chinese and English for everything on screen.

**Done when:** the 4,834-chapter test book imports from Files on KaiC's phone, opens, and
reopens at the same paragraph after the app is killed. A SoNovel TXT does the same.

Plan: `docs/superpowers/plans/2026-10-31-m1-thin-slice.md`.

## M2: The look (TestFlight 2)

- **Design system:** colour tokens (§4.2), the accent system with presets, custom accents
  with the contrast fix, and pick-from-photo.
- **Shape and glass:** masthead and shape rules (§4.3), Liquid Glass on the floating layer
  (§4.4), the bar's final look.
- **Icons:** the custom icon set, all ~60 with `activity` motion, plus the debug icon
  gallery (§4.5).
- **Motion and haptics:** springs, staggered reveals, menus growing from buttons,
  settings sub-pages expanding from their row, Reduce Motion handling (§4.6), haptics
  (§4.7).
- **Settings tab structure (§9):** instant language switch, appearance mode, accent,
  reduce motion, haptics. The rows for later features are absent until they exist.

**Done when:** every M1 screen wears the archive look in light and dark, the bar
animates its icons, and switching language or accent changes everything at once.

## M3: Import, complete (TestFlight 3)

- **Import tab hub (§8.1)** and its import log.
- **Watched folder:**
  - choose a folder, or use Shiori's own folder
  - auto-scan on launch, Scan now, format chips
  - iCloud placeholders, the 2,000-file cap, the `Inbox` skip
- **Open in / Share** via document types (§8.2).
- **More formats:** ZIP with GBK names, PDF import (stored, with title and cover).
- **TXT settings:** encoding override, chapter rules, a preview.
- **Book updates in place (§8.4)**, with remapping by chapter key, plus TXT re-detect
  and re-split.
- **Removal memory:** removed books are remembered so the watched folder doesn't
  re-add them.

**Done when:** dropping a re-downloaded, longer copy of the test book into the watched
folder updates the existing book ("Updated: +N chapters"), with progress intact.

## M4a: Reader engine (TestFlight 4)

- **Text engine:** the content model, lazy per-chapter pagination with a cache, and
  positions stored as (chapter key, offset) (§7.3).
- **Paged layout:** paragraph relay (default) and Apple's page curl, at three speeds
  (§7.2).
- **Full typography (§7.4)** with system fonts. Scope: all books or this book.
- **Reading sessions** are recorded from here on, so stats have history by M8.
- **Speed:** the 300 ms open bar on the test book, and no dropped frames turning pages.

**Done when:** KaiC reads the test book in paged mode with relay and curl. Changing font
size keeps his place.

## M4b: Reader, complete (TestFlight 5)

- **Themes and screen:** paper themes and a custom background (§7.5), screen options,
  brightness, keep awake, rotation with a lock.
- **Chrome (§7.7):** top bar, chapter slider, tool dock, info strip.
- **Navigation:** contents with volumes, search and reverse (§7.8); tap zones and
  gestures (§7.6).
- **Fonts:** Apple's downloadable fonts and imported fonts (§7.4).
- **Illustrations:** inline images, the zoom viewer, saving to Photos, the volume grid
  (§7.11).
- **PDF reader (§7.12)**, so imported PDFs open.

**Done when:** everything in §7.1–§7.8, §7.11's illustrations and §7.12 works on the
phone.

## M5: Shelf (TestFlight 6, then 7)

- **M5a, look approval:** a prototype of the 3D spine carousel (§6.2) ships alone, to be
  checked against the reference recordings. Polish waits for KaiC's OK.
- **M5b:** the polished carousel, the Continue card (§5.3), list and grid with sizes,
  grouping and sort, categories, series (merge plus suggestions), tags and authors,
  search, history (§6.3–6.4), the detail page (§6.5), edit book with generated covers
  (§6.6), the cover flight and arrival animations, and "Open book directly".

**Done when:** M5b is the reading core (§15a). **This is v0.9: KaiC switches to Shiori
for daily reading.**

## M6: Notes and search (TestFlight 8)

- **Marks:** selection toolbar, highlight styles and colours, notes, adjustable ranges,
  per-book lists, bookmarks (§7.9).
- **Bookmark library** with share-as-image quote cards.
- **Search:** find in chapter, and whole-book search with streamed results (§7.10).
- **Book updates** carry notes over, with the "Text changed" flag (§8.4).

## M7: Listening (TestFlight 9)

- **Speech:** `AVSpeechSynthesizer` with a voice per language.
- **Playback:** controls, follow-along, sleep timer, the start point (§7.13).
- **Background:** audio, lock screen and Now Playing, headphone controls, and the mini
  player.

## M8: Stats, moments and the guide (TestFlight 10)

- **Stats:** the Stats page (overview, rhythm, heatmap, streaks, per book, date range)
  and the Settings summary header (§9).
- **Reading moments** (§7.11).
- **First-launch guide**, all five steps, with Replay guide (§5.2).

## M9: Paper turn and hands-free (TestFlight 11)

- **Paper turn:** Shiori's own 3D sheet on Metal (§7.2). A spike can start any time after
  M4a, in parallel with M5–M8, because it only needs page snapshots. It ships when it
  holds 120 fps on the 17 Pro Max. Until then it doesn't block anything.
- **Hands-free:** auto-scroll and auto-turn (§7.5).

## M10: Polish, then v1.0

- **Accessibility:** VoiceOver labels on every control, Dynamic Type for the UI
  (reader text has its own sizes), contrast checks.
- **Quality:** a performance pass with a 500-book library, empty states and error copy,
  the Licenses page and About (§9).
- **Data safety:** schema migrations tested against a copy of a real database.
- **v1.0** on TestFlight.

## After v1.0

Candidates, none promised, in KaiC's likely order:

- **Backup and restore:** export everything to one file. Until this exists, deleting the
  app loses notes and progress.
- **iCloud sync** of progress, notes and the library index (needs a portal step).
- **Home-screen widgets** (needs an App Group, a portal step).
- **iPad**, with a two-page spread and the bar's landscape form.
