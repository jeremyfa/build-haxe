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
lock="$ROOT/profiles/$HAXE_PROFILE/haxe.opam.locked"

(cd "$HAXE_DIR" && "$opam" lock . --lock-suffix=locked)
[ -f "$HAXE_DIR/haxe.opam.locked" ] || die "opam lock did not produce haxe/haxe.opam.locked"

# Drop the packages that only describe the host platform, so the same lock
# works on every OS and architecture.
grep -v -E '"(host-arch-[a-z0-9_]+|host-system-[a-z0-9_]+|arch-[a-z0-9_]+|system-mingw|ocaml-env-mingw[0-9]*|flexdll|conf-mingw-w64-[a-z0-9_-]+|ocaml-option-[a-z0-9_-]+)"' \
    "$HAXE_DIR/haxe.opam.locked" > "$lock"
rm -f "$HAXE_DIR/haxe.opam.locked"
log "lock written: $lock"
