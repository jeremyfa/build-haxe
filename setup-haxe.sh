#!/usr/bin/env bash
# Clone or update the Haxe repository into ./haxe at the requested revision.
#
#   HAXE_REPO    repository URL (default: HaxeFoundation/haxe)
#   HAXE_BRANCH  branch (default: development)
#   HAXE_COMMIT  exact commit, takes precedence over the branch

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

HAXE_REPO="${HAXE_REPO:-$DEFAULT_HAXE_REPO}"
HAXE_BRANCH="${HAXE_BRANCH:-$DEFAULT_HAXE_BRANCH}"
HAXE_COMMIT="${HAXE_COMMIT:-}"

if [ ! -d "$HAXE_DIR/.git" ]; then
    log "cloning $HAXE_REPO ($HAXE_BRANCH)"
    git clone --depth 1 --branch "$HAXE_BRANCH" --no-recurse-submodules "$HAXE_REPO" "$HAXE_DIR"
else
    current_repo="$(git -C "$HAXE_DIR" remote get-url origin)"
    if [ "$current_repo" != "$HAXE_REPO" ]; then
        die "haxe/ is a clone of $current_repo, not $HAXE_REPO. Run ./clean-haxe.sh first or set HAXE_REPO accordingly."
    fi
fi

# Refuse to move a clone with local changes to tracked files (for instance
# patches left applied by an interrupted build).
if [ -n "$(git -C "$HAXE_DIR" status --porcelain --untracked-files=no --ignore-submodules=all)" ]; then
    git -C "$HAXE_DIR" status --short --untracked-files=no >&2
    die "haxe/ has local changes. Inspect them, then run: git -C haxe checkout -- ."
fi

if [ -n "$HAXE_COMMIT" ]; then
    if [ "$(git -C "$HAXE_DIR" rev-parse HEAD)" != "$(git -C "$HAXE_DIR" rev-parse --verify --quiet "$HAXE_COMMIT^{commit}" || true)" ]; then
        log "fetching commit $HAXE_COMMIT"
        git -C "$HAXE_DIR" fetch --depth 1 origin "$HAXE_COMMIT"
        git -C "$HAXE_DIR" checkout --quiet --detach FETCH_HEAD
    fi
else
    log "fetching latest $HAXE_BRANCH"
    git -C "$HAXE_DIR" fetch --depth 1 origin "$HAXE_BRANCH"
    git -C "$HAXE_DIR" checkout --quiet --detach FETCH_HEAD
fi

# haxelib has its own submodules (hx3compat, hx4compat, crypto...)
git -C "$HAXE_DIR" submodule update --init --recursive --depth 1 extra/haxelib_src

haxe_commit > "$ROOT/.haxe_commit"
log "haxe at $(haxe_commit) ($HAXE_REPO)"
