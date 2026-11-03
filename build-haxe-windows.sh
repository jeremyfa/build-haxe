#!/usr/bin/env bash
# Build haxe and haxelib for Windows x64.
# Usage: ./build-haxe-windows.sh [--ceramic-layout]
#
# Runs in the Cygwin bash of an opam installation with the mingw64 port of
# OCaml: on GitHub Actions, the environment set up by ocaml/setup-ocaml
# (see .github/actions/build-haxe); on a Windows machine, opam 2.2+ with a
# mingw switch, from `opam exec -- bash ./build-haxe-windows.sh`.
#
# zlib, pcre2 and mbedtls are built from source with the mingw gcc and linked
# statically: haxe.exe only depends on system DLLs. neko is built from source
# with MSVC (CMake and Visual Studio 2022 must be available).
#
# Environment: HAXE_SRC_DIR or HAXE_REPO / HAXE_BRANCH / HAXE_COMMIT,
# HAXE_PROFILE, HAXE_PROFILE_DIR, HAXE_OUT_DIR, HAXE_LAYOUT,
# BUILD_HAXE_CACHE_DIR, SKIP_SETUP=1. See README.md.
# With BUILD_HAXE_CACHE_DIR, the opam root still comes from setup-ocaml.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/entry.sh"

[ "$HOST_OS" = "windows" ] || die "this script runs on Windows (Cygwin bash from opam)"
parse_entry_args "$@"
[ "${#ENTRY_ARGS[@]}" -eq 0 ] || die "usage: build-haxe-windows.sh [--ceramic-layout]"
target=windows-x64

"$ROOT/scripts/check-host.sh" "$target"
prepare_sources
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
log "profile: $HAXE_PROFILE, sources: $HAXE_DIR"

"$ROOT/scripts/build-neko.sh" "$target"
"$ROOT/scripts/build-deps.sh" "$target"
# opam install is retried, as on the official Haxe CI (downloads and Cygwin
# are flaky on Windows runners).
for i in 1 2 3; do
    if "$ROOT/scripts/setup-switch.sh" "$target"; then break; fi
    [ "$i" -lt 3 ] || die "opam install failed 3 times"
    warn "opam install failed, retrying ($i/3)"
done
"$ROOT/scripts/build-core.sh" "$target"
"$ROOT/scripts/build-haxelib.sh" "$target"
"$ROOT/scripts/assemble.sh" "$target"
package_target "$target"
export_target "$target"
print_summary "$target"
