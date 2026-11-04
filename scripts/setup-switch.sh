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

# Sources of the locked opam packages, from the dependency mirror
# (scripts/opam-cache.sh). opam uses them before the original hosts and checks
# each file against the checksums of the repository. Without the archive, opam
# downloads the sources itself.
use_opam_cache() {
    [ "$mode" != "--unlocked" ] || return 0
    [ -n "$lock" ] && [ -f "$lock" ] || return 0
    [ "$BUILD_HAXE_MIRROR" != "none" ] || return 0
    local name dir archive path
    name="$(opam_cache_name)"
    dir="$CACHE_DIR/opam-cache/${name%.tar.gz}"
    if [ ! -d "$dir/opam-cache" ]; then
        archive="$CACHE_DIR/downloads/$name"
        mkdir -p "$CACHE_DIR/downloads"
        if [ ! -f "$archive" ]; then
            log "downloading $(mirror_url build "$name")"
            if fetch_to "$(mirror_url build "$name")" "$archive.part.$$"; then
                mv -f "$archive.part.$$" "$archive"
            else
                [ "${BUILD_HAXE_MIRROR_ONLY:-0}" != "1" ] || die "$name is not in the mirror (BUILD_HAXE_MIRROR_ONLY=1)"
                warn "$name is not in the mirror, opam downloads the sources from their original hosts"
                return 0
            fi
        fi
        mkdir -p "$dir.extract.$$"
        tar -xzf "$archive" -C "$dir.extract.$$"
        [ -d "$dir" ] || mv "$dir.extract.$$" "$dir"
    fi
    path="$dir/opam-cache"
    [ "$os" = "windows" ] && path="/$(cygpath -m "$path")"
    "$opam" option --global "archive-mirrors=[\"file://$path\"]" >/dev/null
    log "opam sources from $name"
}

if [ "$os" != "windows" ]; then
    opam="$(opam_bin "$target")"
    [ -x "$opam" ] || die "opam missing (run scripts/fetch-opam.sh $target)"
    if [ ! -f "$OPAMROOT/config" ]; then
        repo="$(opam_repo_snapshot)"
        log "initializing opam root $OPAMROOT"
        "$opam" init --bare --no-setup --disable-sandboxing --bypass-checks pinned "$repo"
    fi
    use_opam_cache
    if ! "$opam" switch list --short 2>/dev/null | grep -qx build; then
        log "creating switch with OCaml $OCAML_VERSION (this compiles OCaml, it takes a while)"
        "$opam" switch create build "ocaml-base-compiler.$OCAML_VERSION"
    fi
else
    opam="$(command -v opam)"
    use_opam_cache
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

# opam is a native program on Windows: give it a D:/a/... path.
haxe_src="$HAXE_DIR"
[ "$os" = "windows" ] && haxe_src="$(cygpath -m "$HAXE_DIR")"
# System dependencies: on macOS and Linux they are provided by the build
# (static C libraries) or the image, and opam must not look for packages.
# On Windows opam installs them in its own Cygwin (pkgconf, the mingw
# packages the conf-* packages check), as on the official CI.
depexts=(--assume-depexts)
if [ "$os" = "windows" ]; then
    depexts=()
    unset OPAMNODEPEXTS
fi

if [ "$mode" = "--unlocked" ]; then
    log "installing Haxe dependencies (unlocked resolution)"
    rm -f "$HAXE_DIR/haxe.opam.locked"
    "$opam" install "$haxe_src" --deps-only "${depexts[@]+"${depexts[@]}"}"
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
    "$opam" install "$haxe_src" --deps-only --locked "${depexts[@]+"${depexts[@]}"}"
fi

log "opam switch ready for $HAXE_PROFILE/$target"
