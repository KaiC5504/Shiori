#!/usr/bin/env bash
# Compiles ShioriLibrary and its tests for the iOS simulator in WSL, without running them, so
# a test that doesn't compile is caught before CI (the only place they run). Setup is the same
# as tools/check-app.sh: tools/app-check/README.md.
#
#   bash tools/check-lib-tests.sh
set -uo pipefail

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        here=$(cd "$(dirname "$0")" && pwd -W)
        drive=$(printf '%s' "${here:0:1}" | tr '[:upper:]' '[:lower:]')
        MSYS_NO_PATHCONV=1 exec wsl.exe -d Ubuntu --exec bash "/mnt/$drive${here:2}/check-lib-tests.sh" "$@"
        ;;
esac

repo=$(cd "$(dirname "$0")/.." && pwd)
sdk="$HOME/.swiftpm/swift-sdks/darwin.artifactbundle"
if [ ! -f "$sdk/toolset-swb.json" ] || [ ! -x "$HOME/.local/share/swiftly/bin/swift" ]; then
    echo "check-lib-tests: no Swift toolchain or Darwin SDK in WSL. See tools/app-check/README.md." >&2
    exit 3
fi
# WSL's PATH also carries the Windows one, where D:\Tools\Swift would shadow the Linux toolchain.
export PATH="$sdk/toolset/bin:$HOME/.local/share/swiftly/bin:/usr/local/bin:/usr/bin:/bin"
export XCODE_EXTRA_PLATFORM_FOLDERS="$sdk/Developer/Platforms"
unset SDKROOT

# One stage per checkout, so worktrees building in parallel don't collide.
stage="${XDG_CACHE_HOME:-$HOME/.cache}/shiori-libtests/$(printf '%s' "$repo" | md5sum | cut -c1-12)"
mkdir -p "$stage"
exec 9>"$stage/.lock"
flock 9
rsync -a --delete --exclude .build --exclude .swiftpm "$repo/ios/Packages/ShioriCore/" "$stage/ShioriCore/"
rsync -a --delete --exclude .build --exclude .swiftpm "$repo/ios/Packages/ShioriLibrary/" "$stage/ShioriLibrary/"

swift build --package-path "$stage/ShioriLibrary" --scratch-path "$stage/.build" --build-system swiftbuild \
    --triple arm64-apple-ios-simulator --toolset "$sdk/toolset-swb.json" --build-tests \
    -Xswiftc -diagnostic-style=llvm >"$stage/log.raw" 2>&1
status=$?
sed -e 's/\x1b\[[0-9;]*m//g' "$stage/log.raw" >"$stage/log.txt"

diagnostics=$(grep -E '\.swift:[0-9]+:[0-9]+: (error|warning): ' "$stage/log.txt" | grep -v '/checkouts/' \
    | sed "s#$stage/#ios/Packages/#g" | awk '!seen[$0]++')
[ -n "$diagnostics" ] && printf '%s\n' "$diagnostics"
if printf '%s\n' "$diagnostics" | grep -q ': error: '; then
    echo "FAILED: ShioriLibrary tests don't compile (full log: $stage/log.txt)"
    exit 1
fi
# Linking the test bundle pulls in the host's zlib and fails in WSL. Reaching the link step
# means every Swift file compiled, which is all this check is for.
if [ $status -eq 0 ] || grep -q 'ShioriLibraryTests-product: ld64.lld' "$stage/log.txt"; then
    echo "OK: ShioriLibrary and its tests compile"
else
    tail -n 15 "$stage/log.txt"
    echo "FAILED: the build stopped before linking (full log: $stage/log.txt)"
    exit 1
fi
