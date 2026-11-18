#!/usr/bin/env bash
# Check the .NET SDK used by the new C# target (4.3 sources with
# src/generators/cs), which builds and runs the generated C# with dotnet, also
# with NativeAOT.
# Usage: scripts/test/tool-dotnet.sh <target>
# Like mono, it is not installed from a pinned file: the Linux test image has
# it (Ubuntu packages, with clang for NativeAOT), macOS needs
# `brew bundle --file=Brewfile.tests`, and the GitHub Windows runners have it.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-dotnet.sh <target>}"
dotnet="$(command -v dotnet || true)"
if [ -z "$dotnet" ] && [ "$HOST_OS" = "mac" ]; then
    # dotnet@8 is keg-only in Homebrew
    for d in /opt/homebrew/opt/dotnet@8/bin /usr/local/opt/dotnet@8/bin; do
        [ -x "$d/dotnet" ] && dotnet="$d/dotnet" && break
    done
fi
[ -n "$dotnet" ] || die "the .NET SDK is needed by the cs target: on macOS run brew bundle --file=$ROOT/Brewfile.tests (the Linux test image has it)"
"$dotnet" --version >&2
echo "path:$(dirname "$dotnet")"
