#!/usr/bin/env bash
# Build haxe and haxelib for Windows x64.
# Usage: ./build-haxe-windows.sh
#
# Runs in the Cygwin bash of an opam installation with the mingw64 port of
# OCaml: on GitHub Actions, the environment set up by ocaml/setup-ocaml
# (see .github/workflows/build-haxe.yml); on a Windows machine, opam 2.2+
# with a mingw switch, from `opam exec -- bash ./build-haxe-windows.sh`.
#
# zlib, pcre2 and mbedtls are built from source with the mingw gcc and linked
# statically: haxe.exe only depends on system DLLs. neko is built from source
# with MSVC (CMake and Visual Studio 2022 must be available).
#
# Environment: HAXE_REPO, HAXE_BRANCH, HAXE_COMMIT, HAXE_PROFILE, SKIP_SETUP=1.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

[ "$HOST_OS" = "windows" ] || die "this script runs on Windows (Cygwin bash from opam)"
target=windows-x64

"$ROOT/scripts/check-host.sh" "$target"

if [ "${SKIP_SETUP:-0}" != "1" ] || [ ! -d "$HAXE_DIR/.git" ]; then
    "$ROOT/setup-haxe.sh"
fi
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
log "profile: $HAXE_PROFILE"

"$ROOT/scripts/build-neko.sh" "$target"
"$ROOT/scripts/build-deps.sh" "$target"
"$ROOT/scripts/setup-switch.sh" "$target"
"$ROOT/scripts/build-core.sh" "$target"
"$ROOT/scripts/build-haxelib.sh" "$target"
out="$("$ROOT/scripts/assemble.sh" "$target" | tail -1)"
"$ROOT/scripts/verify-binary.sh" "$out" "$target"
"$ROOT/scripts/package.sh" "$target"

echo
echo "Windows build complete. Available in:"
echo "  - $out"
echo "  - $ROOT/build/archives/haxe-$HAXE_PROFILE-$(cut -c1-10 "$out/commit.txt")-$target.zip"
