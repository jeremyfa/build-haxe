#!/usr/bin/env bash
# Build the npm package deasync (native addon used by the sys tests of the js
# target) from the pinned package files, once per platform.
# Usage: scripts/test/tool-deasync.sh <target>
# Needs node (tool-node.sh), python3 (tool-python.sh) and a C++ compiler.
# Prints "env:BUILD_HAXE_NODE_MODULES=<dir>": test-haxe.sh copies that
# node_modules folder into tests/sys of each test copy, so RunCi finds
# deasync (`npm list deasync`) and never installs it from the registry.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-deasync.sh <target>}"
tools="$(test_tools_dir "$target")"
command -v node >/dev/null && command -v npm >/dev/null || die "node and npm must be on the PATH (tool-node.sh)"

files=()
for p in $TEST_NPM_PACKAGES; do
    f="$(test_file_any "NPM_$p")"
    [ "$HOST_OS" = "windows" ] && f="$(cygpath -m "$f")"
    files+=("$f")
done
id="$(printf '%s\n' "${files[@]}" | xargs -n1 basename | sort | tr '\n' ' ' | sha256_stdin | cut -c1-12)"
dir="$tools/npm-deasync-node$TEST_NODE_VERSION-$id"

if [ ! -f "$dir/.done" ]; then
    [ ! -e "$dir" ] || mv "$dir" "$dir.old.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$dir"
    echo '{"name":"build-haxe-test-deps","private":true}' > "$dir/package.json"
    # node-gyp takes the headers from the pinned node instead of downloading
    # them; every package comes from the files above (--offline).
    nodedir="$(dirname "$(dirname "$(command -v node)")")"
    [ "$HOST_OS" = "windows" ] && nodedir="$(cygpath -m "$(dirname "$(command -v node)")")"
    (
        cd "$dir"
        npm install --offline --no-save --no-package-lock --no-audit --no-fund \
            --ignore-scripts "${files[@]}" >&2
    )
    # npm no longer runs install scripts by default: run deasync's build.js
    # here. It keeps the prebuilt binary of the package when there is one for
    # this platform and node version, and otherwise builds the addon with the
    # node-gyp bundled with npm.
    gyp="$(dirname "$(command -v node)")"
    [ -f "$gyp/../lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js" ] \
        && gyp="$gyp/../lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js" \
        || gyp="$gyp/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js"
    [ -f "$gyp" ] || die "node-gyp not found next to node"
    mkdir -p "$dir/.gyp-bin"
    printf '#!/bin/sh\nexec node "%s" "$@"\n' "$gyp" > "$dir/.gyp-bin/node-gyp"
    chmod +x "$dir/.gyp-bin/node-gyp"
    printf '@node "%s" %%*\r\n' "$( [ "$HOST_OS" = windows ] && cygpath -w "$gyp" || echo "$gyp")" > "$dir/.gyp-bin/node-gyp.cmd"
    (
        cd "$dir/node_modules/deasync"
        PATH="$dir/.gyp-bin:$PATH" npm_config_nodedir="$nodedir" node build.js >&2
    )
    node -e "require('$dir/node_modules/deasync')" || die "deasync does not load"
    touch "$dir/.done"
fi
echo "env:BUILD_HAXE_NODE_MODULES=$dir/node_modules"
