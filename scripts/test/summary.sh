#!/usr/bin/env bash
# Summary of a test run.
# Usage: scripts/test/summary.sh <results dir> <test targets, comma separated>
# Prints a table, writes summary.md and results.json in the results folder,
# appends the table to $GITHUB_STEP_SUMMARY when set, and exits non-zero if
# a target failed without being allowed to.

set -euo pipefail

results="${1:?usage: summary.sh <results dir> <test targets>}"
tests="${2:?usage: summary.sh <results dir> <test targets>}"

failed=0
md="| target | status | duration |
|---|---|---|"
json=""
printf '\n%-10s %-13s %s\n' target status duration
for t in $(echo "$tests" | tr ',' ' '); do
    if [ -f "$results/$t.status" ]; then
        read -r status duration < "$results/$t.status"
    else
        status=missing; duration=0
    fi
    case "$status" in
        pass|allowed-fail|skip) ;;
        *) failed=$((failed + 1)) ;;
    esac
    printf '%-10s %-13s %ss\n' "$t" "$status" "$duration"
    md="$md
| $t | $status | ${duration}s |"
    json="$json${json:+,}{\"target\":\"$t\",\"status\":\"$status\",\"seconds\":$duration}"
done

echo "$md" > "$results/summary.md"
echo "[$json]" > "$results/results.json"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    { echo "### Tests: $(basename "$(dirname "$results")")"; echo "$md"; echo; } >> "$GITHUB_STEP_SUMMARY"
fi
echo "results: $results"
[ "$failed" -eq 0 ] || { echo "[build-haxe] error: $failed test target(s) failed" >&2; exit 1; }
