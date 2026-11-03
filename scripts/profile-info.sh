#!/usr/bin/env bash
# Print the settings a CI needs before building, as KEY=VALUE lines:
# HAXE_PROFILE, OCAML_VERSION, OPAM_REPO_COMMIT, NEKO_NAME, CACHE_KEY.
# Reads the sources of HAXE_SRC_DIR (read-only) or of the clone, and
# HAXE_PROFILE / HAXE_PROFILE_DIR like the build scripts.
# CACHE_KEY changes whenever something that ends up in the cache changes
# (versions.env, the profile files, the neko patches, the Docker files).
# Usage: scripts/profile-info.sh [target]

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:-}"
if [ -n "${HAXE_SRC_DIR:-}" ] && [ -z "${BUILD_HAXE_SOURCE:-}" ]; then
    # Only haxe.opam is read here.
    HAXE_DIR="$(abs_dir "$HAXE_SRC_DIR")"
    export BUILD_HAXE_SOURCE="$HAXE_DIR"
fi
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile

hash_files() {
    local f
    for f in "$@"; do
        [ -f "$f" ] && cat "$f"
    done | (sha256sum 2>/dev/null || shasum -a 256) | cut -c1-16
}
files=("$ROOT/versions.env" "$ROOT"/patches/neko/*.patch "$ROOT"/docker/*.Dockerfile)
for d in "${PROFILE_DIRS[@]}"; do
    files+=("$d/profile.env" "$d/haxe.opam.locked" "$d"/patches/*.patch)
done

echo "HAXE_PROFILE=$HAXE_PROFILE"
echo "OCAML_VERSION=$OCAML_VERSION"
echo "OPAM_REPO_COMMIT=$OPAM_REPO_COMMIT"
echo "NEKO_NAME=$NEKO_NAME"
echo "CACHE_KEY=build-haxe-${target:-any}-$HAXE_PROFILE-ocaml$OCAML_VERSION-$(hash_files "${files[@]}")"
