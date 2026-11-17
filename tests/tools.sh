#!/usr/bin/env bash
#
# Every test for the scripts in scripts/. Run it from anywhere:
#
#   tests/tools.sh
#
# A POSIX script must work under dash, the /bin/sh of ubuntu-latest, and under
# bash. Thus each POSIX test runs once under each shell. The test gets that
# shell in TEST_SHELL and runs the script under test with it. A missing test
# file is a failure, so that a test that is deleted or renamed cannot pass in
# silence.
#
# Each test prints "failures: N". This sums them and exits non-zero if any
# test failed.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

bash_tests='copy.sh releases.sh'
posix_tests='templates.sh'

output="$(mktemp)"
trap 'rm -f "$output"' EXIT
total=0

# run SHELL TEST
run() {
  local shell="$1" test="$2" rc count
  printf '\n=== %s under %s ===\n' "$test" "$shell"
  # A test that did not run under a shell must not look like a pass.
  if ! command -v "$shell" >/dev/null 2>&1; then
    printf 'FAIL %s is not installed\n' "$shell"
    total=$((total + 1))
    return
  fi
  TEST_SHELL="$shell" "$shell" "$here/$test" 2>&1 | tee "$output"
  rc="${PIPESTATUS[0]}"
  count="$(sed -n 's/^failures: //p' "$output" | tail -1)"
  # A test that stops early prints no count.
  case "$count" in
    '' | *[!0-9]*) count=1 ;;
  esac
  if [ "$rc" -ne 0 ] && [ "$count" -eq 0 ]; then
    count=1
  fi
  total=$((total + count))
}

for test in $bash_tests $posix_tests; do
  if [ ! -f "$here/$test" ]; then
    printf '\n=== %s ===\nFAIL tests/%s is missing\n' "$test" "$test"
    total=$((total + 1))
    continue
  fi
  case " $bash_tests " in
    *" $test "*) shells=bash ;;
    *) shells='dash bash' ;;
  esac
  for shell in $shells; do
    run "$shell" "$test"
  done
done

printf '\n'
if [ "$total" -eq 0 ]; then
  printf 'all tool tests passed\n'
  exit 0
fi
printf '%s failing case(s)\n' "$total" >&2
exit 1
