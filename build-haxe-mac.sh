#!/usr/bin/env bash
# Build haxe and haxelib for macOS.
# Usage: ./build-haxe-mac.sh [arm64|x86_64|universal] [--from-stages]
#   default: universal
#   --from-stages: only combine existing arm64 and x86_64 stages (CI builds
#   each architecture in its own job)
#
# x86_64 is built under Rosetta: the whole chain (opam, OCaml, C libraries,
# dune) runs as x86_64 processes, so no cross-compiler is needed.
#
# Environment: HAXE_REPO, HAXE_BRANCH, HAXE_COMMIT, HAXE_PROFILE,
# SKIP_SETUP=1 (keep ./haxe as is), SIGN_IDENTITY (Developer ID signing).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

[ "$HOST_OS" = "mac" ] || die "this script runs on macOS"

what="${1:-universal}"
from_stages=0
[ "${2:-}" = "--from-stages" ] && from_stages=1
case "$what" in
    arm64) arches="arm64" ;;
    x86_64) arches="x86_64" ;;
    universal) arches="arm64 x86_64" ;;
    *) die "usage: build-haxe-mac.sh [arm64|x86_64|universal]" ;;
esac
target="mac-$what"

"$ROOT/scripts/check-host.sh" "$target"

if [ "${SKIP_SETUP:-0}" != "1" ] || [ ! -d "$HAXE_DIR/.git" ]; then
    "$ROOT/setup-haxe.sh"
fi
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
log "profile: $HAXE_PROFILE"

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
    {
        echo "== arm64"
        cat "$(stage_dir mac-arm64)/build_info.txt"
        echo
        echo "== x86_64"
        cat "$(stage_dir mac-x86_64)/build_info.txt"
    } > "$stage/build_info.txt"
fi

"$ROOT/scripts/build-haxelib.sh" "$target"
out="$("$ROOT/scripts/assemble.sh" "$target" | tail -1)"
"$ROOT/scripts/verify-binary.sh" "$out" "$target"
"$ROOT/scripts/package.sh" "$target"

echo
echo "macOS build complete. Available in:"
echo "  - $out"
echo "  - $ROOT/build/archives/haxe-$HAXE_PROFILE-$(cut -c1-10 "$out/commit.txt")-$target.zip"
