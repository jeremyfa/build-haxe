#!/usr/bin/env bash
# Print the dependency profile matching the cloned Haxe sources.
# HAXE_PROFILE, when set, wins.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [ -n "${HAXE_PROFILE:-}" ]; then
    echo "$HAXE_PROFILE"
    exit 0
fi

opam_file="$HAXE_DIR/haxe.opam"
[ -f "$opam_file" ] || die "$opam_file not found (run ./setup-haxe.sh first)"

if grep -q '"camlp5"' "$opam_file"; then
    echo haxe43
elif grep -q '"ppx_parser"' "$opam_file"; then
    echo haxe5
else
    die "cannot tell which profile matches $opam_file. Set HAXE_PROFILE=haxe5 or haxe43."
fi
