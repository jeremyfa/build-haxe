#!/usr/bin/env bash
# Remove everything the build scripts created. Asks for confirmation.
# Usage: ./clean-haxe.sh [--yes]
#
# Removes: haxe/ (the clone), .cache/ (downloads, opam roots, neko),
# build/ (C libraries, outputs, archives), .haxe_commit, and the Docker
# volumes build-haxe-opam-x64 / build-haxe-opam-arm64.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Safety: only run from the build-haxe project folder.
if [ ! -f "$SCRIPT_DIR/PLAN.md" ] || [ ! -f "$SCRIPT_DIR/versions.env" ] || [ ! -d "$SCRIPT_DIR/scripts" ]; then
    echo "error: $SCRIPT_DIR does not look like the build-haxe project" >&2
    exit 1
fi

targets=()
for p in haxe .cache build .haxe_commit; do
    if [ -e "$SCRIPT_DIR/$p" ]; then targets+=("$p"); fi
done

if [ "${#targets[@]}" -eq 0 ]; then
    echo "Nothing to clean."
else
    echo "This will delete, in $SCRIPT_DIR:"
    for p in "${targets[@]}"; do echo "  $p"; done
    if [ "${1:-}" != "--yes" ]; then
        read -r -p "Continue? [y/N] " answer
        case "$answer" in
            y|Y|yes) ;;
            *) echo "Aborted."; exit 1 ;;
        esac
    fi
    # opam marks some files read-only
    chmod -R u+w "${targets[@]}" 2>/dev/null || true
    rm -rf -- "${targets[@]}"
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    for v in build-haxe-opam-x64 build-haxe-opam-arm64; do
        if docker volume inspect "$v" >/dev/null 2>&1; then
            docker volume rm "$v" >/dev/null && echo "Removed Docker volume $v"
        fi
    done
fi
echo "Clean complete."
