---
name: running-a-milestone
description: Use when starting or resuming a Shiori milestone from docs/roadmap.md, when KaiC says "start M<N>" or approves a milestone plan, or before any milestone-sized feature work in Shiori.
---

# Running a milestone

KaiC's words: efficiency and speed. Every build and every check is done by parallel agents. Claude plans, writes the
shared pieces, merges and ships. Building a milestone alone in the main session is the failure this skill prevents
(M1's first half was built solo and was slow).

## 1. Plan: KaiC's only stop

Read `CLAUDE.md`, the spec (`docs/superpowers/specs/2026-10-31-shiori-design.md`), the milestone in `docs/roadmap.md`
with its "done when", and what earlier milestones actually built (the code, not the old plans). For anything on
screen, look at `docs/design/concepts/` (KaiC's picks) and `reference/screens/` (the old app, look and feel only;
local and gitignored, never copied, committed or embedded). Clean-room: never open the old app's code
(`Wenku8_Flutter`, `Shiori-Flutter`). Write the plan with superpowers:writing-plans into `docs/superpowers/plans/`,
then show KaiC one screen:

1. **Done:** the numbered phone test steps.
2. **Shared pieces** Claude commits first (step 2).
3. **Agent table:** agent | builds | owns (files or folders) | tests. No file appears in two rows.
4. **Rounds:** only where this milestone differs from steps 3–7.
5. **Only the phone can prove:** what KaiC should watch for (feel, speed, the real test book).
6. **Screenshots needed:** screens or states the concepts and references don't show, if KaiC should supply them.
7. **Decisions for KaiC:** anything only he can settle (a spec clash, a product choice), each with your
   recommendation. He answers them with the go.
8. **Build number:** the next TestFlight build (the last shipped, from `docs/roadmap.md`, plus one).

Size the table by files, not features: one agent per set of files that can change without the others. A file every
piece needs gets one owner or goes in the contracts commit; the others build against its signatures, stubbed there.
Up to about 8 builders. Pure logic belongs in `ShioriCore` (tests run on Windows) or `ShioriLibrary` (tests run on
CI), so give each logic piece its tests.

Wait for his go. After it, run straight through to TestFlight; ask him only for a decision that is truly his, or a
portal step only he can do (walk him through those while the agents build).

## 2. Shared pieces (the contracts commit)

Before any agent starts, commit on `dev`: interfaces and signatures, stubs of new files with their final
signatures, design tokens, and anything two agents would both touch. In Shiori that always includes:
- `ios/project.yml` (XcodeGen; Info.plist keys, packages, targets; load the ios-testflight skill first) and
  `tools/app-check/Package.swift`, which mirrors it;
- `ios/Sources/App/Resources/Localizable.xcstrings`, with every string the milestone shows, in English and
  `zh-Hans`;
- `.github/workflows/ios-compile.yml`, with a `shoot` line for every new screen (light, and dark where it matters);
- the app model, the root view and `DemoLaunch` (new demo launch arguments for the new screens);
- package manifests and any new dependency (with its `docs/THIRD_PARTY.md` row).

`swift test` (ShioriCore), `bash tools/check-lib-tests.sh` and `bash tools/check-app.sh` green. Every brief names
this commit.

## 3. Build round

All builders in ONE message: `isolation: "worktree"`, background, one agent per independent piece. Each brief
contains, in order:

1. First command: `git log --oneline -1`; if it isn't the contracts commit, `git merge --ff-only <id>`. Worktrees
   can start on an old commit.
2. Read `CLAUDE.md`. Rules: public repo, no secrets, no network requests, clean-room, tokens only (never
   hard-coded colours or the 440 pt width), every user-facing string localised, sample text generated (never long
   passages of an existing work: the content filter blocks that output), comments per KaiC's style.
3. The job, with the spec sections and plan task it implements, and for UI the concept sheets and reference
   screenshots it should follow, by file name.
4. **Your files:** the full list; edit nothing else, and report needs outside it. Never edit the contracts
   commit's shared files.
5. Never push, merge, or switch branches. Only Claude ships `main`.
6. **Done:** committed on the branch; `bash tools/check-app.sh` OK; `swift test` in `ios/Packages/ShioriCore` green if
   it touched ShioriCore; `bash tools/check-lib-tests.sh` OK if it touched ShioriLibrary; a test per behaviour for
   logic.
7. **Report** under 600 words: branch, commits, the change per item, tests, what's not done, needs outside its
   files, and every string it used that isn't in the catalog (English and `zh-Hans`).

## 4. Merge

Merge each branch into `dev` as it finishes (`git merge --no-edit <branch>`); don't wait for all of them. Apply the
agents' "needs outside my files" and reported strings, run the three local checks, then ship once:
`git checkout main && git merge --ff-only dev && git push origin main && git checkout dev`. Watch the compile check
and download `simulator-screenshots` to the scratchpad.

## 5. Check round

All in ONE message, background, read only. Each prompt gives the diff range and the area, and asks for verified
findings only (file:line, severity, scenario, fix) under a word cap. Leave out a checker with nothing to check.

- Code review: data, import and reading position (`ShioriCore`, `ShioriLibrary`, models).
- Code review: SwiftUI screens against the spec and KaiC's taste (no generic settings dump, motion with Reduce
  Motion fallbacks, glass only on the floating layer).
- Silent failures: swallowed errors, `try?` that hides data loss, imports that fail without a row.
- Test gaps, with sketch tests that compile against the code.
- Spec and roadmap: every "done when" item, and every spec line the milestone claims.
- Comments against KaiC's comment style.
- Look check, for every screen the milestone touches: compare each CI screenshot (iPhone 17 Pro Max, 1320×2868,
  light and dark) with its concept sheet and reference screenshot. A verdict per screen: PASS, or FAIL with every
  difference listed.

## 6. Fix round

Group the findings by file. Run one fix agent per group in worktrees, with the same brief (and a contracts commit if
fixers share anything). Merge each as it lands, run the local checks, ship once, and run the look check again on
every screen that failed. Repeat until each passes, or report the screens still failing and why.

Fix small findings directly.

## 7. Ship

1. Mark the milestone done in `docs/roadmap.md` with its build number; update `CLAUDE.md` if the layout or loop
   changed.
2. With `main` green: `python scripts/testflight.py start`, then `python scripts/testflight.py watch <id>` in the
   background. After any change to `testflight.yml`, `start --dry-run` first.
3. On a failure, `gh run view <id> --log-failed` at once, then the ios-testflight skill's troubleshooting.
4. Report: the build number, what changed, how it works, the numbered phone steps from the plan, and what to watch.

## Common mistakes

| Mistake | Fix |
|---|---|
| Building a piece yourself "because it's small" | Small pieces still go to agents; you only write the shared pieces and post-merge fixes |
| Launching a round across several messages | One message per round |
| Two agents editing one file | Move it into the contracts commit or give it one owner |
| An agent adding strings or shoot lines itself | Those are shared files; it reports them and Claude adds them |
| An agent working on an old base | The ff-only line opens every brief |
| Waiting for every agent before merging | Merge each as it lands |
| Pushing to check something | Gate locally; one CI run per round, from `main` |
| Pushing `dev` or another branch | GitHub holds only `main` |
| Asking KaiC between rounds | He approves the plan; then run through |
