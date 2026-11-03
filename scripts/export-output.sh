#!/usr/bin/env bash
# Copy the result of a build to HAXE_OUT_DIR, with names that do not change
# from one build to the next:
#   $HAXE_OUT_DIR/<platform>/...           the folder (haxe/, or haxe/ and neko/)
#   $HAXE_OUT_DIR/haxe-<platform>.<ext>    the archive
# <platform> is the target name (mac-universal, linux-x64, linux-arm64,
# windows-x64) for the standard layout, and mac, linux-x86_64, linux-arm64 or
# windows for the ceramic layout.
# Usage: scripts/export-output.sh <target> [standard|ceramic]
#
# HAXE_OUT_DIR belongs to the caller (it may be tracked by git, like ceramic's
# git/haxe-binary): nothing is deleted there. Every file is replaced through a
# new inode (an executable overwritten in place is killed by macOS on its next
# launch), and files that the new build does not have are reported.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: export-output.sh <target> [standard|ceramic]}"
layout="${2:-standard}"
check_target "$target"
[ -n "${HAXE_OUT_DIR:-}" ] || die "HAXE_OUT_DIR is not set"
load_profile

mkdir -p "$HAXE_OUT_DIR"
out_root="$(abs_dir "$HAXE_OUT_DIR")"
platform="$(layout_platform "$target" "$layout")"
src="$(layout_folder "$target" "$layout")"
archive="$(layout_archive "$target" "$layout")"
[ -d "$src" ] || die "$src missing (run the build script first)"
[ -f "$archive" ] || die "$archive missing (run the build script first)"

dest="$out_root/$platform"
mkdir -p "$dest"
(cd "$src" && find . -type d) | while IFS= read -r d; do
    mkdir -p "$dest/$d"
done
(cd "$src" && find . \( -type f -o -type l \)) | while IFS= read -r f; do
    if [ -L "$src/$f" ]; then
        ln -sfn "$(readlink "$src/$f")" "$dest/$f.tmp.$$"
        mv -f "$dest/$f.tmp.$$" "$dest/$f"
    else
        cp -pf "$src/$f" "$dest/$f.tmp.$$"
        mv -f "$dest/$f.tmp.$$" "$dest/$f"
    fi
done

extra="$(comm -13 \
    <(cd "$src" && find . \( -type f -o -type l \) | LC_ALL=C sort) \
    <(cd "$dest" && find . \( -type f -o -type l \) | LC_ALL=C sort) || true)"
if [ -n "$extra" ]; then
    warn "files in $dest that this build does not provide (left in place):"
    echo "$extra" | head -20 | sed 's/^/    /' >&2
fi

ext="${archive##*.}"
[ "$ext" = "gz" ] && ext="tar.gz"
cp -pf "$archive" "$out_root/haxe-$platform.$ext.tmp.$$"
mv -f "$out_root/haxe-$platform.$ext.tmp.$$" "$out_root/haxe-$platform.$ext"

log "exported to $dest and $out_root/haxe-$platform.$ext"
