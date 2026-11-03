#!/usr/bin/env bash
# Build every platform reachable from a Mac: macOS universal, Linux arm64 and
# Linux x64 (Docker). Windows is built on GitHub Actions.
# Usage: ./build-haxe-all.sh
# Same environment variables as the platform scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

[ "$HOST_OS" = "mac" ] || die "build-haxe-all.sh runs on macOS"

"$ROOT/setup-haxe.sh"
export SKIP_SETUP=1

"$ROOT/build-haxe-mac.sh" universal
KEEP_DOCKER_RUNNING=1 "$ROOT/build-haxe-linux.sh" arm64
"$ROOT/build-haxe-linux.sh" x64

HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
short="$(git -C "$HAXE_DIR" rev-parse --short=10 HEAD)"
echo
echo "All builds complete. Archives:"
for t in mac-universal linux-arm64 linux-x64; do
    for f in "$ROOT/build/archives/haxe-$HAXE_PROFILE-$short-$t".*; do
        [ -f "$f" ] && echo "  - $f"
    done
done
