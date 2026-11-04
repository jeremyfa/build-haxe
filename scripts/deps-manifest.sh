#!/usr/bin/env bash
# List every pinned dependency that belongs in the dependency mirror.
# Usage: scripts/deps-manifest.sh [build|test|all]
# One line per asset:
#   release|asset name|kind|source|sha256|commit|prefix
# kinds:
#   url         a file downloaded as is from <source>
#   git         `git archive --prefix=<prefix> <commit> | gzip -n` of the
#               repository <source>
#   opam-cache  the opam source cache of profile <source> (scripts/opam-cache.sh),
#               no sha256: opam checks every file in it
# Used by scripts/mirror-deps.sh. The neko dependencies are read from the
# CMakeLists of each pinned neko commit, so this script may download them.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

which="${1:-all}"

emit() { echo "$1|$2|$3|$4|$5|${6:-}|${7:-}"; }

build_deps() {
    local v sha asset
    for asset in arm64-macos x86_64-macos x86_64-linux arm64-linux; do
        v="OPAM_SHA256_${asset//-/_}"
        emit build "opam-$OPAM_VERSION-$asset" url \
            "https://github.com/ocaml/opam/releases/download/$OPAM_VERSION/opam-$OPAM_VERSION-$asset" "${!v}"
    done
    emit build "$(basename "$ZLIB_URL")" url "$ZLIB_URL" "$ZLIB_SHA256"
    emit build "$(basename "$PCRE2_URL")" url "$PCRE2_URL" "$PCRE2_SHA256"
    emit build "$(basename "$MBEDTLS2_URL")" url "$MBEDTLS2_URL" "$MBEDTLS2_SHA256"
    emit build "$(basename "$MBEDTLS3_URL")" url "$MBEDTLS3_URL" "$MBEDTLS3_SHA256"
    emit build "$(basename "$STRING_SHELLQUOTE_URL")" url "$STRING_SHELLQUOTE_URL" "$STRING_SHELLQUOTE_SHA256"
    emit build "opam-repository-${OPAM_REPO_COMMIT:0:12}.tar.gz" git \
        https://github.com/ocaml/opam-repository "$OPAM_REPO_SHA256" "$OPAM_REPO_COMMIT" \
        "opam-repository-$OPAM_REPO_COMMIT/"

    # neko sources (every NEKO_<S>_COMMIT without a custom URL) and the
    # dependencies pinned in their CMakeLists
    local var src commit repo url name archive work
    for var in $(compgen -A variable | grep -E '^NEKO_[A-Z0-9_]+_COMMIT$' | sort); do
        src="${var#NEKO_}"; src="${src%_COMMIT}"
        commit="${!var}"
        v="NEKO_${src}_URL"; [ -z "${!v:-}" ] || continue
        v="NEKO_${src}_SHA256"; sha="${!v:-}"
        v="NEKO_${src}_REPO"; repo="${!v:-https://github.com/HaxeFoundation/neko}"
        name="neko-${commit:0:12}.tar.gz"
        emit build "$name" git "$repo" "$sha" "$commit" "neko-$commit/"
        archive="$(fetch_git_archive "$name" "$repo" "$commit" "$sha" "neko-$commit/")"
        work="$PRODUCTS_CACHE_DIR/manifest-work/neko-$commit"
        if [ ! -f "$work/CMakeLists.txt" ]; then
            mkdir -p "$work.extract.$$"
            tar -xzf "$archive" -C "$work.extract.$$"
            [ -d "$work" ] || mv "$work.extract.$$/neko-$commit" "$work"
        fi
        awk '/^[ \t]*URL[ \t]+https?:/{u=$2} /URL_HASH[ \t]+SHA256=/{sub(/.*SHA256=/,""); if(u!=""){print u, $1; u=""}}' \
            "$work/CMakeLists.txt" "$work"/libs/*/CMakeLists.txt |
        while read -r url sha; do
            emit build "$(basename "$url")" url "$url" "$sha"
        done
    done

    # opam source caches, one per profile lock
    local profile
    for profile in "$ROOT"/profiles/*/; do
        profile="$(basename "$profile")"
        [ -f "$ROOT/profiles/$profile/haxe.opam.locked" ] || continue
        (
            HAXE_PROFILE="$profile"
            unset OCAML_VERSION MBEDTLS_SERIES NEKO_SOURCE PROFILE_BUILD_STYLE OPAM_PINS
            load_profile >/dev/null
            emit build "$(opam_cache_name)" opam-cache "$profile" ""
        )
    done
}

# Test dependencies of every profile (test-versions.env with the profile's
# overrides). The same asset can be listed by several profiles.
test_deps() {
    [ -f "$ROOT/test-versions.env" ] || return 0
    local profile
    for profile in "$ROOT"/profiles/*/; do
        profile="$(basename "$profile")"
        (
            HAXE_PROFILE="$profile"
            load_profile >/dev/null
            # shellcheck source=../test-versions.env
            source "$ROOT/test-versions.env"
            local n v repo commit sha lower key url name
            for n in $TEST_GIT_DEPS; do
                v="TEST_GIT_${n}_REPO"; repo="${!v}"
                v="TEST_GIT_${n}_COMMIT"; commit="${!v}"
                v="TEST_GIT_${n}_SHA256"; sha="${!v:-}"
                lower="$(echo "$n" | tr '[:upper:]' '[:lower:]')"
                emit test "$lower-${commit:0:12}.tar.gz" git "$repo" "$sha" "$commit" "$lower-$commit/"
            done
            for v in $(compgen -A variable | grep -E '^TEST_FILE_[A-Z0-9_]+_URL$' | sort); do
                key="${v#TEST_FILE_}"; key="${key%_URL}"
                url="${!v}"
                v="TEST_FILE_${key}_SHA256"; sha="${!v:-}"
                v="TEST_FILE_${key}_NAME"; name="${!v:-$(asset_name "$url")}"
                emit test "$name" url "$url" "$sha"
            done
        )
    done
}

case "$which" in
    build) build_deps ;;
    test) test_deps ;;
    all) build_deps; test_deps ;;
    *) die "usage: deps-manifest.sh [build|test|all]" ;;
esac | sort -u
