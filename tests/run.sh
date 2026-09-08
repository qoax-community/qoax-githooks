#!/usr/bin/env bash
#
# Every check for .githooks/commit-msg. Run it from anywhere:
#
#   tests/commit-msg/run.sh              # against the tracked hook
#   tests/commit-msg/run.sh path/to/hook # against another copy
#
# Each suite prints its cases and ends with "failures: N"; this sums them and
# exits non-zero if any suite failed.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
hook="${1:-$here/../commit-msg}"

if [ ! -x "$hook" ]; then
  printf 'not executable: %s\n' "$hook" >&2
  exit 1
fi

total=0
for suite in cases negatives scissors fuzz; do
  printf '\n=== %s ===\n' "$suite"
  output="$(bash "$here/$suite.sh" "$hook")" || true
  printf '%s\n' "$output"
  count="$(printf '%s\n' "$output" | sed -n 's/^failures: //p' | tail -1)"
  # fuzz.sh reports "fuzz clean=1 (N runs)" instead of a failure count.
  [ -z "$count" ] && case "$output" in
    *'clean=1'*) count=0 ;;
    *) count=1 ;;
  esac
  total=$((total + count))
done

printf '\n'
if [ "$total" -eq 0 ]; then
  printf 'all commit-msg suites passed\n'
  exit 0
fi
printf '%s failing case(s)\n' "$total" >&2
exit 1
