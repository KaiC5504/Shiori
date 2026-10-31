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
2. Execute it task by task (`superpowers:subagent-driven-development` or
   `superpowers:executing-plans`), on `dev`.
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
- Debug builds read demo launch arguments: `-DemoData YES`, `-DemoTab shelf|imports|settings`,
  `-DemoReader <n>`, `-DemoContents YES`, `-DemoImportResults YES`. Every new screen gets
  a `shoot` line in `ios-compile.yml`, in light and in dark where it matters.

## Building and shipping

iOS app, developed on Windows with no Mac. GitHub Actions does everything:
`ios-compile.yml` compiles and screenshots on every push, and `testflight.yml` signs and
uploads when `scripts/testflight.py start` dispatches it. The full playbook, including
every manual step and known failures, is the global `ios-testflight` skill. Load it
before touching signing, `testflight.yml`, `ios/project.yml` or the compile workflow.

Identity: app `Shiori`, scheme `Shiori`, bundle id `com.kaichuan.shiori` (extensions:
none). Repo `KaiC5504/Shiori` (public). App Store Connect name: set in M1 Task 16, Apple
ID: set in M1 Task 16. Runner: `xcode-27` with Xcode 27.1 (fallback `macos-26`, Xcode
26.6). Screenshots come from an iPhone 17 Pro Max simulator.

1. Work on `dev`. Push. Wait for the compile check (`gh run list --branch dev --limit 1`,
   then `gh run watch <id> --exit-status`), and look at the `simulator-screenshots`
   artifact for every screen you touched.
2. `git checkout main && git merge --ff-only dev && git push && git checkout dev`
3. `python scripts/testflight.py start`, then `python scripts/testflight.py watch <id>` in
   the background. Green means Apple has processed the build. After any change to
   `testflight.yml`, run `start --dry-run` first.
4. Report the TestFlight build number, what changed and test steps for the phone.

The owner has authorised commit, push and Actions runs without asking. Never start a
signed build before the compile check is green. TestFlight builds go out once per
milestone, not per push.
