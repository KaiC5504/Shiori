# Local compile check (xtool)

`tools/check-app.sh` compiles the `Shiori` app target for iOS on the Windows PC, in WSL Ubuntu,
using the iOS SDK that [xtool](https://github.com/xtool-org/xtool) builds from an Xcode download.
It takes about 15 s from cold and a few seconds after small edits, instead of a CI round of
several minutes. Run it before every push that touches `ios/`.

`Package.swift` here mirrors the `Shiori` target in `ios/project.yml` for SwiftPM: the same
local packages (`ios/Packages/*`, staged without their tests), Debug defines `DEBUG` and Release
does not, Swift 5 mode, iOS 26.0. If a target, source folder or dependency changes in
`project.yml`, change it here too. CI and TestFlight never read this folder.

## What it does not cover

- It stops at the first file that fails, so it may show one error per run. Fix it and run again.
- Tests. ShioriCore's run on Windows with `swift test`; ShioriLibrary's (GRDB, ZIP, decoding,
  the importer) run only on CI.
- The simulator, launching the app and screenshots: CI only.
- The asset catalog, the string catalog, Info.plist and signing: only `.swift` files are staged.
- The SDK and compiler can differ from CI's. A clean local run is a strong hint, not proof; the
  CI compile check stays the gate.

## Setup (only on a new PC)

KaiC's PC already has all of this from DailyStore and BiliNative.

1. Download Xcode 27 (27.1 on KaiC's PC) with the owner's Apple ID from
   <https://developer.apple.com/download/all/?q=Xcode%2027> into `D:\Tools\Xcode\` (outside the
   repo; never commit it or anything extracted from it).
2. In WSL: `bash tools/app-check/setup-wsl.sh /mnt/d/Tools/Xcode/Xcode_27.1.xip`. It installs
   Swift 6.4.1 (swiftly), xtool 1.22.2 and the SDK (`~/.swiftpm/swift-sdks/darwin.artifactbundle`).
   No Apple ID login: compiling needs none.

Builds are staged in `~/.cache/shiori-check/<checkout>/` inside WSL; delete that folder to start
clean. The full log of the last run is `last-build.log` there.
