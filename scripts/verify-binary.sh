#!/usr/bin/env bash
# Portability and self-containment checks on an assembled folder.
# Usage: scripts/verify-binary.sh <folder> <target> [standard|ceramic]
#   standard: <folder> is the haxe/ folder (neko in haxe/neko/, next to the
#             executables on Windows)
#   ceramic:  <folder> holds haxe/ and neko/ side by side
# Exits non-zero when a check failed.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

folder="${1:?usage: verify-binary.sh <folder> <target> [standard|ceramic]}"
target="${2:?usage: verify-binary.sh <folder> <target> [standard|ceramic]}"
layout="${3:-standard}"
check_target "$target"
load_profile

os="$(target_os "$target")"
if [ "$layout" = "ceramic" ]; then
    dir="$folder/haxe"
    nekodir="$folder/neko"
    nekorel="../neko"
elif [ "$os" = "windows" ]; then
    dir="$folder"
    nekodir="$folder"
    nekorel="."
else
    dir="$folder"
    nekodir="$folder/neko"
    nekorel="neko"
fi
arch="$(target_arch "$target")"
failures=0
ok() { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; failures=$((failures + 1)); }

# Run a command with an empty environment, so nothing outside the folder helps.
run_clean() {
    local home
    home="$(mktemp -d "${TMPDIR:-/tmp}/build-haxe-verify.XXXXXX")"
    env -i HOME="$home" PATH="/usr/bin:/bin" "$@"
}

expected_version_prefix() {
    case "${PROFILE_BASE:-$HAXE_PROFILE}" in
        haxe43) echo "4.3." ;;
        haxe5) echo "5." ;;
        *) echo "" ;;
    esac
}

check_version() {
    local out="$1" label="$2" prefix
    prefix="$(expected_version_prefix)"
    case "$out" in
        "$prefix"*) ok "$label: $out" ;;
        *) fail "$label: unexpected version '$out' (expected $prefix*)" ;;
    esac
}

# haxelib commands that load the neko modules (std, zlib...), run with an
# empty environment and a throwaway repository. Run twice: the second time
# NEKOPATH points to decoy modules (corrupted std.ndll and friends), which
# must be ignored because neko looks next to libneko first.
check_haxelib() {
    local exe="$1" home out decoy m
    home="$(mktemp -d "${TMPDIR:-/tmp}/build-haxe-haxelib.XXXXXX")"
    # haxelib.exe is a native program on Windows: Windows paths, and the
    # user profile it reads instead of HOME.
    local nhome="$home" winenv=""
    if [ "$os" = "windows" ]; then
        nhome="$(cygpath -m "$home")"
        winenv="USERPROFILE=$nhome SystemRoot=${SYSTEMROOT:-C:\\Windows}"
    fi
    out="$(cd "$dir" && env -i HOME="$nhome" $winenv PATH="/usr/bin:/bin" sh -c \
        "'$exe' setup '$nhome/lib' >/dev/null && '$exe' list >/dev/null && '$exe' version" 2>&1 || true)"
    case "$out" in
        [0-9]*) ok "haxelib setup, list and version: $out" ;;
        *) fail "haxelib: $out" ;;
    esac
    decoy="$home/decoy"
    mkdir -p "$decoy"
    for m in std zlib regexp ssl sqlite mysql; do echo "not a module" > "$decoy/$m.ndll"; done
    local ndecoy="$decoy"
    [ "$os" = "windows" ] && ndecoy="$(cygpath -m "$decoy")"
    out="$(cd "$dir" && env -i HOME="$nhome" $winenv PATH="/usr/bin:/bin" NEKOPATH="$ndecoy" sh -c \
        "'$exe' list >/dev/null && '$exe' version" 2>&1 || true)"
    case "$out" in
        [0-9]*) ok "haxelib ignores decoy modules in NEKOPATH (uses its own neko folder)" ;;
        *) fail "haxelib loaded modules from NEKOPATH instead of its own folder: $out" ;;
    esac
}

# haxe calls the haxelib next to it for -lib, even when another haxelib comes
# first in the PATH (profiles/*/patches/all-haxelib-next-to-haxe.patch).
check_haxe_uses_own_haxelib() {
    local home out
    home="$(mktemp -d "${TMPDIR:-/tmp}/build-haxe-lib.XXXXXX")"
    mkdir -p "$home/decoy" "$home/lib" "$home/src"
    printf '#!/bin/sh\necho DECOY haxelib used >&2\nexit 1\n' > "$home/decoy/haxelib"
    chmod +x "$home/decoy/haxelib"
    (cd "$dir" && env -i HOME="$home" PATH="/usr/bin:/bin" ./haxelib setup "$home/lib" >/dev/null 2>&1) || true
    out="$(cd "$home/src" && env -i HOME="$home" PATH="$home/decoy:/usr/bin:/bin" "$dir/haxe" -lib build_haxe_missing_lib --no-output 2>&1 || true)"
    case "$out" in
        *DECOY*) fail "haxe called the haxelib found in the PATH: $out" ;;
        *build_haxe_missing_lib*) ok "haxe -lib uses the haxelib next to it" ;;
        *) fail "haxe -lib: unexpected output: $out" ;;
    esac
}

