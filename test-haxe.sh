#!/usr/bin/env bash
# Run the Haxe test suite (tests/RunCi.hxml) with a built folder.
# Usage: ./test-haxe.sh <target> [test targets]   (default: DEFAULT_TEST_TARGETS of the profile)
#   target: mac-universal, mac-arm64, mac-x86_64, linux-x64, linux-arm64, windows-x64
#   test targets: comma separated RunCi targets (macro, neko, js, hl, cpp,
#   jvm, python, php, lua...). Anything beyond macro and neko needs that
#   target's own toolchain on the machine.
#
# Linux targets run inside the test image (docker/linux-test.Dockerfile).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

target="${1:?usage: test-haxe.sh <target> [test targets]}"
check_target "$target"
os="$(target_os "$target")"

HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
tests="${2:-$DEFAULT_TEST_TARGETS}"

short="$(cut -c1-10 "$(stage_dir "$target")/commit.txt" 2>/dev/null)" || die "no build for $target (run the build script first)"
out="$ROOT/build/$HAXE_PROFILE/$target/$short/haxe"
[ -d "$out" ] || die "$out not found"
[ "$(git -C "$HAXE_DIR" rev-parse --short=10 HEAD)" = "$short" ] || die "haxe/ is not at the tested commit $short"

if [ "$os" = "linux" ] && ! in_container; then
    case "$target" in
        linux-x64) platform=linux/amd64; arch_arg=x64 ;;
        linux-arm64) platform=linux/arm64; arch_arg=arm64 ;;
    esac
    docker info >/dev/null 2>&1 || die "Docker is not running"
    docker build -q --platform "$platform" --build-arg BASE_IMAGE="$GLIBC_IMAGE" --build-arg DEBIAN_SNAPSHOT="$GLIBC_SNAPSHOT" \
        -t "build-haxe-glibc:$arch_arg" -f "$ROOT/docker/linux-glibc.Dockerfile" "$ROOT/docker" >/dev/null
    docker build -q --platform "$platform" --build-arg GLIBC_TAG="build-haxe-glibc:$arch_arg" \
        -t "build-haxe-test:$arch_arg" -f "$ROOT/docker/linux-test.Dockerfile" "$ROOT/docker" >/dev/null
    exec docker run --rm --platform "$platform" -v "$ROOT:/workspace" -w /workspace \
        "build-haxe-test:$arch_arg" ./test-haxe.sh "$target" "$tests"
fi

# RunCi writes into $HOME/haxe-ci (tests/runci/System.hx) and installs
# haxelib libraries: keep both inside the project.
home="$ROOT/.cache/home/$HAXE_PROFILE-$target"
mkdir -p "$home" "$ROOT/.cache/haxelib/$HAXE_PROFILE-$target"
export HOME="$home"
[ "$os" = "windows" ] && export USERPROFILE="$(cygpath -w "$home")"
export HAXELIB_PATH="$ROOT/.cache/haxelib/$HAXE_PROFILE-$target"
export HAXE_STD_PATH="$out/std"
if [ "$os" = "windows" ]; then
    export PATH="$out:$PATH"
else
    export PATH="$out:$out/neko:$PATH"
    export NEKOPATH="$out/neko"
fi
unset DYLD_LIBRARY_PATH LD_LIBRARY_PATH

# Tests write into the source tree (compiled outputs, local haxelib repos)
# and some of them cannot run twice. Run them in a fresh copy of the tracked
# files of the clone.
if in_container; then
    work="$(mktemp -d /tmp/haxe-tests.XXXXXX)"
else
    mkdir -p "$ROOT/build/test-work"
    work="$(mktemp -d "$ROOT/build/test-work/$HAXE_PROFILE-$target.XXXXXX")"
fi
log "copying tracked sources to $work"
git -C "$HAXE_DIR" ls-files -z --recurse-submodules \
    | tar -C "$HAXE_DIR" --null -T - -cf - | tar -C "$work" -xf -

# Some file names in tests/sys/compile-fs.hxml are not valid on APFS.
if [ "$os" = "mac" ] && [ -f "$work/tests/sys/compile-fs.hxml" ]; then
    : > "$work/tests/sys/compile-fs.hxml"
fi

log "haxe: $(haxe --version), haxelib: $(haxelib version 2>/dev/null || echo '?')"
log "running RunCi ($tests) for $HAXE_PROFILE/$target"
cd "$work/tests"
TEST="$tests" haxe RunCi.hxml
log "tests passed: $tests"
