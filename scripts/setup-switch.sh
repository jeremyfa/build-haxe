#!/usr/bin/env bash
# Create the project-local opam root and switch for a target, then install
# Haxe's OCaml dependencies from the profile's lock file.
# Usage: scripts/setup-switch.sh <target> [--unlocked]
#   --unlocked  resolve without the lock file (used by update-locks.sh)
# Requires HAXE_PROFILE and the C dependencies (scripts/build-deps.sh): the
# pcre2 opam package records the pkg-config flags of libpcre2-8 at install time.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: setup-switch.sh <target> [--unlocked]}"
mode="${2:-locked}"
check_target "$target"
load_profile
sanitize_env "$target"

os="$(target_os "$target")"
lock="$PROFILE_LOCK"
[ -f "$(deps_prefix "$target")/.done" ] || die "C dependencies missing for $target (run scripts/build-deps.sh $target)"
[ -f "$HAXE_DIR/haxe.opam" ] || die "$HAXE_DIR/haxe.opam not found (run ./setup-haxe.sh, or set HAXE_SRC_DIR)"
command -v neko >/dev/null || die "neko not in PATH (run scripts/build-neko.sh $target)"

# opam-repository snapshot, extracted once and shared by every opam root
opam_repo_snapshot() {
    local dir="$CACHE_DIR/opam-repository/$OPAM_REPO_COMMIT"
    if [ ! -f "$dir/repo" ]; then
        mkdir -p "$CACHE_DIR/downloads"
        local tgz="$CACHE_DIR/downloads/opam-repository-$OPAM_REPO_COMMIT.tar.gz"
        if [ ! -f "$tgz" ]; then
            log "downloading opam-repository $OPAM_REPO_COMMIT" >&2
            curl -fsSL --retry 5 -o "$tgz.part.$$" "https://github.com/ocaml/opam-repository/archive/$OPAM_REPO_COMMIT.tar.gz"
            mv -f "$tgz.part.$$" "$tgz"
        fi
        log "extracting opam-repository snapshot" >&2
        mkdir -p "$dir.extract"
        tar -xzf "$tgz" -C "$dir.extract"
        mv "$dir.extract/opam-repository-$OPAM_REPO_COMMIT" "$dir"
    fi
    echo "$dir"
}

if [ "$os" != "windows" ]; then
    opam="$(opam_bin "$target")"
    [ -x "$opam" ] || die "opam missing (run scripts/fetch-opam.sh $target)"
    if [ ! -f "$OPAMROOT/config" ]; then
        repo="$(opam_repo_snapshot)"
        log "initializing opam root $OPAMROOT"
        "$opam" init --bare --no-setup --disable-sandboxing --bypass-checks pinned "$repo"
    fi
    if ! "$opam" switch list --short 2>/dev/null | grep -qx build; then
        log "creating switch with OCaml $OCAML_VERSION (this compiles OCaml, it takes a while)"
        "$opam" switch create build "ocaml-base-compiler.$OCAML_VERSION"
    fi
else
    opam="$(command -v opam)"
fi

record_env "$ROOT/build/$HAXE_PROFILE/$target/switch_env.txt"

for pin in ${OPAM_PINS:-}; do
    name="${pin%%.*}"
    version="${pin#*.}"
    if [ "$("$opam" pin list --short 2>/dev/null | grep -x "$name.$version" || true)" = "" ]; then
        log "pinning $name to $version"
        "$opam" pin add --no-action "$name" "$version"
    fi
done

if [ "$mode" = "--unlocked" ]; then
    log "installing Haxe dependencies (unlocked resolution)"
    rm -f "$HAXE_DIR/haxe.opam.locked"
    "$opam" install "$HAXE_DIR" --deps-only --assume-depexts
else
    [ -n "$lock" ] && [ -f "$lock" ] || die "no haxe.opam.locked in the profile folders of $HAXE_PROFILE (${PROFILE_DIRS[*]}). Run scripts/update-locks.sh first."
    if [ "$os" = "windows" ]; then
        # The compiler comes from setup-ocaml (mingw port): drop the compiler
        # pins of the lock, they describe the vanilla compiler.
        grep -v -E '"(ocaml|ocaml-base-compiler|ocaml-compiler|ocaml-config|ocaml-options-vanilla)" \{' \
            "$lock" > "$HAXE_DIR/haxe.opam.locked"
    else
        cp "$lock" "$HAXE_DIR/haxe.opam.locked"
    fi
    log "installing Haxe dependencies from $(basename "$lock")"
    "$opam" install "$HAXE_DIR" --deps-only --locked --assume-depexts
fi

log "opam switch ready for $HAXE_PROFILE/$target"
