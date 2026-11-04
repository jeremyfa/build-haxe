#!/usr/bin/env bash
# Regenerate profiles/<profile>/haxe.opam.locked.
# Usage: HAXE_PROFILE=<profile> scripts/update-locks.sh <target>
# Resolves Haxe's dependencies against the pinned opam-repository snapshot
# (OPAM_REPO_COMMIT), installs them in the target's switch, then records the
# exact versions. Run it after changing OPAM_REPO_COMMIT or the profile's
# OCaml version, then commit the new lock file.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: update-locks.sh <target>}"
check_target "$target"
load_profile

"$ROOT/scripts/setup-switch.sh" "$target" --unlocked

sanitize_env "$target"
opam="$(opam_bin "$target")"
# Written to the most specific profile folder (HAXE_PROFILE_DIR if set).
lock="${PROFILE_DIRS[${#PROFILE_DIRS[@]}-1]}/$PROFILE_LOCK_NAME"

# The switch only contains Haxe's dependencies, so its installed packages are
# exactly the dependency closure. The lock is generated from that list rather
# than with `opam lock`, which cannot handle the dependency formula of
# 4.3_bugfix (a disjunction between OCaml 5 and OCaml 4 setups).
# Packages that only describe the host platform are dropped, so the same lock
# works on every OS and architecture.
platform_re='^(host-arch-|host-system-|arch-|system-mingw$|ocaml-env-mingw|flexdll$|conf-mingw-w64-|ocaml-option-)'
deps="$("$opam" list --installed --short --columns=name,version | awk '{print $1, $2}' \
    | grep -v -E "$platform_re" | sort)"
[ -n "$deps" ] || die "no installed packages found in the switch"

{
    awk '/^depends: *\[/ {skip=1; next} skip && /^\]/ {skip=0; next} !skip' "$HAXE_DIR/haxe.opam"
    echo "depends: ["
    echo "$deps" | while read -r name version; do
        echo "  \"$name\" {= \"$version\"}"
    done
    echo "]"
} > "$lock"
log "lock written: $lock"
