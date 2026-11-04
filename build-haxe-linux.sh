#!/usr/bin/env bash
# Build haxe and haxelib for Linux.
# Usage: ./build-haxe-linux.sh [x64|arm64] [--ceramic-layout]   (default: host architecture)
#
# Runs in Docker on every host (Docker Desktop on macOS, native Docker on
# Linux and GitHub Actions) so the result is the same everywhere:
#   0. Debian 11 (glibc 2.31): neko built from source, static dependencies
#   1. Alpine (musl): C libraries, opam switch, static haxe binary
#   2. Debian 11: haxelib linked to that neko, assembly, checks, archives
#   3. Smoke tests of the result in bare alpine, debian and ubuntu images
# Then the result is copied to HAXE_OUT_DIR, if set (on the host).
#
# Environment: HAXE_SRC_DIR or HAXE_REPO / HAXE_BRANCH / HAXE_COMMIT,
# HAXE_PROFILE, HAXE_PROFILE_DIR, HAXE_OUT_DIR, HAXE_LAYOUT,
# BUILD_HAXE_CACHE_DIR, SKIP_SETUP=1 (keep ./haxe as is). See README.md.
# Mounts: build-haxe on /workspace (it holds the copy of HAXE_SRC_DIR),
# BUILD_HAXE_CACHE_DIR on /cache, HAXE_PROFILE_DIR read-only on
# /build-haxe-profile. The opam roots go to the cache on a Linux host, and to
# a Docker volume per arch on macOS (or without BUILD_HAXE_CACHE_DIR).
#
# Internal: --stage neko|core|haxelib runs one stage inside the container.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/entry.sh"

parse_entry_args "$@"
arch_arg=""
stage_arg=""
set -- "${ENTRY_ARGS[@]+"${ENTRY_ARGS[@]}"}"
while [ $# -gt 0 ]; do
    case "$1" in
        --stage) stage_arg="${2:?--stage needs neko, core or haxelib}"; shift ;;
        x64|amd64|arm64|aarch64) arch_arg="$1" ;;
        *) die "usage: build-haxe-linux.sh [x64|arm64] [--ceramic-layout]" ;;
    esac
    shift
done

if [ -z "$arch_arg" ]; then
    case "$HOST_ARCH" in
        x86_64) arch_arg=x64 ;;
        arm64) arch_arg=arm64 ;;
    esac
fi
case "$arch_arg" in
    x64|amd64) arch_arg=x64; docker_platform=linux/amd64 ;;
    arm64|aarch64) arch_arg=arm64; docker_platform=linux/arm64 ;;
esac
target="linux-$arch_arg"

# ---------------------------------------------------------------- in container
if [ -n "$stage_arg" ]; then
    in_container || die "--stage is meant to run inside the build containers"
    load_profile
    case "$stage_arg" in
        neko)
            "$ROOT/scripts/build-neko.sh" "$target"
            ;;
        core)
            "$ROOT/scripts/check-host.sh" "$target"
            "$ROOT/scripts/build-deps.sh" "$target"
            "$ROOT/scripts/setup-switch.sh" "$target"
            "$ROOT/scripts/build-core.sh" "$target"
            ;;
        haxelib)
            "$ROOT/scripts/build-haxelib.sh" "$target"
            "$ROOT/scripts/assemble.sh" "$target"
            package_target "$target"
            ;;
        *) die "unknown stage '$stage_arg'" ;;
    esac
    exit 0
fi

# ---------------------------------------------------------------- on the host
"$ROOT/scripts/check-host.sh" "$target"
prepare_sources
HAXE_PROFILE="$("$ROOT/scripts/detect-profile.sh")"
export HAXE_PROFILE
load_profile
log "profile: $HAXE_PROFILE, target: $target, sources: $HAXE_DIR"

# Downloads happen on the host, into the mounted cache
"$ROOT/scripts/fetch-opam.sh" "$target"

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

alpine_tag="build-haxe-alpine:$arch_arg"
glibc_tag="build-haxe-glibc:$arch_arg"
# Package mirrors (snapshot.debian.org especially) have short outages: each
# image build is tried 3 times.
docker_build_retry() {
    local i
    for i in 1 2 3; do
        docker build "$@" && return 0
        [ "$i" -lt 3 ] || return 1
        warn "docker build failed, retrying in 30s ($i/3)"
        sleep 30
    done
}
log "building images"
docker_build_retry --platform "$docker_platform" --build-arg ALPINE_IMAGE="$ALPINE_IMAGE" \
    -t "$alpine_tag" -f "$ROOT/docker/linux.Dockerfile" "$ROOT/docker"
