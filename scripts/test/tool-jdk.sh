#!/usr/bin/env bash
# Install a JDK (Eclipse Temurin) for the tests.
# Usage: scripts/test/tool-jdk.sh <target>
# Prints the environment to add, as "path:" and "env:" lines (see setup-tools.sh).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-jdk.sh <target>}"
tools="$(test_tools_dir "$target")"
platform="$(test_platform "$target")"

archive="$(test_file JDK "$target")"
jdk="$tools/jdk-$TEST_JDK_VERSION"
if [ ! -f "$jdk/.done" ]; then
    [ ! -e "$jdk" ] || mv "$jdk" "$jdk.old.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$jdk.extract.$$"
    case "$archive" in
        *.zip) extract_zip "$archive" "$jdk.extract.$$" ;;
        *) tar -xzf "$archive" -C "$jdk.extract.$$" ;;
    esac
    mv "$jdk.extract.$$/jdk-$TEST_JDK_VERSION" "$jdk"
    touch "$jdk/.done"
fi

# macOS archives hold a bundle: the JDK is in Contents/Home.
home="$jdk"
[ -d "$jdk/Contents/Home" ] && home="$jdk/Contents/Home"
if [ "$platform" = "WINDOWS_X64" ]; then
    "$home/bin/java.exe" -version >&2
    echo "env:JAVA_HOME=$(cygpath -w "$home")"
else
    "$home/bin/java" -version >&2
    echo "env:JAVA_HOME=$home"
fi
echo "path:$home/bin"
