#!/usr/bin/env bash
# Install Python 3 (python-build-standalone) and PyPy 3 for the tests.
# Usage: scripts/test/tool-python.sh <target>
# Prints the environment to add, as "path:<dir>" lines (see setup-tools.sh).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-python.sh <target>}"
tools="$(test_tools_dir "$target")"
platform="$(test_platform "$target")"

# install_archive <archive> <dest> <top folder in the archive>
install_archive() {
    local archive="$1" dest="$2" top="$3"
    [ -f "$dest/.done" ] && return 0
    [ ! -e "$dest" ] || mv "$dest" "$dest.old.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$dest.extract.$$"
    tar -xf "$archive" -C "$dest.extract.$$"
    mv "$dest.extract.$$/$top" "$dest"
    touch "$dest/.done"
}

# Python 3: the archive holds python/
python="$tools/python-$TEST_PYTHON_VERSION"
install_archive "$(test_file PYTHON "$target")" "$python" python
if [ "$platform" = "WINDOWS_X64" ]; then
    # RunCi calls python3: give python.exe that name too.
    [ -f "$python/python3.exe" ] || cp "$python/python.exe" "$python/python3.exe"
    "$python/python3.exe" --version >&2
    echo "path:$python"
else
    "$python/bin/python3" --version >&2
    echo "path:$python/bin"
fi

# PyPy 3 (RunCi uses it on macOS and Linux only)
if [ "$platform" != "WINDOWS_X64" ]; then
    archive="$(test_file PYPY "$target")"
    name="$(basename "$archive")"
    pypy="$tools/pypy$TEST_PYPY_VERSION"
    install_archive "$archive" "$pypy" "${name%.tar.bz2}"
    [ -e "$pypy/bin/pypy3" ] || die "pypy3 missing in $pypy/bin"
    "$pypy/bin/pypy3" --version >&2
    echo "path:$pypy/bin"
fi
