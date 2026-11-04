#!/usr/bin/env bash
# Check the C# compiler of the cs target (4.3 only).
# Usage: scripts/test/tool-mono.sh <target>
# There is no portable mono archive for every platform, so this one is not
# installed from a pinned file: the Linux test image has mono (Ubuntu
# packages), macOS needs `brew bundle --file=Brewfile.tests`, and Windows uses
# the csc of the .NET Framework (present on the GitHub runners).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"
load_profile
source "$ROOT/scripts/test/common-test.sh"

target="${1:?usage: tool-mono.sh <target>}"
case "$(test_platform "$target")" in
    WINDOWS_*)
        csc="$(ls "$(cygpath -u 'C:\Windows')"/Microsoft.NET/Framework64/v4*/csc.exe 2>/dev/null | tail -1 || true)"
        [ -n "$csc" ] || die "csc.exe of the .NET Framework not found"
        echo "path:$(dirname "$csc")"
        ;;
    *)
        command -v mono >/dev/null && command -v mcs >/dev/null \
            || die "mono is needed by the cs target: on macOS run brew bundle --file=$ROOT/Brewfile.tests (the Linux test image has it)"
        mono --version | head -1 >&2
        ;;
esac
