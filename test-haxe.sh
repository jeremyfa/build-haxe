#!/usr/bin/env bash
# Run the Haxe test suite (tests/RunCi.hxml) with a built folder.
# Usage: ./test-haxe.sh <target> [default|all|<test targets>]
#   target: mac-universal, mac-arm64, mac-x86_64, linux-x64, linux-arm64, windows-x64
#   default: DEFAULT_TEST_TARGETS of the profile (the default)
#   all: FULL_TEST_TARGETS of the profile, without the targets that the
#        profile skips on this platform (TEST_SKIP_*)
#   <test targets>: comma separated RunCi targets (macro, neko, python...)
#
# The toolchains the targets need are installed from the pinned archives of
# test-versions.env (scripts/test/setup-tools.sh), the repositories RunCi
# clones are redirected to local mirrors of pinned commits
# (scripts/test/git-mirrors.sh), and the haxelib libraries are installed
# beforehand (scripts/test/haxelibs.sh). RunCi runs once per test target, in
# a fresh copy of the sources, without GITHUB_ACTIONS (so it never installs
# anything itself). Results: build/test-results/<profile>/<target>/<build id>/
#
# Uses the same environment as the build scripts (HAXE_SRC_DIR,
# HAXE_PROFILE_DIR, BUILD_HAXE_CACHE_DIR...), and checks that the sources are
# the ones the build was made from.
# Linux targets run inside the test image (docker/linux-test.Dockerfile).

