#!/usr/bin/env bash
# Build haxe and haxelib for macOS.
# Usage: ./build-haxe-mac.sh [arm64|x86_64|universal] [--from-stages] [--ceramic-layout]
#   default: universal
#   --from-stages: only combine existing arm64 and x86_64 stages
#   --ceramic-layout: also produce the ceramic layout (same as HAXE_LAYOUT=ceramic)
#
# x86_64 is built under Rosetta: the whole chain (opam, OCaml, C libraries,
# dune) runs as x86_64 processes, so no cross-compiler is needed.
#
# Environment: HAXE_SRC_DIR or HAXE_REPO / HAXE_BRANCH / HAXE_COMMIT,
# HAXE_PROFILE, HAXE_PROFILE_DIR, HAXE_OUT_DIR, HAXE_LAYOUT,
# BUILD_HAXE_CACHE_DIR, SKIP_SETUP=1 (keep ./haxe as is), SIGN_IDENTITY
# (Developer ID signing). See README.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/entry.sh"

[ "$HOST_OS" = "mac" ] || die "this script runs on macOS"

parse_entry_args "$@"
what="universal"
from_stages=0
for a in "${ENTRY_ARGS[@]+"${ENTRY_ARGS[@]}"}"; do
    case "$a" in
        arm64|x86_64|universal) what="$a" ;;
        --from-stages) from_stages=1 ;;
        *) die "usage: build-haxe-mac.sh [arm64|x86_64|universal] [--from-stages] [--ceramic-layout]" ;;
    esac
done
case "$what" in
    arm64) arches="arm64" ;;
    x86_64) arches="x86_64" ;;
    universal) arches="arm64 x86_64" ;;
esac
target="mac-$what"

"$ROOT/scripts/check-host.sh" "$target"
prepare_sources
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
log "profile: $HAXE_PROFILE, sources: $HAXE_DIR"

# neko (needed by the opam switch and haxelib), built for every architecture
"$ROOT/scripts/build-neko.sh" "$target"

build_arch() {
    local a="$1" t="mac-$1"
    local steps="'$ROOT/scripts/fetch-opam.sh' $t && '$ROOT/scripts/build-deps.sh' $t && '$ROOT/scripts/setup-switch.sh' $t && '$ROOT/scripts/build-core.sh' $t"
    log "building $t"
    if [ "$a" = "$(uname -m)" ]; then
        /bin/bash -c "$steps"
    else
        /usr/bin/arch "-$a" /bin/bash -c "$steps"
    fi
}

if [ "$from_stages" = "1" ]; then
    for a in $arches; do
        [ -f "$(stage_dir "mac-$a")/haxe" ] || die "missing stage for mac-$a"
    done
else
    for a in $arches; do
        build_arch "$a"
    done
fi

if [ "$what" = "universal" ]; then
    stage="$(stage_dir mac-universal)"
    mkdir -p "$stage"
    lipo -create -output "$stage/haxe.new" "$(stage_dir mac-arm64)/haxe" "$(stage_dir mac-x86_64)/haxe"
    mv -f "$stage/haxe.new" "$stage/haxe"
    cp -f "$(stage_dir mac-arm64)/commit.txt" "$stage/commit.txt"
    cp -f "$(stage_dir mac-arm64)/build_id.txt" "$stage/build_id.txt"
    [ "$(cat "$(stage_dir mac-x86_64)/build_id.txt")" = "$(cat "$stage/build_id.txt")" ] \
        || die "mac-arm64 and mac-x86_64 were built from different sources"
    {
        echo "== arm64"
        cat "$(stage_dir mac-arm64)/build_info.txt"
        echo
        echo "== x86_64"
        cat "$(stage_dir mac-x86_64)/build_info.txt"
    } > "$stage/build_info.txt"
fi

"$ROOT/scripts/build-haxelib.sh" "$target"
"$ROOT/scripts/assemble.sh" "$target"
package_target "$target"
export_target "$target"
print_summary "$target"
