#!/usr/bin/env bash
# Build haxe and haxelib for Linux.
# Usage: ./build-haxe-linux.sh [x64|arm64]   (default: host architecture)
#
# Runs in Docker on every host (Docker Desktop on macOS, native Docker on
# Linux and GitHub Actions) so the result is the same everywhere:
#   1. Alpine (musl): C libraries, opam switch, static haxe binary
#   2. Debian 11 (glibc 2.31): haxelib linked to the official neko release,
#      assembly, checks, archive
#   3. Smoke tests of the result in bare alpine, debian and ubuntu images
#
# Environment: HAXE_REPO, HAXE_BRANCH, HAXE_COMMIT, HAXE_PROFILE,
# SKIP_SETUP=1 (keep ./haxe as is),
# BUILD_HAXE_OPAM_CACHE=<host dir> (bind a host folder for the opam roots
# instead of a named Docker volume, used on CI to cache them).
#
# Internal: --stage core|haxelib runs one stage inside the container.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

arch_arg="${1:-}"
stage_arg=""
if [ "${2:-}" = "--stage" ]; then stage_arg="${3:?--stage needs core or haxelib}"; fi

if [ -z "$arch_arg" ]; then
    case "$HOST_ARCH" in
        x86_64) arch_arg=x64 ;;
        arm64) arch_arg=arm64 ;;
    esac
fi
case "$arch_arg" in
    x64|amd64) arch_arg=x64; docker_platform=linux/amd64 ;;
    arm64|aarch64) arch_arg=arm64; docker_platform=linux/arm64 ;;
    *) die "usage: build-haxe-linux.sh [x64|arm64]" ;;
esac
target="linux-$arch_arg"

# ---------------------------------------------------------------- in container
if [ -n "$stage_arg" ]; then
    in_container || die "--stage is meant to run inside the build containers"
    load_profile
    case "$stage_arg" in
        core)
            "$ROOT/scripts/check-host.sh" "$target"
            "$ROOT/scripts/build-deps.sh" "$target"
            "$ROOT/scripts/setup-switch.sh" "$target"
            "$ROOT/scripts/build-core.sh" "$target"
            ;;
        haxelib)
            "$ROOT/scripts/build-haxelib.sh" "$target"
            out="$("$ROOT/scripts/assemble.sh" "$target" | tail -1)"
            "$ROOT/scripts/verify-binary.sh" "$out" "$target"
            "$ROOT/scripts/package.sh" "$target"
            if [ "${CERAMIC_LAYOUT:-0}" = "1" ]; then
                "$ROOT/scripts/package.sh" "$target" --ceramic-layout
            fi
            ;;
        *) die "unknown stage '$stage_arg'" ;;
    esac
    exit 0
fi

# ---------------------------------------------------------------- on the host
"$ROOT/scripts/check-host.sh" "$target"

if [ "${SKIP_SETUP:-0}" != "1" ] || [ ! -d "$HAXE_DIR/.git" ]; then
    "$ROOT/setup-haxe.sh"
fi
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
log "profile: $HAXE_PROFILE, target: $target"

# Downloads happen on the host, into the bind-mounted .cache
"$ROOT/scripts/fetch-opam.sh" "$target"
"$ROOT/scripts/fetch-neko.sh" "$target"

# On macOS: start Docker Desktop if it isn't running, and stop it on exit.
# Only manages what we started. Same logic as loreline-writer/export-linux.sh.
DOCKER_STARTED_BY_US=0
if [ "$HOST_OS" = "mac" ] && ! docker info >/dev/null 2>&1; then
    [ -d /Applications/Docker.app ] || die "Docker Desktop is not installed in /Applications"
    # If a previous run quit Docker Desktop and its VM is still shutting
    # down, `open -a Docker` no-ops and we hang. Wait for it first.
    if pgrep -x Docker >/dev/null 2>&1; then
        echo -n "Waiting for previous Docker session to finish shutting down"
        for _ in $(seq 1 60); do
            if ! pgrep -x Docker >/dev/null 2>&1; then break; fi
            echo -n "."
            sleep 1
        done
        echo
    fi
    log "starting Docker Desktop"
    open -a Docker
    echo -n "Waiting for Docker daemon"
    for _ in $(seq 1 90); do
        if docker info >/dev/null 2>&1; then
            DOCKER_STARTED_BY_US=1
            echo " ready."
            break
        fi
        echo -n "."
        sleep 1
    done
    if [ "$DOCKER_STARTED_BY_US" = "0" ]; then
        echo >&2
        die "Docker daemon did not become ready within 90s"
    fi
fi

cleanup_docker() {
    if [ "$DOCKER_STARTED_BY_US" != "1" ] || [ "${KEEP_DOCKER_RUNNING:-0}" = "1" ]; then return; fi
    echo
    log "stopping Docker Desktop (started by this script)"
    if ! docker desktop stop >/dev/null 2>&1; then
        osascript -e 'quit app "Docker"' >/dev/null 2>&1 || true
        sleep 2
        if pgrep -x Docker >/dev/null 2>&1; then
            pkill -x Docker >/dev/null 2>&1 || true
        fi
    fi
    echo -n "Waiting for Docker to shut down"
    for _ in $(seq 1 60); do
        if ! pgrep -x Docker >/dev/null 2>&1; then
            echo " done."
            return
        fi
        echo -n "."
        sleep 1
    done
    echo " (timed out, Docker may still be running)"
}
trap cleanup_docker EXIT

