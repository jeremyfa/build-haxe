#!/usr/bin/env bash
# Portability checks on an assembled folder.
# Usage: scripts/verify-binary.sh <assembled haxe folder> <target>
# Exits non-zero on the first failed check.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

dir="${1:?usage: verify-binary.sh <folder> <target>}"
target="${2:?usage: verify-binary.sh <folder> <target>}"
check_target "$target"
load_profile

os="$(target_os "$target")"
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
    case "$HAXE_PROFILE" in
        haxe43) echo "4.3." ;;
        haxe5) echo "5." ;;
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

echo "verifying $dir ($target)"

case "$os" in
    mac)
        libs="$(otool -L "$dir/haxe" | grep -v ':$' | awk '{print $1}' | sort -u)"
        bad="$(echo "$libs" | grep -v -E '^(/usr/lib/libSystem\.B\.dylib|/usr/lib/libresolv\.9\.dylib|/usr/lib/libc\+\+\.1\.dylib|/System/Library/Frameworks/)' || true)"
        [ -z "$bad" ] && ok "haxe links only system libraries" || fail "haxe links non-system libraries: $bad"

        libs="$(otool -L "$dir/haxelib" | grep -v ':$' | awk '{print $1}' | sort -u)"
        bad="$(echo "$libs" | grep -v -E '^(/usr/lib/libSystem\.B\.dylib|@rpath/libneko\.2\.dylib)$' || true)"
        [ -z "$bad" ] && ok "haxelib links only libSystem and libneko" || fail "haxelib links: $bad"
        rpaths="$(otool -l "$dir/haxelib" | awk '/LC_RPATH/{getline; getline; print $2}' | sort -u)"
        [ "$rpaths" = "@executable_path/neko" ] && ok "haxelib rpath is @executable_path/neko" || fail "haxelib rpaths: $rpaths"

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
        out="$(cd "$dir" && run_clean ./haxelib version 2>&1 || true)"
        [ -n "$out" ] && ! echo "$out" | grep -qi -E 'error|failed|not found|uncaught' && ok "haxelib version: $out" || fail "haxelib version: $out"
        ;;

    linux)
        file "$dir/haxe" | grep -q -E 'statically linked|static-pie linked' && ok "haxe is statically linked" || fail "haxe is not static: $(file "$dir/haxe")"
        if command -v readelf >/dev/null; then
            needed="$(readelf -d "$dir/haxe" 2>/dev/null | grep NEEDED || true)"
            [ -z "$needed" ] && ok "haxe has no NEEDED entries" || fail "haxe NEEDED: $needed"
            runpath="$(readelf -d "$dir/haxelib" | awk '/RUNPATH|RPATH/{print $NF}')"
            [ "$runpath" = "[\$ORIGIN/neko]" ] && ok "haxelib runpath is \$ORIGIN/neko" || fail "haxelib runpath: $runpath"
        fi
        if command -v objdump >/dev/null; then
            glibc="$(objdump -T "$dir/haxelib" | grep -o 'GLIBC_[0-9.]*' | sort -t. -k2,2n -k3,3n -u | tail -1)"
            ok "haxelib requires $glibc at most"
        fi
        check_version "$(run_clean "$dir/haxe" --version 2>&1)" "haxe --version"
        if ldd --version 2>&1 | grep -qi -E 'glibc|gnu libc'; then
            out="$(cd "$dir" && run_clean ./haxelib version 2>&1 || true)"
            [ -n "$out" ] && ! echo "$out" | grep -qi -E 'error|failed|not found|uncaught' && ok "haxelib version: $out" || fail "haxelib version: $out"
        else
            echo "  skip  haxelib version (needs glibc, host is musl)"
        fi
        ;;

    windows)
        dlls="$(objdump -p "$dir/haxe.exe" | awk '/DLL Name/{print tolower($3)}' | sort -u)"
        bad="$(echo "$dlls" | grep -v -E '^(kernel32|msvcrt|ucrtbase|api-ms-win-.*|advapi32|ws2_32|crypt32|bcrypt|user32|shell32|ole32|oleaut32|secur32|iphlpapi|userenv|psapi|dbghelp|ntdll|shlwapi|version)\.dll$' || true)"
        [ -z "$bad" ] && ok "haxe.exe uses only system DLLs: $(echo $dlls)" || fail "haxe.exe depends on: $bad"
        check_version "$("$dir/haxe.exe" --version 2>&1 | tr -d '\r')" "haxe.exe --version"
        out="$(cd "$dir" && ./haxelib.exe version 2>&1 | tr -d '\r' || true)"
        [ -n "$out" ] && ! echo "$out" | grep -qi -E 'error|failed|not found|uncaught' && ok "haxelib version: $out" || fail "haxelib version: $out"
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
    die "$failures check(s) failed for $dir"
fi
log "all checks passed for $target"
