#!/usr/bin/env bash
# The one shot list, used by the compile check and by tools/mac/run.sh, so the two can't
# drift apart. Expects Shiori already installed on the booted simulator.
# Usage: tools/shots.sh <udid> <outdir>
set -uo pipefail
UDID=$1
OUT=$2
APP=com.kaichuan.shiori
mkdir -p "$OUT"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true

xcrun simctl terminate "$UDID" $APP 2>/dev/null || true
xcrun simctl launch "$UDID" $APP >/dev/null
sleep 15
xcrun simctl io "$UDID" screenshot "$OUT/01-first-launch.png" >/dev/null

# Debug builds read demo launch arguments (DemoLaunch.swift). `shot` uses the real, empty
# library; `shoot` adds -DemoData YES, a throwaway library with generated books.
shot() {
  name=$1; wait=$2; shift 2
  xcrun simctl terminate "$UDID" $APP 2>/dev/null || true
  xcrun simctl launch "$UDID" $APP "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
}
shoot() { name=$1; wait=$2; shift 2; shot "$name" "$wait" -DemoData YES "$@"; }

xcrun simctl ui "$UDID" appearance light
shot 02-shelf-empty 8 -DemoTab shelf
shoot 03-import 10 -DemoTab imports -DemoImportResults YES
shoot 04-shelf 10 -DemoTab shelf -DemoUpdated YES
shoot 05-settings 8 -DemoTab settings
shoot 06-reader 12 -DemoTab shelf -DemoReader 1
shoot 07-contents 12 -DemoTab shelf -DemoReader 1 -DemoContents YES
shoot 08-icons 8 -DemoIcons YES
# The simulator's own language is Chinese here, so English on screen proves the in-app switch wins.
shoot 09-settings-en 8 -DemoTab settings -DemoLanguage en -AppleLanguages "(zh-Hans)"
shoot 10-accent 8 -DemoTab settings -DemoSettingsPage accent -DemoAccent sealVermilion
shoot 11-txt-settings 8 -DemoTab settings -DemoSettingsPage txt
shoot 16-app-icon 8 -DemoTab settings -DemoSettingsPage appIcon
shoot 12-import-folder 12 -DemoTab imports -DemoWatchedFolder YES -DemoImportResults YES
shoot 13-reader-chrome 12 -DemoTab shelf -DemoReader 1 -DemoChrome YES
shoot 14-appearance 12 -DemoTab shelf -DemoReader 1 -DemoAppearance YES
shoot 14b-appearance-more 12 -DemoTab shelf -DemoReader 1 -DemoAppearance YES -DemoAppearancePage more
shoot 14c-appearance-fonts 12 -DemoTab shelf -DemoReader 1 -DemoAppearance YES -DemoAppearancePage fonts
shoot 15-reader-parchment 12 -DemoTab shelf -DemoReader 1 -DemoTheme parchment
shoot 18-detail 12 -DemoTab shelf -DemoDetail 1
shoot 19-contents-search 14 -DemoTab shelf -DemoLongBook YES -DemoReader 1 -DemoContents YES -DemoContentsQuery 120
shoot 20-illustration 12 -DemoTab shelf -DemoReader 1 -DemoJumpTo 2
shoot 21-image-viewer 12 -DemoTab shelf -DemoReader 1 -DemoJumpTo 2 -DemoImageViewer YES
shoot 22-pdf 12 -DemoTab shelf -DemoPDF YES
shoot 22b-pdf-thumbnails 12 -DemoTab shelf -DemoPDF thumbs
shoot 23-screen 12 -DemoTab shelf -DemoReader 1 -DemoAppearance YES -DemoAppearancePage screen
shoot 24-paged 12 -DemoTab shelf -DemoReader 1 -DemoLayout paged
shoot 25-curl-back 14 -DemoTab shelf -DemoReader 1 -DemoLayout paged -DemoEffect curl -DemoCurlFreeze YES

xcrun simctl ui "$UDID" appearance dark
shoot 04-shelf-dark 10 -DemoTab shelf -DemoUpdated YES
shoot 05-settings-dark 8 -DemoTab settings
shoot 06-reader-dark 12 -DemoTab shelf -DemoReader 1
shoot 08-icons-dark 8 -DemoIcons YES
shoot 10-accent-dark 8 -DemoTab settings -DemoSettingsPage accent -DemoAccent sealVermilion
shoot 12-import-folder-dark 12 -DemoTab imports -DemoWatchedFolder YES -DemoImportResults YES
shoot 13-reader-chrome-dark 12 -DemoTab shelf -DemoReader 1 -DemoChrome YES -DemoTheme night
shoot 18-detail-dark 12 -DemoTab shelf -DemoDetail 1
shoot 24-paged-dark 12 -DemoTab shelf -DemoReader 1 -DemoLayout paged -DemoTheme night
shoot 25-curl-back-night 14 -DemoTab shelf -DemoReader 1 -DemoLayout paged -DemoEffect curl -DemoCurlFreeze YES -DemoTheme night
xcrun simctl ui "$UDID" appearance light
ls "$OUT"
