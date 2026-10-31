# Shiori

A local-only novel reader for iPhone in SwiftUI, built for KaiC's own EPUB, TXT and PDF
files (long Chinese web novels). Test device: KaiC's iPhone 17 Pro Max on iOS 27. The
minimum is iOS 26.

## Read first

- `docs/superpowers/specs/2026-10-31-shiori-design.md`: the approved design. Every
  feature and decision is there. Items marked "(planner's call)" or "(builder's call)"
  were not KaiC's choices and can be revisited with a reason.
- `docs/roadmap.md`: the milestones, in order, and what "done" means for each.
- `docs/superpowers/plans/`: one detailed plan per milestone. M1's exists.
- `reference/`: screenshots and recordings of the old app for look and feel only. Local,
  gitignored, and may be empty on another machine.

## Working a milestone

1. If the milestone has no plan yet, write one with `superpowers:writing-plans`, from
   the spec and from what is actually in the repo. Show it to KaiC before building.
2. Execute it with the project skill `running-a-milestone`
   (`.claude/skills/running-a-milestone/SKILL.md`): a contracts commit, then parallel
   agents in worktrees that each own their own files, merged on the local `dev` branch
   (see Branches below), then a parallel check round. KaiC approves the plan; after that
   it runs straight through to TestFlight.
3. When the roadmap's "done when" passes in the simulator screenshots, ship a TestFlight
   build (below). Report the build number, what changed, how it works, and numbered test
   steps for the phone. KaiC doesn't read code: a milestone is done when he can confirm
   it on his phone.
4. Mark the milestone done in `docs/roadmap.md`, with its build number.

## Rules

- **Clean-room:** never open, translate or copy code from
  `D:\Repos\Apps\Wenku8_Flutter`, `KaiC5504/Shiori-Flutter` or
  `mikufoxxx/Wenku8_Flutter`. Shiori borrows UI ideas from that app, which are described
  in the spec and shown in `reference/`, and no code. KaiC's other repos (DailyStore,
  BiliNative, Kazumi's CI scripts) are his and can be reused.
- **No network:** no network requests, analytics, tracking or crash SDKs (spec §12). The
  only exception is Apple's own downloadable fonts, fetched at the user's request.
- **Dependencies:** GRDB.swift, ZIPFoundation and SwiftSoup. Anything else needs a reason
  in the plan and an entry in `docs/THIRD_PARTY.md` (MIT, BSD or Apache only).
- **Localisation:** every user-facing string goes in `Localizable.xcstrings` with English
  and Simplified Chinese.
- **Layout:** never hard-code the 17 Pro Max's 440 pt width. Lay out from the available
  size, because iPad comes later.
- **Fixtures:** public-domain or generated text only. KaiC's books, including the test
  book at `D:\Tools\SoNovel\downloads\`, never enter the repo.
- **Design taste:** archive paper look, Liquid Glass only on the floating layer, the
  custom folded-paper icons, motion everywhere with Reduce Motion fallbacks. Nothing
  that looks like a generic settings dump.

## Local loop (Windows, no Mac)

- `cd ios/Packages/ShioriCore && swift test 2>&1 | grep -E "✘|Test run with"` runs the
  pure logic tests locally (Swift 6.4 for Windows). Logic that can live in `ShioriCore`
  should, because it is the only code testable without CI.
- `bash tools/check-app.sh` compiles the app in WSL against the iOS 27.1 SDK in about
  15 s (it exists from M1 Task 2 on). Run it before every push that touches `ios/`. It
  only compiles, so CI stays the gate.
- `ShioriLibrary` tests (GRDB, ZIP, decoding, the importer) run only on CI.
- **The Mac loop** (while a Mac is rented, `ssh macrent`): `bash tools/mac/run.sh build shots`
  builds, screenshots and copies the shots to `.superpowers/mac-shots/<time>/` in a few
  minutes; add `libtests` and `uitests`, or run `all`. It pushes `dev` to the Mac only, never
  to GitHub. Setup and limits are in `tools/mac/README.md`.
- Debug builds read demo launch arguments: `-DemoData YES`, `-DemoTab shelf|imports|settings`,
  `-DemoReader <n>`, `-DemoContents YES`, `-DemoImportResults YES`, and since wave 3
  `-DemoDetail <n>`, `-DemoContentsQuery <q>`, `-DemoImageViewer YES`, `-DemoPDF YES|thumbs`,
  `-DemoLayout paged`, `-DemoEffect relay|curl`, `-DemoAppearancePage screen`. Every new screen gets
  a `shot` line in `tools/shots.sh` (shared by CI and the Mac), in light and in dark where
  it matters.

## Building and shipping

iOS app, developed on Windows with no Mac. GitHub Actions does everything:
`ios-compile.yml` compiles on every push (dispatch it with `full=true` to also run the
library tests, screenshots and reader UI tests there), and `testflight.yml` signs and
uploads when `scripts/testflight.py start` dispatches it. The full playbook, including
every manual step and known failures, is the global `ios-testflight` skill. Load it
before touching signing, `testflight.yml`, `ios/project.yml` or the compile workflow.

Identity: app `Shiori`, scheme `Shiori`, bundle id `com.kaichuan.shiori` (extensions:
none). Repo `KaiC5504/Shiori` (public). App Store Connect name: `Shiori Library` ("Shiori
Reader" was taken; the home-screen name is still "Shiori"), Apple ID `6829180488`. Runner: `xcode-27` with Xcode 27.1 (fallback `macos-26`, Xcode
26.6). Screenshots come from an iPhone 17 Pro Max simulator.

### Branches (KaiC's rule)

- **GitHub holds only `main`.** Work happens on local branches: `dev` by default, plus
  local feature branches if useful. These are never pushed. Don't create other branches
  on GitHub, and don't push `dev`.
- **Everything merges into `main` locally first.** Pushing `main` is the last step, and
  it is what runs Actions.
- **Only ship what is expected to pass.** Ship when local checks pass (`swift test` for
  ShioriCore, `bash tools/check-app.sh` for the app). If CI goes red, fix it on `dev` and
  ship again.

### The loop

1. Commit on `dev`. Then ship:
   `git checkout main && git merge --ff-only dev && git push origin main && git checkout dev`.
2. Before shipping, `bash tools/mac/run.sh all` on the rented Mac and look at the shots
   for every screen you touched. Without a Mac, dispatch the compile check with
   `full=true` and read its `simulator-screenshots` artifact instead. Then wait for the
   push's compile check (`gh run list --branch main --limit 1`, then
   `gh run watch <id> --exit-status`).
3. At the end of a milestone, with `main` green:
   `python scripts/testflight.py start`, then `python scripts/testflight.py watch <id>` in
   the background. Green means Apple has processed the build. After any change to
   `testflight.yml`, run `start --dry-run` first.
4. Report the TestFlight build number, what changed and test steps for the phone.

The owner has authorised commit, push and Actions runs without asking. Never start a
signed build before the compile check is green. TestFlight builds go out once per
milestone, not per push.
