#!/usr/bin/env bash
# Archive an assembled folder.
# Usage: scripts/package.sh <target> [standard|ceramic]
#   (--ceramic-layout is accepted for ceramic)
# Output: build/archives/haxe-<profile>-<build id>-<target>[-ceramic].{zip,tar.gz}
#
# standard: the archive holds a single haxe/ folder (neko in haxe/neko/, next
#   to the executables on Windows).
# ceramic: haxe/ and neko/ side by side, as in ceramic's git/haxe-binary
#   (<mac|linux-x86_64|linux-arm64|windows>/{haxe,neko}). Lookups stay
#   relative: haxelib finds libneko through an rpath to ../neko on macOS and
#   Linux. On Windows a DLL is only found next to the executable, so haxe/
#   also holds the neko runtime used by haxelib.exe (neko.dll, the .ndll
#   modules and the DLLs they need), and neko/ holds the full neko.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: package.sh <target> [standard|ceramic]}"
layout="${2:-standard}"
[ "$layout" = "--ceramic-layout" ] && layout=ceramic
case "$layout" in standard|ceramic) ;; *) die "unknown layout '$layout'" ;; esac
check_target "$target"
load_profile

os="$(target_os "$target")"
base="$(layout_folder "$target" standard)"
[ -d "$base/haxe" ] || die "$base/haxe missing (run scripts/assemble.sh $target)"
src="$base"

if [ "$layout" = "ceramic" ]; then
    src="$(layout_folder "$target" ceramic)"
    if [ -e "$src" ]; then
        mv "$src" "$src.old.$(date +%Y%m%d%H%M%S)"
    fi
    mkdir -p "$src/haxe" "$src/neko"
    if [ "$os" = "windows" ]; then
        # Files that come from neko, by name.
        neko="$(neko_dir "$target")"
        is_neko_file() { [ -e "$neko/$1" ]; }
        for f in "$base/haxe"/* "$base/haxe"/.[!.]*; do
            [ -e "$f" ] || continue
            n="$(basename "$f")"
            if is_neko_file "$n"; then
                cp -R -P "$f" "$src/neko/"
                # Runtime of haxelib.exe: neko.dll, modules and DLLs.
                case "$n" in
                    *.dll|*.ndll) cp -P "$f" "$src/haxe/" ;;
                esac
            else
                cp -R -P "$f" "$src/haxe/"
            fi
        done
    else
        for f in "$base/haxe"/* "$base/haxe"/.[!.]*; do
            [ -e "$f" ] || continue
            [ "$(basename "$f")" = neko ] && continue
            cp -R -P "$f" "$src/haxe/"
        done
        cp -R -P "$base/haxe/neko/." "$src/neko/"
        case "$os" in
            mac)
                # Changing the rpath invalidates the signature: sign again.
                install_name_tool -rpath @executable_path/neko @executable_path/../neko "$src/haxe/haxelib" 2>/dev/null
                msg="$(codesign --force --sign "${SIGN_IDENTITY:--}" "$src/haxe/haxelib" 2>&1)" || die "codesign failed: $msg"
                ;;
            linux)
                patchelf --set-rpath '$ORIGIN/../neko' "$src/haxe/haxelib"
                ;;
        esac
    fi
fi

archive="$(layout_archive "$target" "$layout")"
mkdir -p "$(dirname "$archive")"
rm -f "$archive"
case "$archive" in
    *.zip)
        if command -v zip >/dev/null; then
            (cd "$src" && zip -q -r -y "$archive" .)
        else
            powershell -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$src")\\*' -DestinationPath '$(cygpath -w "$archive")'"
        fi
        ;;
    *)
        load_source_info
        if tar --version 2>/dev/null | grep -q 'GNU tar'; then
            (cd "$src" && tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="$SRC_DATE" -czf "$archive" .)
        else
            (cd "$src" && tar -czf "$archive" .)
        fi
        ;;
esac

log "archive: $archive"
