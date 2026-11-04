#!/usr/bin/env bash
# Helpers for the test scripts. Sourced after scripts/common.sh and
# load_profile, never executed directly.

# shellcheck source=../../test-versions.env
source "$ROOT/test-versions.env"

# Platform key of the test tools for a build target: the tools run on the
# machine that runs the tests (a universal macOS build is tested natively).
test_platform() {
    case "$1" in
        mac-*)
            case "$HOST_ARCH" in
                arm64) echo MAC_ARM64 ;;
                *) echo MAC_X64 ;;
            esac
            ;;
        linux-x64) echo LINUX_X64 ;;
        linux-arm64) echo LINUX_ARM64 ;;
        windows-x64) echo WINDOWS_X64 ;;
        *) die "no test platform for $1" ;;
    esac
}

test_tools_dir() {
    echo "$CACHE_DIR/test-tools/$(test_platform "$1" | tr '[:upper:]' '[:lower:]')"
}

# test_file <TOOL> <target>: prints the path of the verified archive of
# TEST_FILE_<TOOL>_<PLATFORM>, from the mirror or its original URL.
test_file() {
    local key="$1_$(test_platform "$2")" v url sha name
    v="TEST_FILE_${key}_URL"; url="${!v:-}"
    [ -n "$url" ] || die "TEST_FILE_${key}_URL is not set (test-versions.env)"
    v="TEST_FILE_${key}_SHA256"; sha="${!v:-}"
    [ -n "$sha" ] || die "TEST_FILE_${key}_SHA256 is not set (test-versions.env)"
    v="TEST_FILE_${key}_NAME"; name="${!v:-$(asset_name "$url")}"
    download "$url" "$sha" "$name" test
}

# test_file_any <KEY>: same as test_file for a file without platform variants
# (TEST_FILE_<KEY>_URL).
test_file_any() {
    local key="$1" v url sha name
    v="TEST_FILE_${key}_URL"; url="${!v:-}"
    [ -n "$url" ] || die "TEST_FILE_${key}_URL is not set (test-versions.env)"
    v="TEST_FILE_${key}_SHA256"; sha="${!v:-}"
    [ -n "$sha" ] || die "TEST_FILE_${key}_SHA256 is not set (test-versions.env)"
    v="TEST_FILE_${key}_NAME"; name="${!v:-$(asset_name "$url")}"
    download "$url" "$sha" "$name" test
}

# extract_zip <zip> <dest>: unzip, or PowerShell where unzip is missing
# (Git Bash on Windows)
extract_zip() {
    mkdir -p "$2"
    if command -v unzip >/dev/null; then
        unzip -q "$1" -d "$2"
    else
        powershell -NoProfile -Command "Expand-Archive -LiteralPath '$(cygpath -w "$1")' -DestinationPath '$(cygpath -w "$2")' -Force"
    fi
}

# git_dep_name <N>: lower-case name used for archives and folders
git_dep_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# git_dep_src <N>: prints a folder holding the files of the pinned commit of
# TEST_GIT_<N> (extracted once from its archive).
git_dep_src() {
    local n="$1" v repo commit sha lower archive dir
    v="TEST_GIT_${n}_REPO"; repo="${!v:-}"
    v="TEST_GIT_${n}_COMMIT"; commit="${!v:-}"
    v="TEST_GIT_${n}_SHA256"; sha="${!v:-}"
    [ -n "$repo" ] && [ -n "$commit" ] && [ -n "$sha" ] || die "TEST_GIT_${n}_REPO, _COMMIT and _SHA256 must be set"
    lower="$(git_dep_name "$n")"
    dir="$CACHE_DIR/test-tools/git-src/$lower-${commit:0:12}"
    if [ ! -d "$dir" ]; then
        archive="$(fetch_git_archive "$lower-${commit:0:12}.tar.gz" "$repo" "$commit" "$sha" "$lower-$commit/" test)"
        mkdir -p "$dir.extract.$$"
        tar -xzf "$archive" -C "$dir.extract.$$"
        [ -d "$dir" ] || mv "$dir.extract.$$/$lower-$commit" "$dir"
    fi
    echo "$dir"
}

# file_url <path>: file:// URL of a local path, understood by git
file_url() {
    if [ "$HOST_OS" = "windows" ]; then
        echo "file:///$(cygpath -m "$1")"
    else
        echo "file://$1"
    fi
}

# Status line of a test target: "<status> <seconds>"
# status: pass, fail, allowed-fail, skip
test_results_dir() {
    echo "$ROOT/build/test-results/$HAXE_PROFILE/$1/$2"
}

# in_list <word> <space or comma separated list>
in_list() {
    case " $(echo "$2" | tr ',' ' ') " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}
