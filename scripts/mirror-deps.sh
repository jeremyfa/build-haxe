#!/usr/bin/env bash
# Publish the pinned dependencies that are missing from the dependency mirror,
# or check the mirror.
# Usage: scripts/mirror-deps.sh [--check] [build|test|all]
#
# The mirror is made of the releases build-deps and test-deps of
# BUILD_HAXE_MIRROR_REPO (default jeremyfa/haxe-deps). Assets are never
# replaced or deleted: an asset name always stands for the same bytes.
#   --check  publish nothing; fail if an asset is missing or if the sha256
#            GitHub computed for it differs from the pinned one
# Needs the GitHub CLI (gh), logged in with write access to the mirror for
# publishing (GH_TOKEN on CI). See README.md.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

: "${BUILD_HAXE_MIRROR_REPO:=jeremyfa/haxe-deps}"
check=0
which=all
for a in "$@"; do
    case "$a" in
        --check) check=1 ;;
        build|test|all) which="$a" ;;
        *) die "usage: mirror-deps.sh [--check] [build|test|all]" ;;
    esac
done
command -v gh >/dev/null || die "the GitHub CLI (gh) is needed"

manifest="$("$ROOT/scripts/deps-manifest.sh" "$which")"
[ -n "$manifest" ] || die "empty manifest"

# The same asset name must always mean the same bytes.
dups="$(echo "$manifest" | awk -F'|' '{print $1"|"$2"|"$5}' | sort -u | awk -F'|' '{print $1"|"$2}' | uniq -d)"
[ -z "$dups" ] || die "assets listed with different sha256: $dups"

tag_of() {
    case "$1" in
        build) echo "$BUILD_HAXE_MIRROR_TAG_BUILD" ;;
        test) echo "$BUILD_HAXE_MIRROR_TAG_TEST" ;;
    esac
}

# "name sha256" of the assets already published in a release (empty if the
# release does not exist yet)
published() {
    gh release view "$1" -R "$BUILD_HAXE_MIRROR_REPO" --json assets \
        --jq '.assets[] | .name + " " + ((.digest // "") | sub("^sha256:"; ""))' 2>/dev/null || true
}

ensure_release() {
    local tag="$1"
    gh release view "$tag" -R "$BUILD_HAXE_MIRROR_REPO" >/dev/null 2>&1 && return 0
    log "creating release $tag in $BUILD_HAXE_MIRROR_REPO"
    gh release create "$tag" -R "$BUILD_HAXE_MIRROR_REPO" --latest=false \
        --title "$tag" \
        --notes "Pinned dependencies of build-haxe (https://github.com/jeremyfa/build-haxe), published by scripts/mirror-deps.sh. Assets are never replaced: each name always stands for the same bytes. The sha256 of every asset is pinned in build-haxe (versions.env, test-versions.env)."
}

staging="$PRODUCTS_CACHE_DIR/mirror-staging"
mkdir -p "$staging"

# produce <kind> <name> <source> <sha256> <commit> <prefix>: prints the path
# of a local file with the expected content
produce() {
    local kind="$1" name="$2" source="$3" sha="$4" commit="$5" prefix="$6" file got
    case "$kind" in
        url)
            BUILD_HAXE_MIRROR=none download "$source" "$sha" "$name"
            ;;
        git)
            file="$staging/$name"
            if [ ! -f "$file" ] || [ "$(tar_sha256_of "$file")" != "$sha" ]; then
                make_git_archive "$source" "$commit" "$prefix" "$file" >&2
            fi
            got="$(tar_sha256_of "$file")"
            [ -n "$sha" ] || die "$name: new git dependency, pin the sha256 of its tar ($got) next to commit $commit, then run mirror-deps.sh again"
            [ "$got" = "$sha" ] || die "$name: the tar of $commit has sha256 $got, the pinned one is $sha"
            echo "$file"
            ;;
        opam-cache)
            file="$staging/$name"
            if [ ! -f "$file" ]; then
                HAXE_PROFILE="$source" "$ROOT/scripts/opam-cache.sh" "$file" >&2
            fi
            echo "$file"
            ;;
        *) die "unknown kind $kind" ;;
    esac
}

failures=0
for release in build test; do
    lines="$(echo "$manifest" | grep "^$release|" || true)"
    [ -n "$lines" ] || continue
    tag="$(tag_of "$release")"
    have="$(published "$tag")"
    while IFS='|' read -r _ name kind source sha commit prefix; do
        current="$(echo "$have" | awk -v n="$name" '$1 == n {print $2; exit}')"
        present=0
        echo "$have" | awk -v n="$name" '$1 == n {found=1} END {exit !found}' && present=1
        if [ "$present" = 1 ] && [ "$kind" = git ] && [ "$check" = 1 ]; then
            # The pinned sha256 is the one of the tar inside the archive.
            tmp="$staging/$name.check.$$"
            if fetch_to "$(mirror_url "$release" "$name")" "$tmp" && [ "$(tar_sha256_of "$tmp")" = "$sha" ]; then
                echo "  ok       $tag/$name"
            else
                echo "  BAD      $tag/$name: content differs from the pinned tar sha256"
                failures=$((failures + 1))
            fi
            mv -f "$tmp" "$staging/$name.checked" 2>/dev/null || true
            continue
        fi
        if [ "$present" = 1 ]; then
            if [ "$kind" = url ] && [ -n "$sha" ] && [ -n "$current" ] && [ "$current" != "$sha" ]; then
                echo "  BAD      $tag/$name: published sha256 $current, pinned $sha"
                failures=$((failures + 1))
            else
                echo "  ok       $tag/$name"
            fi
            continue
        fi
        if [ "$check" = 1 ]; then
            echo "  MISSING  $tag/$name"
            failures=$((failures + 1))
            continue
        fi
        file="$(produce "$kind" "$name" "$source" "$sha" "$commit" "$prefix")"
        ensure_release "$tag"
        log "uploading $name to $tag"
        # The upload name is the file name: copy under the asset name if needed.
        if [ "$(basename "$file")" != "$name" ]; then
            cp -f "$file" "$staging/$name"
            file="$staging/$name"
        fi
        gh release upload "$tag" "$file" -R "$BUILD_HAXE_MIRROR_REPO"
        echo "  added    $tag/$name"
    done <<< "$lines"
done

[ "$failures" -eq 0 ] || die "$failures problem(s) in the mirror $BUILD_HAXE_MIRROR_REPO"
log "mirror $BUILD_HAXE_MIRROR_REPO is complete for: $which"
