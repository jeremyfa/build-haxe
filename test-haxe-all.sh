#!/usr/bin/env bash
# Run the full test suite on every platform a Mac can test: macOS universal,
# Linux arm64 and Linux x64 (Docker). Windows is tested on GitHub Actions.
# Usage: ./test-haxe-all.sh [default|all|<test targets>]   (default: all)
# Same environment variables as test-haxe.sh. Every platform is tested even
# when another one fails; the exit code is non-zero if any failed.

main() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/scripts/common.sh"
    [ "$HOST_OS" = "mac" ] || die "test-haxe-all.sh runs on macOS"
    selection="${1:-all}"

    if ! docker info >/dev/null 2>&1; then
        [ -d /Applications/Docker.app ] || die "Docker Desktop is needed for the Linux tests"
        log "starting Docker Desktop"
        open -a Docker
        for _ in $(seq 1 90); do
            docker info >/dev/null 2>&1 && break
            sleep 1
        done
        docker info >/dev/null 2>&1 || die "Docker daemon did not become ready within 90s"
    fi

    failed=""
    for t in mac-universal linux-arm64 linux-x64; do
        log "=== $t"
        if ! "$ROOT/test-haxe.sh" "$t" "$selection"; then
            failed="$failed $t"
        fi
    done

    echo
    if [ -n "$failed" ]; then
        die "tests failed on:$failed (see build/test-results/)"
    fi
    log "all platforms passed"
}

main "$@"
