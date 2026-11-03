#!/usr/bin/env bash
# Run the Haxe test suite (tests/RunCi.hxml) with a built folder.
# Usage: ./test-haxe.sh <target> [test targets]   (default: DEFAULT_TEST_TARGETS of the profile)
#   target: mac-universal, mac-arm64, mac-x86_64, linux-x64, linux-arm64, windows-x64
#   test targets: comma separated RunCi targets (macro, neko, js, hl, cpp,
#   jvm, python, php, lua...). Anything beyond macro and neko needs that
#   target's own toolchain on the machine.
#
# Uses the same environment as the build scripts (HAXE_SRC_DIR,
# HAXE_PROFILE_DIR, BUILD_HAXE_CACHE_DIR...), and checks that the sources are
# the ones the build was made from.
# Linux targets run inside the test image (docker/linux-test.Dockerfile).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/entry.sh"

target="${1:?usage: test-haxe.sh <target> [test targets]}"
check_target "$target"
os="$(target_os "$target")"

if ! in_container && [ -n "${HAXE_SRC_DIR:-}" ]; then
    prepare_sources
fi
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
load_source_info
tests="${2:-$DEFAULT_TEST_TARGETS}"

build_id="$(stage_build_id "$target")"
[ "$build_id" = "$BUILD_ID" ] || die "the sources are at $BUILD_ID, the build of $target was made from $build_id"
out="$(layout_folder "$target" standard)/haxe"
[ -d "$out" ] || die "$out not found"

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
    mounts=(-v "$ROOT:/workspace")
    run_env=(-e HAXE_PROFILE="$HAXE_PROFILE")
    if [ -n "${BUILD_HAXE_CACHE_DIR:-}" ]; then
        mounts+=(-v "$BUILD_HAXE_CACHE_DIR:/cache")
        run_env+=(-e BUILD_HAXE_CACHE_DIR=/cache)
    fi
    if [ -n "${BUILD_HAXE_SOURCE:-}" ]; then
        run_env+=(-e BUILD_HAXE_SOURCE="/workspace/${BUILD_HAXE_SOURCE#"$ROOT"/}")
    fi
    if [ -n "${HAXE_PROFILE_DIR:-}" ]; then
        mounts+=(-v "$HAXE_PROFILE_DIR:/build-haxe-profile:ro")
        run_env+=(-e HAXE_PROFILE_DIR=/build-haxe-profile)
    fi
    exec docker run --rm --platform "$platform" "${mounts[@]}" "${run_env[@]}" -w /workspace \
        "build-haxe-test:$arch_arg" ./test-haxe.sh "$target" "$tests"
fi

# RunCi writes into $HOME/haxe-ci (tests/runci/System.hx) and installs
# haxelib libraries: keep both in the cache.
home="$CACHE_DIR/home/$HAXE_PROFILE-$target"
mkdir -p "$home" "$CACHE_DIR/haxelib/$HAXE_PROFILE-$target"
export HOME="$home"
[ "$os" = "windows" ] && export USERPROFILE="$(cygpath -w "$home")"
export HAXELIB_PATH="$CACHE_DIR/haxelib/$HAXE_PROFILE-$target"
export HAXE_STD_PATH="$out/std"
if [ "$os" = "windows" ]; then
    export PATH="$out:$PATH"
else
    export PATH="$out:$out/neko:$PATH"
    export NEKOPATH="$out/neko"
fi
unset DYLD_LIBRARY_PATH LD_LIBRARY_PATH

# Tests write into the source tree (compiled outputs, local haxelib repos)
# and some of them cannot run twice. Run them in a fresh copy of the source
# files (the files of the clone tracked by git, or the files copied from
# HAXE_SRC_DIR), never in the sources themselves.
if in_container; then
    work="$(mktemp -d /tmp/haxe-tests.XXXXXX)"
else
    mkdir -p "$ROOT/build/test-work"
    work="$(mktemp -d "$ROOT/build/test-work/$HAXE_PROFILE-$target.XXXXXX")"
fi
log "copying the sources to $work"
if sources_are_clone && git -C "$HAXE_DIR" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$HAXE_DIR" ls-files -z --recurse-submodules \
        | tar -C "$HAXE_DIR" --null -T - -cf - | tar -C "$work" -xf -
else
    [ -f "$HAXE_DIR.files" ] || die "$HAXE_DIR.files missing (made by scripts/prepare-source.sh)"
    tar -C "$HAXE_DIR" --null -T "$HAXE_DIR.files" -cf - | tar -C "$work" -xf -
fi

# Some file names in tests/sys/compile-fs.hxml are not valid on APFS.
if [ "$os" = "mac" ] && [ -f "$work/tests/sys/compile-fs.hxml" ]; then
    : > "$work/tests/sys/compile-fs.hxml"
fi

# Some tests (TestDate) assume UTC, as on the official CI.
export TZ=UTC

log "haxe: $(haxe --version), haxelib: $(haxelib version 2>/dev/null || echo '?')"
cd "$work/tests"
# One RunCi run per test target. RunCi starts an echo server (nekotools
# server on port 20200) for every target and never stops it, so chaining
# targets in one run leaves the next target talking to the previous server.
IFS=',' read -r -a test_list <<< "$tests"
for t in "${test_list[@]}"; do
    log "running RunCi ($t) for $HAXE_PROFILE/$target"
    TEST="$t" haxe RunCi.hxml
done
log "tests passed: $tests"