# No global module path compiled into libneko (patches/neko).
check_no_global_module_path() {
    local lib
    for lib in "$nekodir"/libneko*.dylib "$nekodir"/libneko.so* "$nekodir"/neko.dll "$dir"/neko.dll; do
        [ -f "$lib" ] && [ ! -L "$lib" ] || continue
        if grep -a -q -E '/usr/local/lib/neko|/usr/lib/neko' "$lib"; then
            fail "$(basename "$lib") still contains global module paths"
        else
            ok "$(basename "$lib") has no global module path"
        fi
    done
}

echo "verifying $folder ($target, $layout layout)"

case "$os" in
    mac)
        libs="$(otool -L "$dir/haxe" | grep -v ':$' | awk '{print $1}' | sort -u)"
        bad="$(echo "$libs" | grep -v -E '^(/usr/lib/libSystem\.B\.dylib|/usr/lib/libresolv\.9\.dylib|/usr/lib/libc\+\+\.1\.dylib|/System/Library/Frameworks/)' || true)"
        [ -z "$bad" ] && ok "haxe links only system libraries" || fail "haxe links non-system libraries: $bad"

        libs="$(otool -L "$dir/haxelib" | grep -v ':$' | awk '{print $1}' | sort -u)"
        bad="$(echo "$libs" | grep -v -E '^(/usr/lib/libSystem\.B\.dylib|@rpath/libneko\.2\.dylib)$' || true)"
        [ -z "$bad" ] && ok "haxelib links only libSystem and libneko" || fail "haxelib links: $bad"
        rpaths="$(otool -l "$dir/haxelib" | awk '/LC_RPATH/{getline; getline; print $2}' | sort -u)"
        [ "$rpaths" = "@executable_path/$nekorel" ] && ok "haxelib rpath is @executable_path/$nekorel" || fail "haxelib rpaths: $rpaths"

        archs="$(lipo -archs "$dir/haxe")"
        case "$arch" in
            universal) want_archs="x86_64 arm64" ;;
            *) want_archs="$arch" ;;
        esac
        [ "$archs" = "$want_archs" ] && ok "haxe architectures: $archs" || fail "haxe architectures: '$archs', expected '$want_archs'"

        for a in $archs; do
            # LC_BUILD_VERSION has "minos"; targets before 10.14 get
            # LC_VERSION_MIN_MACOSX, which has "version" instead.
            minos="$(vtool -arch "$a" -show-build "$dir/haxe" 2>/dev/null | awk '$1 == "minos" || $1 == "version" {print $2; exit}')"
            eval "want=\${MACOS_MIN_$a}"
            [ "$minos" = "$want" ] && ok "haxe $a minos $minos" || fail "haxe $a minos '$minos', expected '$want'"
        done

        for f in "$dir/haxe" "$dir/haxelib"; do
            codesign --verify --strict "$f" 2>/dev/null && ok "$(basename "$f") signature valid" || fail "$(basename "$f") signature invalid"
        done

        check_version "$(run_clean "$dir/haxe" --version 2>&1)" "haxe --version (native)"
        if [ "$arch" = "universal" ] || [ "$arch" = "x86_64" ]; then
            if arch -x86_64 /usr/bin/true 2>/dev/null; then
                check_version "$(run_clean /usr/bin/arch -x86_64 "$dir/haxe" --version 2>&1)" "haxe --version (x86_64)"
            fi
        fi
        check_haxelib ./haxelib
        check_haxe_uses_own_haxelib
        check_no_global_module_path
        # Every binary only links system libraries and libneko, and only has
        # rpaths relative to itself.
        before="$failures"
        for f in "$dir/haxe" "$dir/haxelib" "$nekodir"/*; do
            [ -f "$f" ] && [ ! -L "$f" ] && file "$f" | grep -q Mach-O || continue
            bad="$(otool -L "$f" | grep -v ':$' | awk '{print $1}' | grep -v -E '^(/usr/lib/libSystem\.B\.dylib|/usr/lib/libresolv\.9\.dylib|/usr/lib/libc\+\+\.1\.dylib|/usr/lib/libz\.1\.dylib|@rpath/libneko\.2\.dylib|/System/Library/Frameworks/)' || true)"
            [ -z "$bad" ] || fail "$(basename "$f") links: $bad"
            bad="$(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}' | grep -v -E '^@(executable|loader)_path(/|$)' || true)"
            [ -z "$bad" ] || fail "$(basename "$f") has rpaths outside its folder: $(echo $bad)"
        done
        [ "$failures" = "$before" ] && ok "all binaries link only system libraries and libneko, with relative rpaths only"
        ;;

    linux)
        file "$dir/haxe" | grep -q -E 'statically linked|static-pie linked' && ok "haxe is statically linked" || fail "haxe is not static: $(file "$dir/haxe")"
        if command -v readelf >/dev/null; then
            needed="$(readelf -d "$dir/haxe" 2>/dev/null | grep NEEDED || true)"
            [ -z "$needed" ] && ok "haxe has no NEEDED entries" || fail "haxe NEEDED: $needed"
            runpath="$(readelf -d "$dir/haxelib" | awk '/RUNPATH|RPATH/{print $NF}')"
            [ "$runpath" = "[\$ORIGIN/$nekorel]" ] && ok "haxelib runpath is \$ORIGIN/$nekorel" || fail "haxelib runpath: $runpath"
        fi
        if command -v objdump >/dev/null; then
            glibc="$(objdump -T "$dir/haxelib" | grep -o 'GLIBC_[0-9.]*' | sort -t. -k2,2n -k3,3n -u | tail -1)"
            ok "haxelib requires $glibc at most"
        fi
        check_version "$(run_clean "$dir/haxe" --version 2>&1)" "haxe --version"
        if ldd --version 2>&1 | grep -qi -E 'glibc|gnu libc'; then
            check_haxelib ./haxelib
            glibc="$(for f in "$dir/haxelib" "$nekodir"/*; do [ -f "$f" ] && objdump -T "$f" 2>/dev/null; done \
                | grep -o 'GLIBC_[0-9.]*' | sort -t. -k2,2n -u | tail -1)"
            ok "haxelib and neko require $glibc at most"
            needed="$(for f in "$dir/haxelib" "$nekodir"/*; do [ -f "$f" ] && readelf -d "$f" 2>/dev/null | awk '/NEEDED/{print $NF}'; done | sort -u | tr -d '[]')"
            bad="$(echo "$needed" | grep -v -E '^(libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libneko\.so\.2|ld-linux.*)$' || true)"
            [ -z "$bad" ] && ok "haxelib and neko only need glibc and libneko" || fail "haxelib/neko need: $(echo $bad)"
            bad="$(for f in "$dir/haxelib" "$nekodir"/*; do [ -f "$f" ] && readelf -d "$f" 2>/dev/null | awk '/RUNPATH|RPATH/{print $NF}'; done \
                | tr -d '[]' | tr ':' '\n' | grep -v -E '^\$ORIGIN(/|$)' | sort -u || true)"
            [ -z "$bad" ] && ok "haxelib and neko only have \$ORIGIN-relative runpaths" || fail "runpaths outside the folder: $(echo $bad)"
            check_no_global_module_path
            check_haxe_uses_own_haxelib
        else
            echo "  skip  haxelib (needs glibc, host is musl)"
        fi
        ;;

    windows)
        # The objdump found on Windows runners can be a native one (mingw):
        # give it a Windows path.
        dlls="$(objdump -p "$(cygpath -m "$dir/haxe.exe")" | awk '/DLL Name/{print tolower($3)}' | sort -u)"
        bad="$(echo "$dlls" | grep -v -E '^(kernel32|msvcrt|ucrtbase|api-ms-win-.*|advapi32|ws2_32|crypt32|bcrypt|user32|shell32|ole32|oleaut32|secur32|iphlpapi|userenv|psapi|dbghelp|ntdll|shlwapi|version)\.dll$' || true)"
        [ -z "$bad" ] && ok "haxe.exe uses only system DLLs: $(echo $dlls)" || fail "haxe.exe depends on: $bad"
        check_version "$("$dir/haxe.exe" --version 2>&1 | tr -d '\r')" "haxe.exe --version"
        check_haxelib ./haxelib.exe
        ;;
esac

# Build environment: only project-local prefixes for headers and libraries.
env_targets="$target"
[ "$target" = "mac-universal" ] && env_targets="mac-arm64 mac-x86_64"
for t in $env_targets; do
    envfile="$ROOT/build/$HAXE_PROFILE/$t/build_env.txt"
    [ -f "$envfile" ] || continue
    if grep -E '^(C_INCLUDE_PATH|LIBRARY_PATH|PKG_CONFIG_LIBDIR)=' "$envfile" | grep -q -E '/opt/homebrew|/usr/local|\.opam/'; then
        fail "build environment of $t points outside the project: $envfile"
    else
        ok "build environment of $t limited to project prefixes"
    fi
done

if [ "$failures" -gt 0 ]; then
    die "$failures check(s) failed for $folder"
fi
log "all checks passed for $target ($layout layout)"
