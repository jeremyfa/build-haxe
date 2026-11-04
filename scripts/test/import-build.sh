#!/usr/bin/env bash
# Put a build archive (made by another job) where test-haxe.sh expects it.
# Usage: scripts/test/import-build.sh <target> <archive>
# The sources (./haxe or HAXE_SRC_DIR) must be at the commit the archive was
# built from: its commit.txt is checked.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
source "$ROOT/scripts/entry.sh"

target="${1:?usage: import-build.sh <target> <archive>}"
archive="${2:?usage: import-build.sh <target> <archive>}"
check_target "$target"
[ -f "$archive" ] || die "$archive not found"

[ -z "${HAXE_SRC_DIR:-}" ] || prepare_sources
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
load_source_info

stage="$(stage_dir "$target")"
mkdir -p "$stage"
echo "$BUILD_ID" > "$stage/build_id.txt"
echo "$SRC_COMMIT" > "$stage/commit.txt"
folder="$(layout_folder "$target" standard)"
[ ! -e "$folder" ] || mv "$folder" "$folder.old.$(date +%Y%m%d%H%M%S)"
mkdir -p "$folder"
case "$archive" in
    *.zip)
        if command -v unzip >/dev/null; then unzip -q "$archive" -d "$folder"; else tar -xf "$archive" -C "$folder"; fi ;;
    *) tar -xzf "$archive" -C "$folder" ;;
esac
[ -f "$folder/haxe/commit.txt" ] || die "$archive does not hold a haxe/ folder"
got="$(tr -d '\r\n' < "$folder/haxe/commit.txt")"
[ "$got" = "$SRC_COMMIT" ] || die "$archive was built from $got, the sources are at $SRC_COMMIT"
log "imported $archive into $folder"
