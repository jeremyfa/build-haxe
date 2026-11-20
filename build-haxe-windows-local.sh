#!/usr/bin/env bash
# Build haxe and haxelib for Windows x64 on a Windows machine (not a GitHub
# runner), from Git Bash.
# Usage: ./build-haxe-windows-local.sh [--ceramic-layout]
#
# Requirements: Git for Windows (this bash), opam 2.2 or newer with its own
# Cygwin (`opam init` installs it), CMake and Visual Studio 2022 with the C++
# tools (neko is built with MSVC).
#
# What it does that build-haxe-windows.sh expects from the GitHub action:
# - an opam switch for the profile, `build-haxe-<profile>` (mingw port of the
#   OCaml version of the profile, from the pinned opam-repository snapshot).
#   It is created on the first run, next to the switches of the opam root,
#   which are left alone (BUILD_HAXE_OPAM_SWITCH names another one);
# - the copy of the sources, made here: git for Windows cannot read the paths
#   of the Cygwin bash the build runs in;
# - a native perl for the OpenSSL build of neko (Strawberry Perl, portable,
#   in .cache/tools: nothing is installed on the machine);
# - the Cygwin tools first in the PATH of the build.
#
# Environment: as build-haxe-windows.sh (HAXE_SRC_DIR or HAXE_REPO /
# HAXE_BRANCH / HAXE_COMMIT, HAXE_PROFILE, HAXE_OUT_DIR, HAXE_LAYOUT...).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

[ "$HOST_OS" = "windows" ] || die "this script runs on Windows, from Git Bash"
case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *) die "run this script from Git Bash (build-haxe-windows.sh is the one for the Cygwin bash of opam)" ;;
esac
command -v opam >/dev/null || die "opam not found (https://opam.ocaml.org/doc/Install.html)"
command -v cmake >/dev/null || die "cmake not found"

opam_root="$(opam var root | tr -d '\r')"
cygwin_bash="$(cygpath -u "$opam_root")/.cygwin/root/bin/bash.exe"
[ -x "$cygwin_bash" ] || die "the Cygwin of opam was not found at $cygwin_bash (opam init installs it)"

# Sources: a copy of HAXE_SRC_DIR, or the clone of setup-haxe.sh
cd "$ROOT"
if [ -n "${HAXE_SRC_DIR:-}" ]; then
    snapshot="$(scripts/prepare-source.sh | tail -1)"
else
    [ "${SKIP_SETUP:-0}" = "1" ] && [ -d "$ROOT/haxe/.git" ] || ./setup-haxe.sh
    snapshot="$(HAXE_SRC_DIR="$ROOT/haxe" scripts/prepare-source.sh | tail -1)"
fi
export BUILD_HAXE_SOURCE="$(cygpath -m "$snapshot")"
log "sources: $BUILD_HAXE_SOURCE"

# Profile of these sources: OCaml version and opam-repository snapshot
info="$(scripts/profile-info.sh windows-x64)"
profile="$(echo "$info" | sed -n 's/^HAXE_PROFILE=//p')"
ocaml="$(echo "$info" | sed -n 's/^OCAML_VERSION=//p')"
repo_commit="$(echo "$info" | sed -n 's/^OPAM_REPO_COMMIT=//p')"
[ -n "$profile" ] && [ -n "$ocaml" ] && [ -n "$repo_commit" ] || die "could not read the profile of the sources"

# opam switch of the profile
switch="${BUILD_HAXE_OPAM_SWITCH:-build-haxe-$profile}"
repo="build-haxe-${repo_commit:0:12}"
if ! opam switch list --short 2>/dev/null | tr -d '\r' | grep -qx "$switch"; then
    if ! opam repository list --all --short 2>/dev/null | tr -d '\r' | grep -qx "$repo"; then
        log "adding the opam repository $repo"
        opam repository add "$repo" "git+https://github.com/ocaml/opam-repository#$repo_commit" --dont-select
    fi
    log "creating the opam switch $switch with OCaml $ocaml for mingw (this compiles OCaml, it takes a while)"
    opam switch create "$switch" --no-switch --yes --repositories="$repo" \
        --packages="arch-x86_64.1,ocaml-base-compiler.$ocaml,ocaml-options-vanilla.1,system-mingw.1"
fi
export BUILD_HAXE_OPAM_SWITCH="$switch"

# Native perl for neko's build of OpenSSL
perl_dir="$CACHE_DIR/tools/strawberry-perl-$STRAWBERRY_PERL_VERSION"
if [ ! -x "$perl_dir/perl/bin/perl.exe" ]; then
    archive="$(download "$STRAWBERRY_PERL_URL" "$STRAWBERRY_PERL_SHA256")"
    log "extracting $(basename "$archive")"
    mkdir -p "$perl_dir.extract.$$"
    unzip -q -o "$archive" -d "$perl_dir.extract.$$"
    mkdir -p "$(dirname "$perl_dir")"
    [ -d "$perl_dir" ] || mv "$perl_dir.extract.$$" "$perl_dir"
    rm -rf "$perl_dir.extract.$$"
fi
perl_bin="$(cygpath -m "$perl_dir/perl/bin")"

args=""
for a in "$@"; do args="$args '$a'"; done

# The Cygwin tools first: git for Windows brings its own sh, make and file,
# which libtool cannot work with. The solver of the GitHub action
# (OPAMEXTERNALSOLVER) is left out: opam 2.5 finds no solution with it.
unset OPAMEXTERNALSOLVER
exec opam exec --switch="$switch" -- "$(cygpath -w "$cygwin_bash")" -c \
    "export PATH=/usr/bin:\$PATH:\$(cygpath -u '$perl_bin'); SKIP_SETUP=1 ./build-haxe-windows.sh$args"
