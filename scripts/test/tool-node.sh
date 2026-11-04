#!/usr/bin/env bash
# Install Node.js for the tests.
# Usage: scripts/test/tool-node.sh <target>
# Prints the environment to add, as "path:" and "env:" lines (see setup-tools.sh).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-node.sh <target>}"
tools="$(test_tools_dir "$target")"
platform="$(test_platform "$target")"

archive="$(test_file NODE "$target")"
name="$(basename "$archive")"
top="${name%.tar.xz}"; top="${top%.zip}"
node="$tools/node-$TEST_NODE_VERSION"
if [ ! -f "$node/.done" ]; then
    [ ! -e "$node" ] || mv "$node" "$node.old.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$node.extract.$$"
    case "$archive" in
        *.zip) extract_zip "$archive" "$node.extract.$$" ;;
        *) tar -xf "$archive" -C "$node.extract.$$" ;;
    esac
    mv "$node.extract.$$/$top" "$node"
    touch "$node/.done"
fi

if [ "$platform" = "WINDOWS_X64" ]; then
    "$node/node.exe" --version >&2
    echo "path:$node"
else
    "$node/bin/node" --version >&2
    echo "path:$node/bin"
fi
# npm downloads stay in the cache
echo "env:npm_config_cache=$CACHE_DIR/npm"
