#!/usr/bin/env bash
# Shared helpers. Sourced by every script, never executed directly.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[build-haxe] $*"; }
warn() { echo "[build-haxe] warning: $*" >&2; }
die() { echo "[build-haxe] error: $*" >&2; exit 1; }

abs_dir() { (cd "$1" 2>/dev/null && pwd) || die "folder not found: $1"; }

# Haxe sources: the clone made by setup-haxe.sh, or the copy of HAXE_SRC_DIR
# made by scripts/prepare-source.sh (BUILD_HAXE_SOURCE). Information about the
# sources (commit, local changes) is read from <sources>.info, never with git
# inside a copy (a copy has no .git and git would find an enclosing repo).
HAXE_DIR="${BUILD_HAXE_SOURCE:-$ROOT/haxe}"
if [ -n "${BUILD_HAXE_SOURCE:-}" ]; then
    # Tools that look for a git repository (opam, git itself) must not find
    # build-haxe or the calling project above the copy.
    export GIT_CEILING_DIRECTORIES="$(dirname "$BUILD_HAXE_SOURCE")"
fi

# Caches: downloads, opam roots, neko and C library builds. In the project by
# default, or under BUILD_HAXE_CACHE_DIR so a calling project can keep them
# (for instance with actions/cache on its CI).
if [ -n "${BUILD_HAXE_CACHE_DIR:-}" ]; then
    mkdir -p "$BUILD_HAXE_CACHE_DIR"
    BUILD_HAXE_CACHE_DIR="$(abs_dir "$BUILD_HAXE_CACHE_DIR")"
    export BUILD_HAXE_CACHE_DIR
    CACHE_DIR="$BUILD_HAXE_CACHE_DIR"
    PRODUCTS_CACHE_DIR="$BUILD_HAXE_CACHE_DIR"
else
    CACHE_DIR="$ROOT/.cache"
    PRODUCTS_CACHE_DIR="$ROOT/build"
fi

# shellcheck source=../versions.env
source "$ROOT/versions.env"

# Host detection
case "$(uname -s)" in
    Darwin) HOST_OS=mac ;;
    Linux) HOST_OS=linux ;;
    CYGWIN*|MINGW*|MSYS*) HOST_OS=windows ;;
    *) die "unsupported host: $(uname -s)" ;;
esac
case "$(uname -m)" in
    arm64|aarch64) HOST_ARCH=arm64 ;;
    x86_64|amd64) HOST_ARCH=x86_64 ;;
    *) die "unsupported host architecture: $(uname -m)" ;;
esac

if [ "$HOST_OS" = "mac" ]; then
    JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
else
    JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
fi

in_container() {
    [ "${BUILD_HAXE_IN_CONTAINER:-0}" = "1" ] || [ -f /.dockerenv ]
}

# Targets are named <os>-<arch>: mac-arm64, mac-x86_64, mac-universal,
# linux-x64, linux-arm64, windows-x64.
check_target() {
    case "$1" in
        mac-arm64|mac-x86_64|mac-universal|linux-x64|linux-arm64|windows-x64) ;;
        *) die "unknown target '$1' (expected mac-arm64, mac-x86_64, mac-universal, linux-x64, linux-arm64 or windows-x64)" ;;
    esac
}
target_os() { echo "${1%%-*}"; }
target_arch() {
    case "${1#*-}" in
        x64) echo x86_64 ;;
        *) echo "${1#*-}" ;;
    esac
}

# Built-in profile matching the sources in $HAXE_DIR (or "" when unknown).
detect_builtin_profile() {
    local opam_file="$HAXE_DIR/haxe.opam"
    if [ ! -f "$opam_file" ]; then
        echo ""
    elif grep -q '"camlp5"' "$opam_file"; then
        echo haxe43
    elif grep -q '"ppx_parser"' "$opam_file"; then
        echo haxe5
    else
        echo ""
    fi
}

