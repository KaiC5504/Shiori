#!/usr/bin/env bash
# The Mac side of tools/mac/run.sh. Prints only summaries and errors; full logs stay in ~/logs.
set -uo pipefail
cd ~/Shiori
export PATH="$HOME/bin/xcodegen/bin:$PATH"
mkdir -p ~/logs
UDID=$(cat ~/sim.udid)
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
SIGN=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES)
status=0

build() {
  (cd ios && xcodegen generate --spec project-tests.yml --quiet) || return 1
  if xcodebuild -project ios/Shiori.xcodeproj -scheme Shiori -destination "id=$UDID" \
      -configuration Debug -derivedDataPath ~/dd "${SIGN[@]}" build > ~/logs/build.log 2>&1; then
    echo "build OK"
  else
    grep -E "error:" ~/logs/build.log | sort -u | head -40
    echo "BUILD FAILED"
    return 1
  fi
}

shots() {
  xcrun simctl install "$UDID" ~/dd/Build/Products/Debug-iphonesimulator/Shiori.app || return 1
  rm -rf shots
  bash tools/shots.sh "$UDID" shots > ~/logs/shots.log 2>&1
  echo "shots: $(ls shots | wc -l | tr -d ' ') files"
  find ~/Library/Logs/DiagnosticReports -name "Shiori*" -newer ~/logs/build.log 2>/dev/null | head -3 | sed 's/^/CRASH: /'
}

libtests() {
  for p in ShioriCore ShioriLibrary; do
    if swift test --package-path "ios/Packages/$p" > ~/logs/$p.log 2>&1; then
      echo "$p tests OK: $(grep -E "Executed|Test run with" ~/logs/$p.log | tail -1)"
    else
      grep -E "error:|✘|failed" ~/logs/$p.log | head -20
      echo "$p tests FAILED"
      status=1
    fi
  done
}

# `uitests=testName` runs one ReaderScrollTests case.
uitests() {
  local only=()
  [ -n "${1:-}" ] && only=(-only-testing:"ShioriUITests/ReaderScrollTests/$1")
  xcodebuild test -project ios/Shiori.xcodeproj -scheme ShioriUITests -destination "id=$UDID" \
    -derivedDataPath ~/dd "${SIGN[@]}" ${only[@]+"${only[@]}"} > ~/logs/uitests.log 2>&1 || status=1
  grep -E "Test Case .*(passed|failed)|error: -\[|\*\* TEST" ~/logs/uitests.log | sed -E 's/^.*\[ShioriUITests\.//' | cut -c1-200
}

for step in "$@"; do
  case $step in
    build) build || exit 1 ;;
    shots) shots ;;
    libtests) libtests ;;
    uitests) uitests ;;
    uitests=*) uitests "${step#uitests=}" ;;
    all) build || exit 1; shots; libtests; uitests ;;
    *) echo "unknown step: $step"; exit 2 ;;
  esac
done
exit $status
