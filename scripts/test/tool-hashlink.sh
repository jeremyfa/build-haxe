#!/usr/bin/env bash
# Build and install HashLink (pinned commit TEST_GIT_HASHLINK) for the tests.
# Usage: scripts/test/tool-hashlink.sh <target>
# Prints the environment to add (see setup-tools.sh).
#
# Same CMake options as RunCi. Dependencies: system packages in the Linux
# test image; on macOS, HashLink's own DOWNLOAD_DEPENDENCIES mode, whose
# downloads are checked against the hashes pinned in the HashLink commit.
# RunCi skips its own build when it finds hl, but then also skips adding it to
# the PATH and `haxelib dev hashlink`: done here and by haxelibs.sh.
# On arm64 HashLink has no VM (JIT), only libhl and the hdll libraries for
# HL/C: a placeholder hl reports that, and RunCi runs with --skip-hl-jit.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-hashlink.sh <target>}"
tools="$(test_tools_dir "$target")"
platform="$(test_platform "$target")"
src="$(git_dep_src HASHLINK)"
id="${TEST_GIT_HASHLINK_COMMIT:0:12}"
prefix="$tools/hashlink-$id"
build="$tools/hashlink-build-$id"

if [ ! -f "$prefix/.done" ]; then
    [ ! -e "$prefix" ] || mv "$prefix" "$prefix.old.$(date +%Y%m%d%H%M%S)"
    args=(-DBUILD_TESTING=OFF -DWITH_DIRECTX=OFF -DWITH_FMT=ON -DWITH_OPENAL=OFF -DWITH_SDL=OFF
        -DWITH_SQLITE=ON -DWITH_SSL=ON -DWITH_UI=OFF -DWITH_UV=OFF -DWITH_VIDEO=OFF
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
    case "$platform" in
        MAC_*) args+=(-G Ninja -DDOWNLOAD_DEPENDENCIES=ON) ;;
        LINUX_*) args+=(-G Ninja) ;;
        WINDOWS_*) die "HashLink on Windows is built by the CI job (MSVC), not supported here yet" ;;
    esac
    log "building HashLink ${TEST_GIT_HASHLINK_COMMIT:0:12}"
    cmake -S "$src" -B "$build" "${args[@]}" >&2
    cmake --build "$build" --parallel "$JOBS" >&2
    cmake --install "$build" >&2
    if [ ! -x "$prefix/bin/hl" ]; then
        mkdir -p "$prefix/bin"
        printf '#!/bin/sh\necho "this HashLink build has no VM (arm64): HL/C only" >&2\nexit 1\n' > "$prefix/bin/hl"
        chmod +x "$prefix/bin/hl"
        touch "$prefix/.no-vm"
    fi
    touch "$prefix/.done"
fi

# RunCi looks for HashLink in ~/haxe-ci/hashlink when hl does not run.
mkdir -p "$HOME/haxe-ci"
ln -sfn "$prefix" "$HOME/haxe-ci/hashlink"

if [ -f "$prefix/.no-vm" ]; then
    log "HashLink: HL/C only (no VM on this architecture)" >&2
else
    "$prefix/bin/hl" --version >&2
fi
echo "path:$prefix/bin"
case "$platform" in
    MAC_*) echo "env:DYLD_FALLBACK_LIBRARY_PATH=$prefix/lib" ;;
    LINUX_*) echo "env:LD_LIBRARY_PATH=$prefix/lib" ;;
esac
