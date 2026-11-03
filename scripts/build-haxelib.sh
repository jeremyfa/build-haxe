#!/usr/bin/env bash
# Build haxelib for a target from the haxe binary in the stage directory.
# Usage: scripts/build-haxelib.sh <target>
# Output: build/<profile>/<target>/stage/haxelib[.exe]
#
# The Makefile targets differ between branches (HAXELIB_LFLAGS vs
# HAXELIB_LDFLAGS, `nekotools boot` with or without -c), so the same steps are
# done here for every branch:
#   haxe client.hxml -> run.n -> nekotools boot -> haxelib
# haxelib looks for libneko in the neko/ folder next to it.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: build-haxelib.sh <target>}"
check_target "$target"
load_profile

os="$(target_os "$target")"
stage="$(stage_dir "$target")"
neko="$(neko_dir "$target")"
exe=""
[ "$os" = "windows" ] && exe=".exe"

haxe_bin="${HAXE_FOR_HAXELIB:-$stage/haxe$exe}"
[ -x "$haxe_bin" ] || die "$haxe_bin not found (run scripts/build-core.sh $target)"
[ -x "$neko/nekotools$exe" ] || die "neko missing (run scripts/fetch-neko.sh $target)"

export PATH="$neko:$PATH"
case "$os" in
    mac) export DYLD_FALLBACK_LIBRARY_PATH="$neko" ;;
    linux) export LD_LIBRARY_PATH="$neko" ;;
esac

src="$HAXE_DIR/extra/haxelib_src"
cd "$src"

std="$HAXE_DIR/std"
[ "$os" = "windows" ] && std="$(cygpath -m "$std")"
log "compiling haxelib client to neko bytecode"
HAXE_STD_PATH="$std" "$haxe_bin" client.hxml

case "$os" in
    mac)
        nekotools boot -c run.n
        # One universal binary linked against the universal libneko. libneko
        # itself requires macOS 11.0, so haxelib uses the same minimum.
        cc -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 run.c -o "$stage/haxelib" \
            -I"$neko/include" -L"$neko" -lneko -Wl,-rpath,@executable_path/neko
        ;;
    linux)
        nekotools boot -c run.n
        gcc -O2 run.c -o "$stage/haxelib" -I"$neko/include" -L"$neko" -lneko \
            -Wl,-rpath,'$ORIGIN/neko'
        ;;
    windows)
        nekotools boot run.n
        mv -f run.exe "$stage/haxelib.exe"
        ;;
esac

# run.n is tracked in the haxelib repository: restore it so the submodule
# stays clean and can move to another commit.
git -C "$src" checkout -- run.n 2>/dev/null || true
rm -f run.c

log "haxelib built: $stage/haxelib$exe"
