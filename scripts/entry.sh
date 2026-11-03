#!/usr/bin/env bash
# Helpers shared by the build-haxe-<platform>.sh entry points. Sourced after
# common.sh, never executed directly.

# Layout of the result: HAXE_LAYOUT=standard|ceramic, or --ceramic-layout
# among the arguments. Sets LAYOUT and ENTRY_ARGS (the other arguments).
parse_entry_args() {
    LAYOUT="${HAXE_LAYOUT:-standard}"
    ENTRY_ARGS=()
    local a
    for a in "$@"; do
        case "$a" in
            --ceramic-layout) LAYOUT=ceramic ;;
            *) ENTRY_ARGS+=("$a") ;;
        esac
    done
    case "$LAYOUT" in standard|ceramic) ;; *) die "HAXE_LAYOUT must be standard or ceramic" ;; esac
    export HAXE_LAYOUT="$LAYOUT"
}

# Haxe sources: a copy of HAXE_SRC_DIR (never written to), or the clone of
# setup-haxe.sh (skipped with SKIP_SETUP=1 when it exists). Exports
# BUILD_HAXE_SOURCE for the scripts started afterwards.
prepare_sources() {
    if [ -n "${BUILD_HAXE_SOURCE:-}" ] && [ -f "$BUILD_HAXE_SOURCE.info" ]; then
        # Already prepared (by the GitHub action, where git only works from
        # Git Bash on Windows).
        HAXE_DIR="$BUILD_HAXE_SOURCE"
    elif [ -n "${HAXE_SRC_DIR:-}" ]; then
        BUILD_HAXE_SOURCE="$("$ROOT/scripts/prepare-source.sh" | tail -1)"
        export BUILD_HAXE_SOURCE
        HAXE_DIR="$BUILD_HAXE_SOURCE"
        export GIT_CEILING_DIRECTORIES="$(dirname "$BUILD_HAXE_SOURCE")"
    elif [ "${SKIP_SETUP:-0}" != "1" ] || [ ! -d "$HAXE_DIR/.git" ]; then
        "$ROOT/setup-haxe.sh"
    fi
}

# Archives (and the ceramic layout when asked), with the checks of each
# layout. Runs where the build ran (inside the glibc container for Linux).
package_target() {
    local target="$1" folder
    folder="$(layout_folder "$target" standard)/haxe"
    "$ROOT/scripts/verify-binary.sh" "$folder" "$target"
    "$ROOT/scripts/package.sh" "$target" standard
    if [ "$LAYOUT" = "ceramic" ]; then
        "$ROOT/scripts/package.sh" "$target" ceramic
        "$ROOT/scripts/verify-binary.sh" "$(layout_folder "$target" ceramic)" "$target" ceramic
    fi
}

# Copy to HAXE_OUT_DIR, if set (on the host).
export_target() {
    local target="$1"
    if [ -n "${HAXE_OUT_DIR:-}" ]; then
        "$ROOT/scripts/export-output.sh" "$target" "$LAYOUT"
    fi
}

print_summary() {
    local target="$1"
    echo
    echo "Build of $target complete. Available in:"
    echo "  - $(layout_folder "$target" "$LAYOUT")"
    echo "  - $(layout_archive "$target" "$LAYOUT")"
    if [ -n "${HAXE_OUT_DIR:-}" ]; then
        echo "  - $HAXE_OUT_DIR/$(layout_platform "$target" "$LAYOUT")"
    fi
}
