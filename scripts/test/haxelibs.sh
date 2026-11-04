#!/usr/bin/env bash
# Install the pinned haxelib libraries of the tests with `haxelib dev`, so
# RunCi finds them (`haxelib path <lib>`) and does not install its own,
# unpinned versions.
# Usage: scripts/test/haxelibs.sh [test targets, comma separated]
# Needs haxelib on the PATH and HAXELIB_PATH set (done by test-haxe.sh).
# For the cpp and cppia targets it also does what RunCi skips when hxcpp is
# installed: build the hxcpp tools (hxcpp.n), and on the development branch
# the cppia host.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

[ -n "${HAXELIB_PATH:-}" ] || die "HAXELIB_PATH is not set"
mkdir -p "$HAXELIB_PATH"

for n in $TEST_GIT_DEPS; do
    v="TEST_GIT_${n}_HAXELIB"; lib="${!v:-}"
    [ -n "$lib" ] || continue
    src="$(git_dep_src "$n")"
    v="TEST_GIT_${n}_HAXELIB_DIR"; [ -z "${!v:-}" ] || src="$src/${!v}"
    [ "$HOST_OS" = "windows" ] && src="$(cygpath -m "$src")"
    haxelib dev "$lib" "$src" >/dev/null
    log "haxelib $lib: $(haxelib path "$lib" 2>/dev/null | head -1)"
done

tests="${1:-}"
if in_list cpp "$tests" || in_list cppia "$tests"; then
    hxcpp="$(git_dep_src HXCPP)"
    if [ ! -f "$hxcpp/hxcpp.n" ]; then
        log "building the hxcpp tools"
        (cd "$hxcpp/tools/hxcpp" && haxe -D "source-header=''" compile.hxml)
    fi
    # The development branch runs cppia scripts with the host of hxcpp
    # (`haxelib run hxcpp`); 4.3 builds its own host in the tests
    # (TEST_BUILD_CPPIA_HOST=0 in its profile).
    if [ -f "$hxcpp/project/compile-cppia.hxml" ] && [ "${TEST_BUILD_CPPIA_HOST:-1}" = "1" ]; then
        suffix=""
        [ "$HOST_ARCH" = "arm64" ] && [ -f "$hxcpp/project/compile-cppia-arm64.hxml" ] && suffix="-arm64"
        stamp="$hxcpp/project/.build-haxe-cppia-$(test_platform "${BUILD_HAXE_TEST_TARGET:-$HOST_OS}" 2>/dev/null || echo host)"
        if [ ! -f "$stamp" ]; then
            log "building the cppia host of hxcpp"
            (cd "$hxcpp/project" && haxe -D "source-header=''" "compile-cppia$suffix.hxml")
            touch "$stamp"
        fi
    fi
fi
