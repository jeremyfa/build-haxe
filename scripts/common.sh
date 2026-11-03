#!/usr/bin/env bash
# Shared helpers. Sourced by every script, never executed directly.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HAXE_DIR="$ROOT/haxe"

log() { echo "[build-haxe] $*"; }
warn() { echo "[build-haxe] warning: $*" >&2; }
die() { echo "[build-haxe] error: $*" >&2; exit 1; }

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

# Profile loading. HAXE_PROFILE must be set (see scripts/detect-profile.sh).
load_profile() {
    [ -n "${HAXE_PROFILE:-}" ] || die "HAXE_PROFILE is not set"
    local file="$ROOT/profiles/$HAXE_PROFILE/profile.env"
    [ -f "$file" ] || die "unknown profile '$HAXE_PROFILE' ($file not found)"
    # shellcheck disable=SC1090
    source "$file"
    if [ "$MBEDTLS_SERIES" = "3" ]; then
        MBEDTLS_VERSION="$MBEDTLS3_VERSION"; MBEDTLS_URL="$MBEDTLS3_URL"; MBEDTLS_SHA256="$MBEDTLS3_SHA256"
    else
        MBEDTLS_VERSION="$MBEDTLS2_VERSION"; MBEDTLS_URL="$MBEDTLS2_URL"; MBEDTLS_SHA256="$MBEDTLS2_SHA256"
    fi
    local v
    v="NEKO_${NEKO_SOURCE}_COMMIT"; NEKO_COMMIT="${!v:?unknown NEKO_SOURCE $NEKO_SOURCE}"
    v="NEKO_${NEKO_SOURCE}_SHA256"; NEKO_SHA256="${!v}"
    v="NEKO_${NEKO_SOURCE}_NAME"; NEKO_NAME="${!v}"
    export HAXE_PROFILE OCAML_VERSION MBEDTLS_SERIES MBEDTLS_VERSION NEKO_COMMIT NEKO_NAME
}

# Paths, all inside the project directory
deps_prefix() { echo "$ROOT/build/deps/$HAXE_PROFILE/$1"; }
deps_work() { echo "$ROOT/build/deps-work/$1"; }
# One opam root per profile, target and OCaml version, so changing the
# compiler never reuses (or needs to delete) an existing root.
opam_root() {
    local name="$HAXE_PROFILE-$1-ocaml$OCAML_VERSION"
    if [ -n "${BUILD_HAXE_OPAMROOT_BASE:-}" ]; then
        echo "$BUILD_HAXE_OPAMROOT_BASE/$name"
    else
        echo "$ROOT/.cache/opam/$name"
    fi
}
stage_dir() { echo "$ROOT/build/$HAXE_PROFILE/$1/stage"; }
dune_build_dir() { echo "_build-$1"; }

# neko built from source (scripts/build-neko.sh), one folder per neko source
# and target, with the flat layout of the official neko archives.
neko_dir() { echo "$ROOT/build/neko/$NEKO_NAME/$1"; }

opam_bin() {
    local os arch
    os="$(target_os "$1")"
    arch="$(target_arch "$1")"
    case "$os" in
        mac) echo "$ROOT/.cache/bin/macos-$arch/opam" ;;
        linux) echo "$ROOT/.cache/bin/linux-$arch/opam" ;;
        windows) command -v opam ;;
    esac
}

haxe_commit() { git -C "$HAXE_DIR" rev-parse HEAD; }
haxe_short() { git -C "$HAXE_DIR" rev-parse --short=10 HEAD; }

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

# download URL SHA256 -> prints the path of the verified file in .cache/downloads
download() {
    local url="$1" sha="$2"
    local dir="$ROOT/.cache/downloads"
    local file="$dir/$(basename "$url")"
    mkdir -p "$dir"
    if [ -f "$file" ] && [ "$(sha256_of "$file")" = "$sha" ]; then
        echo "$file"
        return
    fi
    log "downloading $url" >&2
    # The temporary name is unique per process: builds running in parallel
    # (macOS and Docker) share .cache/downloads.
    local part="$file.part.$$"
    curl -fsSL --retry 5 --retry-delay 2 -o "$part" "$url"
    local got
    got="$(sha256_of "$part")"
    if [ "$got" != "$sha" ]; then
        rm -f "$part"
        die "checksum mismatch for $url: expected $sha, got $got"
    fi
    mv -f "$part" "$file"
    echo "$file"
}

# Host tools allowed in the build PATH, exposed one by one so that the whole
# Homebrew bin directory never ends up in the PATH.
# autotools are needed by some of neko's static dependencies.
HOST_TOOLS="cmake ninja pkg-config pkgconf autoreconf autoconf autoheader autom4te autoscan autoupdate ifnames aclocal automake glibtool glibtoolize"

prepare_hostbin() {
    local dir="$ROOT/.cache/hostbin"
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