# The whole script is a function, read entirely before it runs: editing the
# file while tests run cannot change what the running script does.
main() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/scripts/common.sh"
    source "$SCRIPT_DIR/scripts/entry.sh"

    target="${1:?usage: test-haxe.sh <target> [default|all|<test targets>]}"
    selection="${2:-default}"
    check_target "$target"
    os="$(target_os "$target")"

    if ! in_container && [ -n "${HAXE_SRC_DIR:-}" ]; then
        prepare_sources
    fi
    HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
    export HAXE_PROFILE
    load_profile
    load_source_info
    source "$ROOT/scripts/test/common-test.sh"

    build_id="$(stage_build_id "$target")"
    [ "$build_id" = "$BUILD_ID" ] || die "the sources are at $BUILD_ID, the build of $target was made from $build_id"
    out="$(layout_folder "$target" standard)/haxe"
    [ -d "$out" ] || die "$out not found"

    # ---- which test targets
    platform="$(test_platform "$target")"
    case "$selection" in
        default) tests="$DEFAULT_TEST_TARGETS" ;;
        all)
            tests=""
            skip_var="TEST_SKIP_$platform"; os_skip_var="TEST_SKIP_$(echo "$os" | tr '[:lower:]' '[:upper:]')"
            for t in ${FULL_TEST_TARGETS:-$DEFAULT_TEST_TARGETS}; do
                if in_list "$t" "${!skip_var:-} ${!os_skip_var:-}"; then continue; fi
                tests="$tests${tests:+,}$t"
            done
            ;;
        *) tests="$selection" ;;
    esac
    tests="$(echo "$tests" | tr ' ' ',')"

    if [ "$os" = "linux" ] && ! in_container; then
        case "$target" in
            linux-x64) docker_platform=linux/amd64; arch_arg=x64 ;;
            linux-arm64) docker_platform=linux/arm64; arch_arg=arm64 ;;
        esac
        docker info >/dev/null 2>&1 || die "Docker is not running"
        docker build -q --platform "$docker_platform" --build-arg TEST_IMAGE="$TEST_IMAGE" \
            -t "build-haxe-test:$arch_arg" -f "$ROOT/docker/linux-test.Dockerfile" "$ROOT/docker" >/dev/null
        mounts=(-v "$ROOT:/workspace")
        run_env=(-e HAXE_PROFILE="$HAXE_PROFILE" -e JOBS="$JOBS")
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
        for v in $(compgen -A variable | grep -E '^(NEKO_|TEST_GIT_|TEST_FILE_|BUILD_HAXE_MIRROR)'); do
            run_env+=(-e "$v=${!v}")
        done
        exec docker run --rm --platform "$docker_platform" "${mounts[@]}" "${run_env[@]}" -w /workspace \
            "build-haxe-test:$arch_arg" ./test-haxe.sh "$target" "$tests"
    fi

    # ---- environment shared by every test target
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
    # Some tests (TestDate) assume UTC, as on the official CI.
    export TZ=UTC
    # hxcpp keeps compiled objects here between runs.
    export HXCPP_COMPILE_CACHE="$CACHE_DIR/hxcpp-cache/$(test_platform "$target" | tr '[:upper:]' '[:lower:]')"
    mkdir -p "$HXCPP_COMPILE_CACHE"

    envfile="$("$ROOT/scripts/test/setup-tools.sh" "$target" "$tests" | tail -1)"
    # shellcheck disable=SC1090
    source "$envfile"
    "$ROOT/scripts/test/git-mirrors.sh" "$home"
    BUILD_HAXE_TEST_TARGET="$target" "$ROOT/scripts/test/haxelibs.sh" "$tests"

    results="$(test_results_dir "$target" "$BUILD_ID")"
    mkdir -p "$results"
    {
        echo "haxe: $(haxe --version 2>&1)"
        echo "haxelib: $(haxelib version 2>&1)"
        echo "neko: $(neko -version 2>&1)"
        for tool in python3 pypy3 node; do
            command -v "$tool" >/dev/null && echo "$tool: $("$tool" --version 2>&1 | head -1)"
        done
        echo "PATH=$PATH"
    } > "$results/env.txt"
    log "testing $HAXE_PROFILE/$target ($BUILD_ID): $tests"

    # copy_sources <dir>: the files of the sources (tracked by git for the clone,
    # listed in <copy>.files for HAXE_SRC_DIR), never the sources themselves:
    # tests write into the tree and some cannot run twice.
    copy_sources() {
        if sources_are_clone && git -C "$HAXE_DIR" rev-parse HEAD >/dev/null 2>&1; then
            git -C "$HAXE_DIR" ls-files -z --recurse-submodules \
                | tar -C "$HAXE_DIR" --null -T - -cf - | tar -C "$1" -xf -
        else
            [ -f "$HAXE_DIR.files" ] || die "$HAXE_DIR.files missing (made by scripts/prepare-source.sh)"
            tar -C "$HAXE_DIR" --null -T "$HAXE_DIR.files" -cf - | tar -C "$1" -xf -
        fi
        # npm packages built beforehand (deasync, see scripts/test/tool-deasync.sh)
        if [ -n "${BUILD_HAXE_NODE_MODULES:-}" ] && [ -d "$1/tests/sys" ]; then
            cp -R "$BUILD_HAXE_NODE_MODULES" "$1/tests/sys/node_modules"
        fi
        # Some file names in tests/sys/compile-fs.hxml are not valid on APFS.
        if [ "$os" = "mac" ] && [ -f "$1/tests/sys/compile-fs.hxml" ]; then
            : > "$1/tests/sys/compile-fs.hxml"
        fi
    }

    # ---- one RunCi run per test target
    # RunCi stops at the first failing target, and starts an echo server (nekotools
    # server, port 20200) for every target without stopping it: chaining targets
    # in one run would leave a target talking to the server of the previous one.
    for t in $(echo "$tests" | tr ',' ' '); do
        if in_container; then
            work="$(mktemp -d /tmp/haxe-tests.XXXXXX)"
        else
            mkdir -p "$ROOT/build/test-work"
            work="$(mktemp -d "$ROOT/build/test-work/$HAXE_PROFILE-$target-$t.XXXXXX")"
        fi
        copy_sources "$work"
        v="TEST_ARGS_${t}_${platform}"; args="${!v:-}"
        log "running RunCi ($t) for $HAXE_PROFILE/$target in $work"
        start="$(date +%s)"
        set +e
        # With extra RunCi arguments (TEST_ARGS_*), the target goes on the
        # command line like on the official CI: arguments after RunCi.hxml
        # would go to haxe, not to RunCi.
        if [ -n "$args" ]; then
            (cd "$work/tests" && env -u GITHUB_ACTIONS haxe --run RunCi "$t" $args) 2>&1 | tee "$results/$t.log"
        else
            (cd "$work/tests" && env -u GITHUB_ACTIONS TEST="$t" haxe RunCi.hxml) 2>&1 | tee "$results/$t.log"
        fi
        code="${PIPESTATUS[0]}"
        set -e
        duration=$(( $(date +%s) - start ))
        if [ "$code" = 0 ]; then
            status=pass
        else
            v="TEST_ALLOW_FAIL_$platform"
            if in_list "$t" "${TEST_ALLOW_FAIL:-} ${!v:-}"; then status=allowed-fail; else status=fail; fi
        fi
        echo "$status $duration" > "$results/$t.status"
        log "$t: $status (${duration}s)"
    done

    "$ROOT/scripts/test/summary.sh" "$results" "$tests"
}

main "$@"
