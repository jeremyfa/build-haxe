#!/usr/bin/env bash
# Install hererocks for the lua target.
# Usage: scripts/test/tool-lua.sh <target>
# Needs python3 (tool-python.sh). Prints the environment to add (see
# setup-tools.sh).
#
# RunCi then creates one Lua environment per tested Lua version with
# hererocks (under $HOME/haxe-ci/lua_env, in the cache) and installs the
# rocks it needs with LuaRocks. Those sources come from lua.org, the LuaJIT
# and LuaRocks repositories and luarocks.org: they are not pinned here (see
# README.md). The C libraries of the rocks come from the Linux test image, and
# from Homebrew on macOS (Brewfile.tests), as RunCi expects.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-lua.sh <target>}"
tools="$(test_tools_dir "$target")"
platform="$(test_platform "$target")"
command -v python3 >/dev/null || die "python3 must be on the PATH (tool-python.sh)"

venv="$tools/hererocks-$TEST_HEREROCKS_VERSION"
wheels="$tools/pip-wheels-hererocks-$TEST_HEREROCKS_VERSION"
if [ ! -f "$venv/.done" ]; then
    [ ! -e "$venv" ] || mv "$venv" "$venv.old.$(date +%Y%m%d%H%M%S)"
    wheel="$(test_file_any PIP_HEREROCKS)"
    mkdir -p "$wheels"
    cp -f "$wheel" "$wheels/"
    wheel="$wheels/$(basename "$wheel")"
    [ "$HOST_OS" = "windows" ] && wheel="$(cygpath -m "$wheel")"
    python3 -m venv "$venv" >&2
    if [ "$platform" = "WINDOWS_X64" ]; then
        "$venv/Scripts/python.exe" -m pip install --no-index --no-deps "$wheel" >&2
    else
        "$venv/bin/python3" -m pip install --no-index --no-deps "$wheel" >&2
    fi
    # Only the hererocks command goes on the PATH, not the pip of the venv:
    # RunCi 4.3 runs `pip install --user hererocks`, which a venv refuses.
    mkdir -p "$venv/expose"
    if [ "$platform" = "WINDOWS_X64" ]; then
        cp -f "$venv/Scripts/hererocks.exe" "$venv/expose/"
    else
        ln -sf "$venv/bin/hererocks" "$venv/expose/hererocks"
    fi
    touch "$venv/.done"
fi
[ "$platform" = "WINDOWS_X64" ] || "$venv/expose/hererocks" --version >&2
echo "path:$venv/expose"
# Any `pip install hererocks` (RunCi 4.3) gets the pinned wheel, offline.
echo "env:PIP_NO_INDEX=1"
echo "env:PIP_FIND_LINKS=$( [ "$HOST_OS" = windows ] && cygpath -m "$wheels" || echo "$wheels")"
echo "env:PIP_DISABLE_PIP_VERSION_CHECK=1"