docker_build_retry --platform "$docker_platform" --build-arg BASE_IMAGE="$GLIBC_IMAGE" --build-arg DEBIAN_SNAPSHOT="$GLIBC_SNAPSHOT" \
    -t "$glibc_tag" -f "$ROOT/docker/linux-glibc.Dockerfile" "$ROOT/docker"

# Mounts and environment shared by the stages
mounts=(-v "$ROOT:/workspace")
run_env=(-e HAXE_PROFILE="$HAXE_PROFILE" -e JOBS="$JOBS" -e HAXE_LAYOUT="$LAYOUT")
if [ -n "${BUILD_HAXE_CACHE_DIR:-}" ]; then
    mounts+=(-v "$BUILD_HAXE_CACHE_DIR:/cache")
    run_env+=(-e BUILD_HAXE_CACHE_DIR=/cache)
fi
# opam roots: in the cache on a Linux host (CI), so they can be cached with
# it. On macOS they stay in a Docker volume per arch: the macOS file system is
# case-insensitive, which breaks the OCaml build, and bind mounts from macOS
# are slow for the many small files of opam.
core_opam=()
if [ -z "${BUILD_HAXE_CACHE_DIR:-}" ] || [ "$HOST_OS" = "mac" ]; then
    core_opam=(-v "build-haxe-opam-$arch_arg:/opamroot" -e BUILD_HAXE_OPAMROOT_BASE=/opamroot)
fi
if [ -n "${BUILD_HAXE_SOURCE:-}" ]; then
    case "$BUILD_HAXE_SOURCE" in
        "$ROOT"/*) run_env+=(-e BUILD_HAXE_SOURCE="/workspace/${BUILD_HAXE_SOURCE#"$ROOT"/}") ;;
        *) die "the copy of the sources must be inside $ROOT" ;;
    esac
fi
if [ -n "${HAXE_PROFILE_DIR:-}" ]; then
    mounts+=(-v "$HAXE_PROFILE_DIR:/build-haxe-profile:ro")
    run_env+=(-e HAXE_PROFILE_DIR=/build-haxe-profile)
fi

log "stage 0: neko $NEKO_NAME ($GLIBC_IMAGE, $docker_platform)"
docker run --rm --platform "$docker_platform" "${mounts[@]}" "${run_env[@]}" \
    -w /workspace "$glibc_tag" ./build-haxe-linux.sh "$arch_arg" --stage neko

log "stage 1: static haxe (Alpine, $docker_platform)"
docker run --rm --platform "$docker_platform" "${mounts[@]}" "${core_opam[@]+"${core_opam[@]}"}" "${run_env[@]}" \
    -e BUILD_HAXE_COPY_SOURCES=1 -w /workspace "$alpine_tag" ./build-haxe-linux.sh "$arch_arg" --stage core

log "stage 2: haxelib, assembly and checks ($GLIBC_IMAGE, $docker_platform)"
docker run --rm --platform "$docker_platform" "${mounts[@]}" "${run_env[@]}" \
    -w /workspace "$glibc_tag" ./build-haxe-linux.sh "$arch_arg" --stage haxelib

out_dir="$(layout_folder "$target" standard)/haxe"

log "stage 3: smoke tests in bare images"
# haxe is static: it must run everywhere. haxelib and neko need glibc 2.31 or
# newer (the glibc of the build image). haxelib is checked with commands that
# load the neko modules (setup and list), not only its version.
haxe_images="$ALPINE_IMAGE $GLIBC_IMAGE ubuntu:20.04 ubuntu:24.04"
haxelib_images="$GLIBC_IMAGE ubuntu:20.04 ubuntu:22.04 ubuntu:24.04 debian:bookworm-slim"
for image in $haxe_images $haxelib_images; do
    docker pull -q --platform "$docker_platform" "$image" >/dev/null
done
for image in $haxe_images; do
    v="$(docker run --rm --platform "$docker_platform" -v "$out_dir:/haxe:ro" "$image" /haxe/haxe --version 2>&1 || true)"
    case "$v" in
        [0-9]*) log "  haxe --version in $image: $v" ;;
        *) die "haxe does not run in $image: $v" ;;
    esac
done
for image in $haxelib_images; do
    v="$(docker run --rm --platform "$docker_platform" -v "$out_dir:/haxe:ro" -e HOME=/tmp "$image" \
        sh -c 'mkdir -p /tmp/lib && /haxe/haxelib setup /tmp/lib >/dev/null && /haxe/haxelib list >/dev/null && /haxe/haxelib version && /haxe/neko/neko -version' 2>&1 || true)"
    case "$v" in
        [0-9]*) log "  haxelib and neko in $image: $(echo $v)" ;;
        *) die "haxelib does not run in $image: $v" ;;
    esac
done

export_target "$target"
print_summary "$target"
