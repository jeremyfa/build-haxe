#!/usr/bin/env bash
# Copy the Haxe sources of HAXE_SRC_DIR into build/source/, never writing in
# HAXE_SRC_DIR. Prints the path of the copy on the last line.
#
# - The copy holds the tracked files and the new files that are not ignored,
#   with their uncommitted changes, recursively for the submodules. Every
#   submodule must be initialized in HAXE_SRC_DIR (the build never fetches
#   anything into it).
# - <copy>.info records the commit, the branch, the origin, and whether the
#   sources have local changes (with the list of changed paths), see
#   load_source_info in common.sh.
# - git runs with GIT_OPTIONAL_LOCKS=0 so that even `git status` does not
#   refresh the index of HAXE_SRC_DIR.
# - The copy is reused between builds (dune builds stay incremental). When a
#   file it holds no longer exists in HAXE_SRC_DIR, it is set aside
#   (<copy>.old.<date>, never deleted) and a fresh copy is made.

#
# --info-only <dir>: write <dir>.info and <dir>.files for sources used in
# place (the clone of setup-haxe.sh), without copying anything.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

info_only=0
if [ "${1:-}" = "--info-only" ]; then
    info_only=1
    src="$(abs_dir "${2:?usage: prepare-source.sh --info-only <dir>}")"
else
    [ -n "${HAXE_SRC_DIR:-}" ] || die "HAXE_SRC_DIR is not set"
    src="$(abs_dir "$HAXE_SRC_DIR")"
fi
[ -f "$src/haxe.opam" ] || die "$src does not look like the Haxe repository (no haxe.opam)"
[ -e "$src/.git" ] || die "$src is not a git checkout (a clone or a submodule of the calling project is expected)"
export GIT_OPTIONAL_LOCKS=0

if [ "$info_only" = "1" ]; then
    snap="$src"
else
    name="$(basename "$src")-$(printf '%s' "$src" | (sha256sum 2>/dev/null || shasum -a 256) | cut -c1-8)"
    snap="$ROOT/build/source/$name"
    mkdir -p "$ROOT/build/source"
fi
list="$snap.files"

# ---- files to copy, recursively through the submodules (NUL separated)
list_repo() {
    local dir="$1" prefix="$2" f sm
    while IFS= read -r -d '' f; do
        # Directories are submodules (handled below); missing paths are files
        # deleted in the working tree.
        if [ -L "$dir/$f" ] || [ -f "$dir/$f" ]; then
            printf '%s\0' "$prefix$f"
        fi
    done < <(git -C "$dir" ls-files -z --cached --others --exclude-standard)
    [ -f "$dir/.gitmodules" ] || return 0
    while read -r _ sm; do
        if [ ! -e "$dir/$sm/.git" ]; then
            die "submodule $prefix$sm is not initialized in $src. Run: git -C '$src' submodule update --init --recursive"
        fi
        list_repo "$dir/$sm" "$prefix$sm/"
    done < <(git -C "$dir" config -f .gitmodules --get-regexp '^submodule\..*\.path$' || true)
}

# ---- local changes, recursively (one "<status> <path>" per line)
list_changes() {
    local dir="$1" prefix="$2" sm
    # Submodules: a different commit shows here, changes inside them are
    # listed by the recursion.
    git -C "$dir" status --porcelain=v1 --untracked-files=normal --ignore-submodules=dirty \
        | sed "s|^\(...\)|\1$prefix|"
    [ -f "$dir/.gitmodules" ] || return 0
    while read -r _ sm; do
        list_changes "$dir/$sm" "$prefix$sm/"
    done < <(git -C "$dir" config -f .gitmodules --get-regexp '^submodule\..*\.path$' || true)
}

list_repo "$src" "" > "$list"
changes="$(list_changes "$src" "")"
dirty=0
[ -z "$changes" ] || dirty=1

# ---- reuse the previous copy unless it holds files that are gone
if [ "$info_only" = "1" ]; then
    :
elif [ -d "$snap" ]; then
    stale="$(comm -23 \
        <(cd "$snap" && find . \( -type f -o -type l \) | sed 's|^\./||' \
            | grep -v -E '^(_build|lib\.sexp$|src/compiler/version\.ml$|haxe\.opam\.locked$|extra/haxelib_src/run\.c$)' | LC_ALL=C sort) \
        <(tr '\0' '\n' < "$list" | LC_ALL=C sort) | head -5 || true)"
    if [ -n "$stale" ]; then
        old="$snap.old.$(date +%Y%m%d%H%M%S)"
        mv "$snap" "$old"
        log "previous copy holds files that are gone from $src ($(echo $stale)...), moved to $old"
    fi
fi
if [ "$info_only" = "0" ]; then
    mkdir -p "$snap"
    log "copying $src to $snap"
    tar -C "$src" --null -T "$list" -cf - | tar -C "$snap" -xpf -
fi

# ---- information about the sources
{
    printf 'SRC_DIR=%q\n' "$src"
    printf 'SRC_COMMIT=%q\n' "$(git -C "$src" rev-parse HEAD)"
    printf 'SRC_BRANCH=%q\n' "$(git -C "$src" rev-parse --abbrev-ref HEAD)"
    printf 'SRC_DATE=%q\n' "$(git -C "$src" show -s --format=%cI HEAD)"
    printf 'SRC_REPO=%q\n' "$(git -C "$src" remote get-url origin 2>/dev/null || echo "local ($src)")"
    printf 'SRC_HAXELIB_COMMIT=%q\n' "$(git -C "$src/extra/haxelib_src" rev-parse HEAD 2>/dev/null || echo unknown)"
    printf 'SRC_DIRTY=%q\n' "$dirty"
    printf 'SRC_CHANGES=%q\n' "$changes"
} > "$snap.info"

if [ "$dirty" = "1" ]; then
    log "sources have local changes:"
    echo "$changes" | sed 's/^/    /'
fi
echo "$snap"
