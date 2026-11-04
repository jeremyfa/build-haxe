#!/usr/bin/env bash
# List the test jobs of a profile, one "<platform> <test target>" line each.
# Usage: scripts/test/test-matrix.sh <profile> <default|all>
# Platforms: mac-universal, linux-x64, linux-arm64, windows-x64. Uses the
# same lists as test-haxe.sh (DEFAULT_TEST_TARGETS, FULL_TEST_TARGETS and
# the TEST_SKIP_* of the profile), so the CI matrix follows the profiles.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

HAXE_PROFILE="${1:?usage: test-matrix.sh <profile> <default|all>}"
selection="${2:-default}"
export HAXE_PROFILE
load_profile
source "$ROOT/scripts/test/common-test.sh"

for platform in mac-universal linux-x64 linux-arm64 windows-x64; do
    os="$(target_os "$platform")"
    case "$platform" in
        mac-*) key=MAC_ARM64 ;;   # the macOS runners are arm64
        *) key="$(test_platform "$platform")" ;;
    esac
    skip_var="TEST_SKIP_$key"
    os_skip_var="TEST_SKIP_$(echo "$os" | tr '[:lower:]' '[:upper:]')"
    case "$selection" in
        all) list="${FULL_TEST_TARGETS:-$DEFAULT_TEST_TARGETS}" ;;
        *) list="$DEFAULT_TEST_TARGETS" ;;
    esac
    for t in $(echo "$list" | tr ',' ' '); do
        if [ "$selection" = all ] && in_list "$t" "${!skip_var:-} ${!os_skip_var:-}"; then continue; fi
        echo "$platform $t"
    done
done
