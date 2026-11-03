#!/usr/bin/env bash
# Assemble the distributable folder for a target from the stage directory.
# Usage: scripts/assemble.sh <target>
# Output: build/<profile>/<target>/<short commit>/haxe/
#   haxe, haxelib, std/, neko/ (next to the executables on Windows),
#   commit.txt, build_info.txt, CHANGES.txt, CONTRIB.txt, LICENSE.txt
#
# The folder is assembled from scratch in a new directory. An existing one for
# the same commit is renamed to <short>.old.<date> (never deleted, see
# clean-haxe.sh), so a new build never mixes files with an older one.
# Prints the folder path on the last line.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: assemble.sh <target>}"
check_target "$target"
load_profile

os="$(target_os "$target")"
stage="$(stage_dir "$target")"
neko="$(neko_dir "$target")"
short="$(cut -c1-10 "$stage/commit.txt")"
base="$ROOT/build/$HAXE_PROFILE/$target/$short"
work="$base.new.$$"
out="$work/haxe"
exe=""
[ "$os" = "windows" ] && exe=".exe"

for f in "haxe$exe" "haxelib$exe" commit.txt build_info.txt; do
    [ -f "$stage/$f" ] || die "$stage/$f missing"
done
[ "$(cat "$stage/commit.txt")" = "$(haxe_commit)" ] || die "stage was built from $(cat "$stage/commit.txt"), haxe/ is at $(haxe_commit)"

mkdir -p "$out"
for f in "haxe$exe" "haxelib$exe" commit.txt build_info.txt; do
    replace_file "$stage/$f" "$out/$f"
done
for f in CHANGES.txt CONTRIB.txt LICENSE.txt; do
    if [ -f "$HAXE_DIR/extra/$f" ]; then cp -f "$HAXE_DIR/extra/$f" "$out/"; fi
done
mkdir -p "$out/std"
cp -R "$HAXE_DIR/std/." "$out/std/"

# Neko runtime used by haxelib: libneko, ndll modules and the neko tools.
if [ "$os" = "windows" ]; then
    nekodest="$out"
else
    nekodest="$out/neko"
    mkdir -p "$nekodest"
fi
for f in "$neko"/*; do
    case "$(basename "$f")" in
        include|CMake|README.md|.done|*.lib) continue ;;
    esac
    if [ -f "$f" ] && [ ! -L "$f" ]; then
        replace_file "$f" "$nekodest/$(basename "$f")"
    else
        cp -R -P "$f" "$nekodest/"
    fi
done
if [ "$os" != "windows" ]; then
    mv -f "$nekodest/LICENSE" "$nekodest/LICENSE.txt" 2>/dev/null || true
fi

if [ "$os" = "mac" ]; then
    # Ad hoc signature (required on Apple Silicon). SIGN_IDENTITY switches to
    # a Developer ID signature with the hardened runtime.
    if [ -n "${SIGN_IDENTITY:-}" ]; then
        sign=(codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY")
    else
        sign=(codesign --force --sign -)
    fi
    for f in "$nekodest"/*.dylib "$nekodest"/*.ndll "$nekodest/neko" "$nekodest/nekoc" \
        "$nekodest/nekoml" "$nekodest/nekotools" "$out/haxelib" "$out/haxe"; do
        if [ -f "$f" ] && [ ! -L "$f" ]; then
            msg="$("${sign[@]}" "$f" 2>&1)" || die "codesign failed for $f: $msg"
        fi
    done
fi

if [ -e "$base" ]; then
    old="$base.old.$(date +%Y%m%d%H%M%S)"
    mv "$base" "$old"
    log "previous folder moved to $old"
fi
mv "$work" "$base"
out="$base/haxe"

log "assembled $out"
echo "$out"
