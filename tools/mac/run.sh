#!/usr/bin/env bash
# Runs the build, screenshots and tests on the rented Mac (`ssh macrent`), from Windows.
# Pushes local `dev` to the Mac first (never to GitHub), then copies screenshots back to
# .superpowers/mac-shots/<time>/.
# Usage: tools/mac/run.sh build|shots|libtests|uitests|all [more...]
set -uo pipefail
cd "$(dirname "$0")/../.."
[ $# -gt 0 ] || set -- build
git push -q macrent dev 2>&1 | grep -v "^remote:" || true
ssh macrent "bash ~/Shiori/tools/mac/remote.sh $*"
status=$?
if [[ " $* " == *" shots "* || " $* " == *" all "* ]]; then
  dest=".superpowers/mac-shots/$(date +%H%M%S)"
  mkdir -p "$dest"
  scp -q -r "macrent:Shiori/shots/*" "$dest/" && echo "shots: $dest"
fi
exit $status
