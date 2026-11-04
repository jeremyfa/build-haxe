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

# hererocks from the pinned commit of its repository, run with the pinned
# Python. Only this command goes on the PATH: RunCi 4.3 runs `pip install
# --user hererocks`, which must reach the pip of that Python.
src="$(git_dep_src HEREROCKS)"
expose="$tools/hererocks-${TEST_GIT_HEREROCKS_COMMIT:0:12}"
mkdir -p "$expose"
python="$(command -v python3)"
if [ "$platform" = "WINDOWS_X64" ]; then
    printf '@"%s" "%s" %%*\r\n' "$(cygpath -w "$python")" "$(cygpath -w "$src/hererocks.py")" > "$expose/hererocks.cmd"
    printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$python" "$src/hererocks.py" > "$expose/hererocks"
else
    printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$python" "$src/hererocks.py" > "$expose/hererocks"
fi
chmod +x "$expose/hererocks"
"$expose/hererocks" --version >&2
echo "path:$expose"

# RunCi 4.3 runs `pip install --user hererocks`: pip finds (PIP_FIND_LINKS,
# offline) a wheel made here from the same pinned commit. A wheel is a zip of
# the module and its metadata; it comes from checked sources, so it needs no
# pinned sha256 of its own.
wheels="$tools/pip-wheels-hererocks-${TEST_GIT_HEREROCKS_COMMIT:0:12}"
mkdir -p "$wheels"
python3 - "$src/hererocks.py" "$wheels" <<'PY'
import base64, hashlib, os, re, sys, zipfile
module, out = sys.argv[1], sys.argv[2]
code = open(module, "rb").read()
version = re.search(rb'__version__ = "([^"]+)"', code).group(1).decode()
dist = "hererocks-%s.dist-info" % version
files = {
    "hererocks.py": code,
    dist + "/METADATA": ("Metadata-Version: 2.1\nName: hererocks\nVersion: %s\n" % version).encode(),
    dist + "/WHEEL": b"Wheel-Version: 1.0\nGenerator: build-haxe\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
    dist + "/entry_points.txt": b"[console_scripts]\nhererocks = hererocks:main\n",
}
record = ""
for name, data in files.items():
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    record += "%s,sha256=%s,%d\n" % (name, digest, len(data))
record += dist + "/RECORD,,\n"
files[dist + "/RECORD"] = record.encode()
path = os.path.join(out, "hererocks-%s-py3-none-any.whl" % version)
with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
    for name, data in files.items():
        z.writestr(zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0)), data)
PY
echo "env:PIP_NO_INDEX=1"
echo "env:PIP_PRE=1"
echo "env:PIP_FIND_LINKS=$( [ "$HOST_OS" = windows ] && cygpath -m "$wheels" || echo "$wheels")"
echo "env:PIP_DISABLE_PIP_VERSION_CHECK=1"
