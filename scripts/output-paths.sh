#!/usr/bin/env bash
# Print where the result of a build is, as KEY=VALUE lines:
# FOLDER (haxe/, or haxe/ and neko/ for the ceramic layout), ARCHIVE,
# BUILD_ID, and OUT_FOLDER / OUT_ARCHIVE when HAXE_OUT_DIR is set.
# Usage: scripts/output-paths.sh <target> [standard|ceramic]
# Same environment as the build scripts (HAXE_PROFILE, HAXE_PROFILE_DIR...).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: output-paths.sh <target> [standard|ceramic]}"
layout="${2:-${HAXE_LAYOUT:-standard}}"
check_target "$target"
if [ -n "${HAXE_SRC_DIR:-}" ] && [ -z "${BUILD_HAXE_SOURCE:-}" ]; then
    export BUILD_HAXE_SOURCE="$(abs_dir "$HAXE_SRC_DIR")"
    HAXE_DIR="$BUILD_HAXE_SOURCE"
fi
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile

# Windows paths as D:/a/... (understood by GitHub actions and Cygwin).
topath() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}
archive="$(layout_archive "$target" "$layout")"
echo "FOLDER=$(topath "$(layout_folder "$target" "$layout")")"
echo "ARCHIVE=$(topath "$archive")"
echo "BUILD_ID=$(stage_build_id "$target")"
if [ -n "${HAXE_OUT_DIR:-}" ]; then
    platform="$(layout_platform "$target" "$layout")"
    ext="${archive##*.}"
    [ "$ext" = "gz" ] && ext="tar.gz"
    echo "OUT_FOLDER=$HAXE_OUT_DIR/$platform"
    echo "OUT_ARCHIVE=$HAXE_OUT_DIR/haxe-$platform.$ext"
fi