# Profile loading. HAXE_PROFILE must be set (see scripts/detect-profile.sh).
# A profile is a built-in one (profiles/<name>), or one given by the caller
# with HAXE_PROFILE_DIR. A caller profile may set PROFILE_BASE (a built-in
# profile name, or "auto" for the one matching the sources): it then only
# overrides what it sets, and its patches come after the base ones.
# Sets PROFILE_DIRS (base first), PROFILE_LOCK and PROFILE_PATCHES.
load_profile() {
    [ -n "${HAXE_PROFILE:-}" ] || die "HAXE_PROFILE is not set"
    PROFILE_DIRS=()
    if [ -n "${HAXE_PROFILE_DIR:-}" ]; then
        HAXE_PROFILE_DIR="$(abs_dir "$HAXE_PROFILE_DIR")"
        export HAXE_PROFILE_DIR
        [ -f "$HAXE_PROFILE_DIR/profile.env" ] || die "$HAXE_PROFILE_DIR/profile.env not found"
        # Values already set win, so the caller profile is read first.
        # shellcheck disable=SC1091
        source "$HAXE_PROFILE_DIR/profile.env"
        if [ -n "${PROFILE_BASE:-}" ]; then
            if [ "$PROFILE_BASE" = "auto" ]; then
                PROFILE_BASE="$(detect_builtin_profile)"
                [ -n "$PROFILE_BASE" ] || die "PROFILE_BASE=auto: no built-in profile matches $HAXE_DIR/haxe.opam"
            fi
            [ -f "$ROOT/profiles/$PROFILE_BASE/profile.env" ] || die "unknown PROFILE_BASE '$PROFILE_BASE'"
            # shellcheck disable=SC1090
            source "$ROOT/profiles/$PROFILE_BASE/profile.env"
            PROFILE_DIRS+=("$ROOT/profiles/$PROFILE_BASE")
        fi
        PROFILE_DIRS+=("$HAXE_PROFILE_DIR")
    else
        local file="$ROOT/profiles/$HAXE_PROFILE/profile.env"
        [ -f "$file" ] || die "unknown profile '$HAXE_PROFILE' ($file not found)"
        # shellcheck disable=SC1090
        source "$file"
        PROFILE_DIRS+=("$ROOT/profiles/$HAXE_PROFILE")
    fi
    local d p
    PROFILE_LOCK=""
    PROFILE_PATCHES=()
    for d in "${PROFILE_DIRS[@]}"; do
        if [ -f "$d/haxe.opam.locked" ]; then PROFILE_LOCK="$d/haxe.opam.locked"; fi
        for p in "$d"/patches/*.patch; do
            if [ -f "$p" ]; then PROFILE_PATCHES+=("$p"); fi
        done
    done
    [ -n "${OCAML_VERSION:-}" ] || die "profile $HAXE_PROFILE does not set OCAML_VERSION"
    if [ "$MBEDTLS_SERIES" = "3" ]; then
        MBEDTLS_VERSION="$MBEDTLS3_VERSION"; MBEDTLS_URL="$MBEDTLS3_URL"; MBEDTLS_SHA256="$MBEDTLS3_SHA256"
    else
        MBEDTLS_VERSION="$MBEDTLS2_VERSION"; MBEDTLS_URL="$MBEDTLS2_URL"; MBEDTLS_SHA256="$MBEDTLS2_SHA256"
    fi
    local v
    # neko source NEKO_SOURCE (see versions.env)
    local lower
    v="NEKO_${NEKO_SOURCE}_COMMIT"; NEKO_COMMIT="${!v:-}"
    [ -n "$NEKO_COMMIT" ] || die "neko source $NEKO_SOURCE: NEKO_${NEKO_SOURCE}_COMMIT is not set"
    v="NEKO_${NEKO_SOURCE}_SHA256"; NEKO_SHA256="${!v:-}"
    [ -n "$NEKO_SHA256" ] || die "neko source $NEKO_SOURCE: NEKO_${NEKO_SOURCE}_SHA256 is not set"
    v="NEKO_${NEKO_SOURCE}_REPO"; NEKO_REPO="${!v:-https://github.com/HaxeFoundation/neko}"
    lower="$(echo "$NEKO_SOURCE" | tr '[:upper:]' '[:lower:]')"
    v="NEKO_${NEKO_SOURCE}_NAME"; NEKO_NAME="${!v:-$lower-${NEKO_COMMIT:0:7}}"
    v="NEKO_${NEKO_SOURCE}_URL"; NEKO_URL="${!v:-}"
    # Without NEKO_<S>_URL, the sources are the archive of the commit (mirror,
    # or made from the repository).
    NEKO_ARCHIVE_NAME="neko-${NEKO_COMMIT:0:12}.tar.gz"
    export HAXE_PROFILE OCAML_VERSION MBEDTLS_SERIES MBEDTLS_VERSION NEKO_COMMIT NEKO_NAME NEKO_REPO NEKO_URL NEKO_ARCHIVE_NAME
}

# Paths. C libraries and neko go to the products cache (build/ or
# BUILD_HAXE_CACHE_DIR), outputs always to build/.
deps_prefix() { echo "$PRODUCTS_CACHE_DIR/deps/$HAXE_PROFILE/$1"; }
deps_work() { echo "$PRODUCTS_CACHE_DIR/deps-work/$1"; }
# One opam root per profile, target and OCaml version, so changing the
# compiler never reuses (or needs to delete) an existing root.
opam_root() {
    local name="$HAXE_PROFILE-$1-ocaml$OCAML_VERSION"
    if [ -n "${BUILD_HAXE_OPAMROOT_BASE:-}" ]; then
        echo "$BUILD_HAXE_OPAMROOT_BASE/$name"
    else
        echo "$CACHE_DIR/opam/$name"
    fi
}
stage_dir() { echo "$ROOT/build/$HAXE_PROFILE/$1/stage"; }
dune_build_dir() { echo "_build-$1"; }

# neko built from source (scripts/build-neko.sh), one folder per neko source
# and target, with the flat layout of the official neko archives.
neko_dir() { echo "$PRODUCTS_CACHE_DIR/neko/$NEKO_NAME/$1"; }

opam_bin() {
    local os arch
    os="$(target_os "$1")"
    arch="$(target_arch "$1")"
    case "$os" in
        mac) echo "$CACHE_DIR/bin/macos-$arch/opam" ;;
        linux) echo "$CACHE_DIR/bin/linux-$arch/opam" ;;
        windows) command -v opam ;;
    esac
}

# Platform names used for HAXE_OUT_DIR and the ceramic layout.
# standard: the target names. ceramic: ceramic's git/haxe-binary folders.
layout_platform() {
    local target="$1" layout="${2:-standard}"
    if [ "$layout" = "ceramic" ]; then
        case "$target" in
            mac-*) echo mac ;;
            linux-x64) echo linux-x86_64 ;;
            linux-arm64) echo linux-arm64 ;;
            windows-x64) echo windows ;;
        esac
    else
        echo "$target"
    fi
}

# Build id of the assembled folder of a target (from its stage).
stage_build_id() {
    local f
    f="$(stage_dir "$1")/build_id.txt"
    [ -f "$f" ] || die "no build for $1 ($f missing)"
    cat "$f"
}
# Folder holding a layout of a target: haxe/ (standard), or haxe/ and neko/
# side by side (ceramic).
layout_folder() {
    local target="$1" layout="${2:-standard}" base
    base="$ROOT/build/$HAXE_PROFILE/$target/$(stage_build_id "$target")"
    if [ "$layout" = "ceramic" ]; then echo "$base-ceramic"; else echo "$base"; fi
}
# Archive of a layout of a target.
layout_archive() {
    local target="$1" layout="${2:-standard}" name ext=tar.gz
    case "$target" in mac-*|windows-*) ext=zip ;; esac
    name="haxe-$HAXE_PROFILE-$(stage_build_id "$target")-$target"
    if [ "$layout" = "ceramic" ]; then name="$name-ceramic"; fi
    echo "$ROOT/build/archives/$name.$ext"
}

# Information about the Haxe sources. From <sources>.info for a copy of
# HAXE_SRC_DIR, from git for the clone. Sets SRC_COMMIT, SRC_SHORT,
# SRC_BRANCH, SRC_DATE, SRC_REPO, SRC_HAXELIB_COMMIT, SRC_DIRTY (0 or 1),
# SRC_CHANGES (one changed path per line) and BUILD_ID (short commit, with
# "-dirty" when the sources have local changes).
load_source_info() {
    if ! sources_are_clone && [ -f "$HAXE_DIR.info" ]; then
        # shellcheck disable=SC1090
        source "$HAXE_DIR.info"
    elif sources_are_clone && git -C "$HAXE_DIR" rev-parse HEAD >/dev/null 2>&1; then
        SRC_COMMIT="$(git -C "$HAXE_DIR" rev-parse HEAD)"
        SRC_BRANCH="$(git -C "$HAXE_DIR" rev-parse --abbrev-ref HEAD)"
        SRC_DATE="$(git -C "$HAXE_DIR" show -s --format=%cI HEAD)"
        SRC_REPO="$(git -C "$HAXE_DIR" remote get-url origin 2>/dev/null || echo unknown)"
        SRC_HAXELIB_COMMIT="$(git -C "$HAXE_DIR/extra/haxelib_src" rev-parse HEAD 2>/dev/null || echo unknown)"
        SRC_DIRTY=0
        SRC_CHANGES=""
    elif [ -f "$HAXE_DIR.info" ]; then
        # The clone, where git cannot run (Cygwin with Git for Windows):
        # information written by setup-haxe.sh.
        # shellcheck disable=SC1090
        source "$HAXE_DIR.info"
    else
        die "no Haxe sources in $HAXE_DIR (run ./setup-haxe.sh, or set HAXE_SRC_DIR)"
    fi
    SRC_SHORT="${SRC_COMMIT:0:10}"
    BUILD_ID="$SRC_SHORT"
    if [ "$SRC_DIRTY" = "1" ]; then BUILD_ID="$SRC_SHORT-dirty"; fi
}
haxe_commit() { load_source_info; echo "$SRC_COMMIT"; }
haxe_short() { load_source_info; echo "$SRC_SHORT"; }

# Apply a patch to a source folder unless the sources already contain it (a
# fork with the patch merged). Prints "applied" or "already applied", fails
# when the patch neither applies nor is present.
# patch(1) is used rather than git apply, which would look for an enclosing
# repository. -f keeps both BSD patch (macOS) and GNU patch from asking or
# guessing: without it, BSD patch answers its own "Reversed patch detected!
# Ignore -R?" question and reports an unapplied patch as present.
apply_patch_once() {
    local dir="$1" p="$2"
    if (cd "$dir" && patch -p1 -R -f -s --dry-run < "$p" >/dev/null 2>&1); then
        echo "already applied"
    elif (cd "$dir" && patch -p1 -f -s --dry-run < "$p" >/dev/null 2>&1); then
        (cd "$dir" && patch -p1 -f -s < "$p") >/dev/null
        echo "applied"
    else
        die "$(basename "$p") does not apply to $dir"
    fi
}

# True when the sources are the clone made by setup-haxe.sh (git commands
# may then run in it).
sources_are_clone() { [ "$HAXE_DIR" = "$ROOT/haxe" ]; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Replace a file with a copy of another one through a new inode. Overwriting
# an executable in place makes macOS kill it on the next launch (its cached
# code signature no longer matches).
replace_file() {
    local src="$1" dst="$2"
    cp -f "$src" "$dst.tmp.$$"
    mv -f "$dst.tmp.$$" "$dst"
}

# ---- dependency mirror
# Every pinned dependency is also published as an asset of a release of
# https://github.com/jeremyfa/haxe-deps (scripts/mirror-deps.sh). Downloads try
# the mirror first and the original location only as a fallback.
#   BUILD_HAXE_MIRROR       base URL of the releases, "none" to skip the mirror
#   BUILD_HAXE_MIRROR_ONLY  1: never fall back to the original location
: "${BUILD_HAXE_MIRROR:=https://github.com/jeremyfa/haxe-deps/releases/download}"
: "${BUILD_HAXE_MIRROR_TAG_BUILD:=build-deps}"
: "${BUILD_HAXE_MIRROR_TAG_TEST:=test-deps}"

mirror_url() {
    # mirror_url <build|test> <asset name>
    local tag
    case "$1" in
        build) tag="$BUILD_HAXE_MIRROR_TAG_BUILD" ;;
        test) tag="$BUILD_HAXE_MIRROR_TAG_TEST" ;;
        *) die "unknown mirror release '$1'" ;;
    esac
    echo "$BUILD_HAXE_MIRROR/$tag/$2"
}

# asset_name <url>: default asset name of a file in the mirror, the basename
# of the URL with characters GitHub would rename replaced by "_".
asset_name() {
    basename "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

# fetch_to <url> <file>: quiet download with retries, 0 on success.
fetch_to() {
    local out="$2"
    # On Windows the curl found first can be the native curl.exe, which does
    # not understand Cygwin paths; D:/a/... works for both.
    [ "$HOST_OS" = "windows" ] && out="$(cygpath -m "$out")"
    curl -fsSL --retry 3 --retry-delay 2 --max-time 1800 -o "$out" "$1" 2>/dev/null
}

# download <url> <sha256> [asset name] [build|test]
# Prints the path of the verified file in $CACHE_DIR/downloads. The asset
# name defaults to the basename of the URL. A file that fails its checksum
# is kept as <name>.bad (overwritten by the next failure).
download() {
    local url="$1" sha="$2" name="${3:-}" release="${4:-build}"
    [ -n "$name" ] || name="$(asset_name "$url")"
    local dir="$CACHE_DIR/downloads"
    local file="$dir/$name"
    mkdir -p "$dir"
    if [ -f "$file" ] && [ "$(sha256_of "$file")" = "$sha" ]; then
        echo "$file"
        return
    fi
    # The temporary name is unique per process: builds running in parallel
    # (macOS and Docker) share the downloads folder.
    local part="$file.part.$$" got source from
    for source in mirror origin; do
        if [ "$source" = mirror ]; then
            [ "$BUILD_HAXE_MIRROR" != "none" ] || continue
            from="$(mirror_url "$release" "$name")"
        else
            if [ "${BUILD_HAXE_MIRROR_ONLY:-0}" = "1" ]; then break; fi
            from="$url"
            [ "$BUILD_HAXE_MIRROR" = "none" ] || warn "$name is not in the mirror, downloading it from $url"
        fi
        log "downloading $from" >&2
        if fetch_to "$from" "$part"; then
            got="$(sha256_of "$part")"
            if [ "$got" = "$sha" ]; then
                mv -f "$part" "$file"
                echo "$file"
                return
            fi
            warn "checksum mismatch for $from: expected $sha, got $got"
            mv -f "$part" "$file.bad"
        fi
    done
    die "could not download $name (expected sha256 $sha)"
}

# opam-repository snapshot, extracted once and shared by every opam root
opam_repo_snapshot() {
    local dir="$CACHE_DIR/opam-repository/$OPAM_REPO_COMMIT"
    if [ ! -f "$dir/repo" ]; then
        mkdir -p "$CACHE_DIR/downloads"
        local tgz
        tgz="$(fetch_git_archive "opam-repository-${OPAM_REPO_COMMIT:0:12}.tar.gz" \
            https://github.com/ocaml/opam-repository "$OPAM_REPO_COMMIT" "$OPAM_REPO_SHA256" \
            "opam-repository-$OPAM_REPO_COMMIT/")"
        log "extracting opam-repository snapshot" >&2
        mkdir -p "$dir.extract"
        tar -xzf "$tgz" -C "$dir.extract"
        mv "$dir.extract/opam-repository-$OPAM_REPO_COMMIT" "$dir"
    fi
    echo "$dir"
}

# First 12 characters of the sha256 of the profile's lock file.
lock_hash() {
    sha256_of "$PROFILE_LOCK" | cut -c1-12
}
# Asset name of the opam source cache of the profile (scripts/opam-cache.sh).
opam_cache_name() {
    echo "opam-cache-$HAXE_PROFILE-$(lock_hash).tar.gz"
}
# Target name of the machine running the script (mac-arm64, linux-x64...).
host_target() {
    case "$HOST_OS-$HOST_ARCH" in
        mac-arm64) echo mac-arm64 ;;
        mac-x86_64) echo mac-x86_64 ;;
        linux-arm64) echo linux-arm64 ;;
        linux-x86_64) echo linux-x64 ;;
        windows-x86_64) echo windows-x64 ;;
        *) die "unsupported host $HOST_OS-$HOST_ARCH" ;;
    esac
}

# sha256 of the uncompressed content of a .tar.gz. Archives of git commits
# are pinned by this value: `git archive` writes the same tar everywhere,
# while gzip output differs between systems.
tar_sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        gzip -dc "$1" | sha256sum | awk '{print $1}'
    else
        gzip -dc "$1" | shasum -a 256 | awk '{print $1}'
    fi
}

# make_git_archive <repo url> <commit> <prefix> <out file>
# Fetches one commit and writes `git archive --prefix=<prefix> | gzip -n`.
make_git_archive() {
    local repo="$1" commit="$2" prefix="$3" out="$4"
    local work="$CACHE_DIR/git-work/$(echo "$repo" | sed 's|[^A-Za-z0-9._-]|_|g')"
    mkdir -p "$work"
    [ -d "$work/.git" ] || git -C "$work" init -q
    git -C "$work" fetch -q --depth 1 "$repo" "$commit" || die "could not fetch $commit from $repo"
    [ "$(git -C "$work" rev-parse FETCH_HEAD)" = "$commit" ] || die "$repo did not return commit $commit"
    git -C "$work" archive --format=tar --prefix="$prefix" FETCH_HEAD | gzip -n -9 > "$out.part.$$"
    mv -f "$out.part.$$" "$out"
}

# fetch_git_archive <asset name> <repo url> <commit> <tar sha256> <prefix> [build|test]
# Prints the path of the archive of a pinned commit, from the cache, the
# mirror, or made from the repository. Every source is checked against the
# sha256 of the uncompressed tar (tar_sha256_of).
fetch_git_archive() {
    local name="$1" repo="$2" commit="$3" sha="$4" prefix="$5" release="${6:-build}"
    local dir="$CACHE_DIR/downloads"
    local file="$dir/$name" part="$dir/$name.part.$$" got
    mkdir -p "$dir"
    if [ -f "$file" ] && [ "$(tar_sha256_of "$file")" = "$sha" ]; then
        echo "$file"
        return
    fi
    if [ "$BUILD_HAXE_MIRROR" != "none" ]; then
        local from
        from="$(mirror_url "$release" "$name")"
        log "downloading $from" >&2
        if fetch_to "$from" "$part"; then
            if [ "$(tar_sha256_of "$part")" = "$sha" ]; then
                mv -f "$part" "$file"
                echo "$file"
                return
            fi
            warn "content mismatch for $from"
            mv -f "$part" "$file.bad"
        fi
    fi
    [ "${BUILD_HAXE_MIRROR_ONLY:-0}" != "1" ] || die "$name is not in the mirror (BUILD_HAXE_MIRROR_ONLY=1)"
    [ "$BUILD_HAXE_MIRROR" = "none" ] || warn "$name is not in the mirror, making it from $repo at $commit"
    make_git_archive "$repo" "$commit" "$prefix" "$part" >&2
    got="$(tar_sha256_of "$part")"
    if [ -n "$sha" ] && [ "$got" != "$sha" ]; then
        mv -f "$part" "$file.bad"
        die "$name: the content of $commit has sha256 $got, the pinned one is $sha"
    fi
    mv -f "$part" "$file"
    echo "$file"
}

# Host tools allowed in the build PATH, exposed one by one so that the whole
# Homebrew bin directory never ends up in the PATH.
# autotools are needed by some of neko's static dependencies.
HOST_TOOLS="cmake ninja pkg-config pkgconf autoreconf autoconf autoheader autom4te autoscan autoupdate ifnames aclocal automake glibtool glibtoolize"

prepare_hostbin() {
    local dir="$CACHE_DIR/hostbin"
    mkdir -p "$dir"
    local tool path
    for tool in $HOST_TOOLS; do
        path="$(command -v "$tool" 2>/dev/null || true)"
        case "$path" in
            ""|"$dir"/*) continue ;;
        esac
        ln -sf "$path" "$dir/$tool"
    done
    # Homebrew names GNU libtool glibtool / glibtoolize
    if [ -e "$dir/glibtoolize" ]; then ln -sf glibtoolize "$dir/libtoolize"; fi
    if [ -e "$dir/glibtool" ]; then ln -sf glibtool "$dir/libtool"; fi
    echo "$dir"
}

# Reset the environment so the build only sees our own prefixes.
# Usage: sanitize_env <target>
sanitize_env() {
    local target="$1"
    local os arch prefix neko root hostbin
    os="$(target_os "$target")"
    arch="$(target_arch "$target")"
    prefix="$(deps_prefix "$target")"
    neko="$(neko_dir "$target")"

    unset C_INCLUDE_PATH CPATH CPLUS_INCLUDE_PATH LIBRARY_PATH \
        DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH LD_LIBRARY_PATH \
        PKG_CONFIG_PATH OPAMSWITCH OCAMLPARAM CAML_LD_LIBRARY_PATH \
        OCAMLFIND_CONF OCAMLPATH OCAML_TOPLEVEL_PATH MANPATH CFLAGS LDFLAGS CPPFLAGS || true

    export HOMEBREW_NO_AUTO_UPDATE=1
    export OPAMYES=1 OPAMCOLOR=never OPAMNODEPEXTS=1 OPAMCONFIRMLEVEL=unsafe-yes
    export OPAMDOWNLOADJOBS="${OPAMDOWNLOADJOBS:-4}" OPAMJOBS="$JOBS"
    export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
    export PKG_CONFIG_PATH=""
    export C_INCLUDE_PATH="$prefix/include:$neko/include"
    export LIBRARY_PATH="$prefix/lib:$neko"

    case "$os" in
        mac)
            root="$(opam_root "$target")"
            hostbin="$(prepare_hostbin)"
            export OPAMROOT="$root" OPAMSWITCH=build
            # Bytecode tools such as camlp5o load their C stubs from here
            # (opam env would set it).
            export CAML_LD_LIBRARY_PATH="$root/build/lib/stublibs:$root/build/lib/ocaml/stublibs"
            export PATH="$root/build/bin:$neko:$(dirname "$(opam_bin "$target")"):$hostbin:/usr/bin:/bin:/usr/sbin:/sbin"
            export MACOSX_DEPLOYMENT_TARGET
            eval "MACOSX_DEPLOYMENT_TARGET=\${MACOS_MIN_$arch}"
            export DYLD_FALLBACK_LIBRARY_PATH="$neko"
            ;;
        linux)
            root="$(opam_root "$target")"
            export OPAMROOT="$root" OPAMSWITCH=build
            # Bytecode tools such as camlp5o load their C stubs from here
            # (opam env would set it).
            export CAML_LD_LIBRARY_PATH="$root/build/lib/stublibs:$root/build/lib/ocaml/stublibs"
            export PATH="$root/build/bin:$neko:$(dirname "$(opam_bin "$target")"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
            export LD_LIBRARY_PATH="$neko"
            ;;
        windows)
            # OPAMROOT and the switch come from setup-ocaml. Keep its PATH,
            # put neko first so conf-neko and nekotools find it.
            export PATH="$neko:$PATH"
            unset OPAMSWITCH
            ;;
    esac
}

# Write the effective environment next to the build outputs (checked later
# by verify-binary.sh).
record_env() {
    local out="$1"
    mkdir -p "$(dirname "$out")"
    {
        echo "PATH=$PATH"
        echo "C_INCLUDE_PATH=${C_INCLUDE_PATH:-}"
        echo "LIBRARY_PATH=${LIBRARY_PATH:-}"
        echo "PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-}"
        echo "OPAMROOT=${OPAMROOT:-}"
        echo "MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-}"
    } > "$out"
}
