#!/usr/bin/env bash
# Archive an assembled folder.
# Usage: scripts/package.sh <target> [--ceramic-layout]
# Output: build/archives/haxe-<profile>-<short>-<target>.{zip,tar.gz}
#   The archive contains a single haxe/ folder.
#   --ceramic-layout: haxe/ and neko/ side by side, as in
#   ceramic's git/haxe-binary (<platform>/{haxe,neko}). Rewrites the haxelib
#   rpath to ../neko. Suffix "-ceramic" on the archive name.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: package.sh <target> [--ceramic-layout]}"
layout="${2:-}"
check_target "$target"
load_profile

os="$(target_os "$target")"
stage="$(stage_dir "$target")"
short="$(cut -c1-10 "$stage/commit.txt")"
base="$ROOT/build/$HAXE_PROFILE/$target/$short"
[ -d "$base/haxe" ] || die "$base/haxe missing (run scripts/assemble.sh $target)"

name="haxe-$HAXE_PROFILE-$short-$target"
src="$base"

if [ "$layout" = "--ceramic-layout" ]; then
    [ "$os" != "windows" ] || die "--ceramic-layout is only needed for mac and linux"
    name="$name-ceramic"
    src="$base-ceramic"
    [ ! -e "$src" ] || die "$src already exists, remove it first"
    mkdir -p "$src"
    cp -R -P "$base/haxe" "$src/haxe"
    mv "$src/haxe/neko" "$src/neko"
    case "$os" in
        mac)
            # Changing the rpath invalidates the signature: sign again.
            install_name_tool -rpath @executable_path/neko @executable_path/../neko "$src/haxe/haxelib" 2>/dev/null
            msg="$(codesign --force --sign "${SIGN_IDENTITY:--}" "$src/haxe/haxelib" 2>&1)" || die "codesign failed: $msg"
            ;;
        linux)
            patchelf --set-rpath '$ORIGIN/../neko' "$src/haxe/haxelib"
            ;;
    esac
fi

mkdir -p "$ROOT/build/archives"
case "$os" in
    mac|windows)
        archive="$ROOT/build/archives/$name.zip"
        rm -f "$archive"
        if command -v zip >/dev/null; then
            (cd "$src" && zip -q -r -y "$archive" .)
        else
            powershell -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$src")\\*' -DestinationPath '$(cygpath -w "$archive")'"
        fi
        ;;
    linux)
        archive="$ROOT/build/archives/$name.tar.gz"
        rm -f "$archive"
        mtime="$(git -C "$HAXE_DIR" show -s --format=%cI HEAD)"
        if tar --version 2>/dev/null | grep -q 'GNU tar'; then
            (cd "$src" && tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="$mtime" -czf "$archive" .)
        else
            (cd "$src" && tar -czf "$archive" .)
        fi
        ;;
esac

log "archive: $archive"
