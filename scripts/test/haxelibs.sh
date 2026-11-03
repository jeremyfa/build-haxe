#!/usr/bin/env bash
# Install the pinned haxelib libraries of the tests with `haxelib dev`, so
# RunCi finds them (`haxelib path <lib>`) and does not install its own,
# unpinned versions.
# Usage: scripts/test/haxelibs.sh
# Needs haxelib on the PATH and HAXELIB_PATH set (done by test-haxe.sh).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

[ -n "${HAXELIB_PATH:-}" ] || die "HAXELIB_PATH is not set"
mkdir -p "$HAXELIB_PATH"

for n in $TEST_GIT_DEPS; do
    v="TEST_GIT_${n}_HAXELIB"; lib="${!v:-}"
    [ -n "$lib" ] || continue
    src="$(git_dep_src "$n")"
    [ "$HOST_OS" = "windows" ] && src="$(cygpath -m "$src")"
    haxelib dev "$lib" "$src" >/dev/null
    log "haxelib $lib: $(haxelib path "$lib" 2>/dev/null | head -1)"
done
