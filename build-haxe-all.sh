#!/usr/bin/env bash
# Build every platform reachable from a Mac: macOS universal, Linux arm64 and
# Linux x64 (Docker). Windows is built on GitHub Actions.
# Usage: ./build-haxe-all.sh [--ceramic-layout]
# Same environment variables as the platform scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

[ "$HOST_OS" = "mac" ] || die "build-haxe-all.sh runs on macOS"

if [ -z "${HAXE_SRC_DIR:-}" ]; then
    "$ROOT/setup-haxe.sh"
    export SKIP_SETUP=1
fi

"$ROOT/build-haxe-mac.sh" universal "$@"
KEEP_DOCKER_RUNNING=1 "$ROOT/build-haxe-linux.sh" arm64 "$@"
"$ROOT/build-haxe-linux.sh" x64 "$@"

echo
echo "All builds complete. Archives:"
ls -1 "$ROOT/build/archives/" | tail -n 12 | sed "s|^|  - $ROOT/build/archives/|"
