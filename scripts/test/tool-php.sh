#!/usr/bin/env bash
# Install PHP for the tests.
# Usage: scripts/test/tool-php.sh <target>
# Prints the environment to add, as "path:" lines (see setup-tools.sh).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-php.sh <target>}"
tools="$(test_tools_dir "$target")"
platform="$(test_platform "$target")"

archive="$(test_file PHP "$target")"
php="$tools/php-$(basename "$archive" | sed -E 's/\.(tar\.gz|zip)$//')"
if [ ! -f "$php/.done" ]; then
    [ ! -e "$php" ] || mv "$php" "$php.old.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$php.extract.$$"
    case "$archive" in
        # official Windows build: php.exe and ext/ at the root of the zip
        *.zip) unzip -q "$archive" -d "$php.extract.$$" ;;
        # static-php-cli: a single static php binary
        *) tar -xzf "$archive" -C "$php.extract.$$" ;;
    esac
    mv "$php.extract.$$" "$php"
    touch "$php/.done"
fi

if [ "$platform" = "WINDOWS_X64" ]; then
    "$php/php.exe" -v | head -1 >&2
else
    chmod +x "$php/php"
    "$php/php" -v | head -1 >&2
    modules="$("$php/php" -m)"
    for ext in mbstring sqlite3 pdo_sqlite sockets; do
        echo "$modules" | grep -qx "$ext" || die "PHP in $php lacks the $ext extension"
    done
fi
echo "path:$php"