docker info >/dev/null 2>&1 || die "Docker daemon is not running. Start Docker and re-run."

if [ "$HOST_OS" = "mac" ] && [ "$docker_platform" = "linux/amd64" ]; then
    got="$(docker run --rm --platform linux/amd64 "$ALPINE_IMAGE" uname -m 2>/dev/null || true)"
    [ "$got" = "x86_64" ] || die "Docker cannot run linux/amd64 containers (got '$got'). Enable 'Use Rosetta for x86_64/amd64 emulation' in Docker Desktop settings."
fi

glibc_image_var="GLIBC_IMAGE_$arch_arg"; glibc_image="${!glibc_image_var}"
glibc_snapshot_var="GLIBC_SNAPSHOT_$arch_arg"; glibc_snapshot="${!glibc_snapshot_var}"
alpine_tag="build-haxe-alpine:$arch_arg"
glibc_tag="build-haxe-glibc:$arch_arg"
log "building images"
docker build --platform "$docker_platform" --build-arg ALPINE_IMAGE="$ALPINE_IMAGE" \
    -t "$alpine_tag" -f "$ROOT/docker/linux.Dockerfile" "$ROOT/docker"
docker build --platform "$docker_platform" --build-arg BASE_IMAGE="$glibc_image" --build-arg DEBIAN_SNAPSHOT="$glibc_snapshot" \
    -t "$glibc_tag" -f "$ROOT/docker/linux-glibc.Dockerfile" "$ROOT/docker"

# opam roots: a named volume per arch (bind mounts from macOS are slow for
# the many small files opam creates), or a host folder on CI.
if [ -n "${BUILD_HAXE_OPAM_CACHE:-}" ]; then
    mkdir -p "$BUILD_HAXE_OPAM_CACHE"
    opam_mount=(-v "$BUILD_HAXE_OPAM_CACHE:/opamroot")
else
    opam_mount=(-v "build-haxe-opam-$arch_arg:/opamroot")
fi

run_env=(-e HAXE_PROFILE="$HAXE_PROFILE" -e BUILD_HAXE_OPAMROOT_BASE=/opamroot -e JOBS="$JOBS"
    -e CERAMIC_LAYOUT="${CERAMIC_LAYOUT:-0}")

log "stage 1: static haxe (Alpine, $docker_platform)"
docker run --rm --platform "$docker_platform" -v "$ROOT:/workspace" "${opam_mount[@]}" \
    "${run_env[@]}" -e BUILD_HAXE_COPY_SOURCES=1 -w /workspace "$alpine_tag" ./build-haxe-linux.sh "$arch_arg" --stage core

log "stage 2: haxelib, assembly and checks ($glibc_image, $docker_platform)"
docker run --rm --platform "$docker_platform" -v "$ROOT:/workspace" \
    "${run_env[@]}" -w /workspace "$glibc_tag" ./build-haxe-linux.sh "$arch_arg" --stage haxelib

short="$(cut -c1-10 "$(stage_dir "$target")/commit.txt")"
out_rel="build/$HAXE_PROFILE/$target/$short/haxe"

log "stage 3: smoke tests in bare images"
# haxe is static: it must run everywhere. haxelib needs the glibc of its build
# image or newer.
if [ "$arch_arg" = "x64" ]; then
    haxelib_images="$glibc_image ubuntu:20.04 ubuntu:22.04 ubuntu:24.04"
else
    haxelib_images="$glibc_image ubuntu:24.04 debian:bookworm-slim"
fi
for image in "$ALPINE_IMAGE" "$GLIBC_IMAGE_x64" ubuntu:20.04 ubuntu:24.04 $haxelib_images; do
    docker pull -q --platform "$docker_platform" "$image" >/dev/null
done
for image in "$ALPINE_IMAGE" "$GLIBC_IMAGE_x64" ubuntu:20.04 ubuntu:24.04; do
    v="$(docker run --rm --platform "$docker_platform" -v "$ROOT/$out_rel:/haxe:ro" "$image" /haxe/haxe --version 2>&1 || true)"
    case "$v" in
        [0-9]*) log "  haxe --version in $image: $v" ;;
        *) die "haxe does not run in $image: $v" ;;
    esac
done
for image in $haxelib_images; do
    v="$(docker run --rm --platform "$docker_platform" -v "$ROOT/$out_rel:/haxe:ro" -e HOME=/tmp "$image" /haxe/haxelib version 2>&1 || true)"
    case "$v" in
        [0-9]*) log "  haxelib version in $image: $v" ;;
        *) die "haxelib does not run in $image: $v" ;;
    esac
done

echo
echo "Linux $arch_arg build complete. Available in:"
echo "  - $ROOT/$out_rel"
echo "  - $ROOT/build/archives/haxe-$HAXE_PROFILE-$short-$target.tar.gz"
