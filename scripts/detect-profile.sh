#!/usr/bin/env bash
# Print the name of the dependency profile to use for the Haxe sources.
#   HAXE_PROFILE_DIR set: the caller profile (its PROFILE_NAME, or the name of
#                         its folder)
#   HAXE_PROFILE set:     that built-in profile
#   otherwise:            the built-in profile matching haxe.opam

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [ -n "${HAXE_PROFILE_DIR:-}" ]; then
    dir="$(abs_dir "$HAXE_PROFILE_DIR")"
    [ -f "$dir/profile.env" ] || die "$dir/profile.env not found"
    name="$(sed -n 's/^[: ]*"*\${*PROFILE_NAME:*=\([A-Za-z0-9._-]*\)}*"*$/\1/p; s/^PROFILE_NAME="*\([A-Za-z0-9._-]*\)"*$/\1/p' "$dir/profile.env" | head -1)"
    echo "${name:-$(basename "$dir")}"
    exit 0
fi

if [ -n "${HAXE_PROFILE:-}" ]; then
    echo "$HAXE_PROFILE"
    exit 0
fi

[ -f "$HAXE_DIR/haxe.opam" ] || die "$HAXE_DIR/haxe.opam not found (run ./setup-haxe.sh, or set HAXE_SRC_DIR)"
profile="$(detect_builtin_profile)"
[ -n "$profile" ] || die "cannot tell which profile matches $HAXE_DIR/haxe.opam. Set HAXE_PROFILE=haxe5 or haxe43, or HAXE_PROFILE_DIR."
echo "$profile"
