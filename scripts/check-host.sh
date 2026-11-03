#!/usr/bin/env bash
# Check that the host has what a target needs. Fails with a clear message.
# Usage: scripts/check-host.sh <target>

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: check-host.sh <target>}"
check_target "$target"
problems=0
problem() { echo "  - $*" >&2; problems=$((problems + 1)); }

version_ge() {
    # version_ge <have> <want>
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$2" ]
}

case "$(target_os "$target")" in
    mac)
        [ "$HOST_OS" = "mac" ] || die "$target must be built on macOS"
        xcode-select -p >/dev/null 2>&1 || problem "Xcode Command Line Tools missing: xcode-select --install"
        for tool in git curl make cc lipo codesign vtool otool install_name_tool; do
            command -v "$tool" >/dev/null || problem "$tool not found (Xcode Command Line Tools)"
        done
        if ! command -v brew >/dev/null; then
            problem "Homebrew not found, needed for host tools (https://brew.sh), then: brew bundle --file=$ROOT/Brewfile"
        fi
        if command -v cmake >/dev/null; then
            v="$(cmake --version | awk 'NR==1{print $3}')"
            version_ge "$v" 3.20 || problem "cmake $v is too old (need >= 3.20): brew upgrade cmake"
        else
            problem "cmake not found: brew bundle --file=$ROOT/Brewfile"
        fi
        command -v ninja >/dev/null || problem "ninja not found: brew bundle --file=$ROOT/Brewfile"
        command -v pkg-config >/dev/null || problem "pkg-config not found: brew bundle --file=$ROOT/Brewfile"
        case "$target" in
            mac-x86_64|mac-universal)
                if [ "$HOST_ARCH" = "arm64" ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
                    problem "Rosetta is needed for x86_64: softwareupdate --install-rosetta --agree-to-license"
                fi
                sdk="$(xcrun --show-sdk-version 2>/dev/null || echo 0)"
                if [ "${sdk%%.*}" -ge 27 ] 2>/dev/null; then
                    warn "SDK $sdk: Apple tools may no longer be universal from version 27, x86_64 builds under Rosetta can break"
                fi
                ;;
        esac
        ;;
    linux)
        if in_container; then
            for tool in git curl make gcc cmake ninja pkg-config; do
                command -v "$tool" >/dev/null || problem "$tool missing in the build image"
            done
        else
            command -v docker >/dev/null || problem "docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
            if [ "$HOST_OS" = "mac" ] && [ ! -d /Applications/Docker.app ]; then
                problem "Docker Desktop is not installed in /Applications"
            fi
        fi
        ;;
    windows)
        [ "$HOST_OS" = "windows" ] || die "$target is built on Windows (GitHub Actions or a Windows machine with opam)"
        for tool in opam make x86_64-w64-mingw32-gcc cygpath; do
            command -v "$tool" >/dev/null || problem "$tool not found (run inside the opam/Cygwin environment)"
        done
        ;;
esac

[ "$problems" -eq 0 ] || die "host check failed for $target"
log "host ready for $target"
