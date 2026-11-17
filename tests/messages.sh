#!/usr/bin/env bash
#
# Cases for the errors of scripts/check-messages.sh. In Actions, an error is
# a workflow command. The runner reads stdout and stderr as two streams, so
# the command and its text must be one line of one stream. Bash only, like
# the script. Prints "failures: N".
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
script="$root/scripts/check-messages.sh"

# mktemp -d without a template ignores TMPDIR on macOS.
T="$(mktemp -d "${TMPDIR:-/tmp}/messages.XXXXXX")" && T="$(cd "$T" && pwd -P)" || exit 1
trap 'rm -rf "$T"' EXIT

# The fixtures must not see the git configuration of the person who runs the
# tests. They must not see the Actions variables of the CI job either.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
unset GITHUB_ACTIONS GITHUB_STEP_SUMMARY EVENT_NAME BASE_SHA HEAD_SHA \
  PUSH_BEFORE PUSH_AFTER PR_TITLE PR_AUTHOR COMMIT_MSG_HOOK
mkdir -p "$HOME" "$T/no-hooks"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf 'FAIL %s\n' "$1"
  [ -n "${2-}" ] && printf '%s\n' "$2" | sed 's/^/       /'
  return 0
}

repo="$T/repo"
git init -q "$repo"
for subject in 'chore: build the fixture' 'chore: add a second commit'; do
  git -C "$repo" -c core.hooksPath="$T/no-hooks" commit -q --allow-empty -m "$subject"
done
# A depth-1 clone lacks the parent of its one commit.
git clone -q --depth 1 "file://$repo" "$T/shallow"

missing=0123456789012345678901234567890123456789

where="$repo"
# run [NAME=VALUE...] -- ARGUMENTS...: run the script in $where. Its stdout
# goes to $T/out and its stderr to $T/err, so that a case can tell the streams
# apart.
run() {
  local vars=()
  while [ "$1" != -- ]; do
    vars+=("$1")
    shift
  done
  shift
  (cd "$where" && env ${vars[@]+"${vars[@]}"} bash "$script" "$@") >"$T/out" 2>"$T/err"
  rc=$?
}
both() { printf -- '--- stdout\n%s\n--- stderr\n%s\n' "$(cat "$T/out")" "$(cat "$T/err")"; }
# lines FILE PATTERN: the count of lines in FILE that match PATTERN.
lines() { grep -c -e "$2" "$1"; }

# expect_error NAME WANT_LINE [NAME=VALUE...] -- ARGUMENTS...: the script must
# fail and print WANT_LINE to stderr as a complete line. In Actions, it must be
# the only workflow command for an error in either stream.
expect_error() {
  local name="$1" want="$2"
  shift 2
  run "$@"
  if [ "$rc" -ne 1 ]; then
    fail "$name (rc $rc, want 1)" "$(both)"
    return
  fi
  if ! grep -qxF -e "$want" "$T/err"; then
    fail "$name (no complete line on stderr: $want)" "$(both)"
    return
  fi
  case "$want" in
    ::error::*)
      if [ "$(lines "$T/err" '::error::')" -ne 1 ] || [ "$(lines "$T/out" '::error::')" -ne 0 ]; then
        fail "$name (more than one error command)" "$(both)"
        return
      fi
      ;;
    *)
      if grep -q -e '::' "$T/out" "$T/err"; then
        fail "$name (a workflow command outside Actions)" "$(both)"
        return
      fi
      ;;
  esac
  pass "$name"
}

echo '--- a range that cannot be listed ---'
expect_error 'in Actions the range error is one error line on stderr' \
  "::error::cannot enumerate $missing..HEAD — the range is not available in this checkout." \
  GITHUB_ACTIONS=true -- "$missing..HEAD"
run GITHUB_ACTIONS=true -- "$missing..HEAD"
count=$(($(lines "$T/out" '^::error::cannot enumerate') + $(lines "$T/err" '^::error::cannot enumerate')))
if [ "$count" -eq 1 ]; then
  pass 'in Actions there is exactly one cannot enumerate error line'
else
  fail "in Actions there is exactly one cannot enumerate error line ($count)" "$(both)"
fi
expect_error 'outside Actions the range error is plain text' \
  "cannot enumerate $missing..HEAD — the range is not available in this checkout." \
  -- "$missing..HEAD"
expect_error 'the error command escapes a percent sign' \
  '::error::cannot enumerate no%25such..HEAD — the range is not available in this checkout.' \
  GITHUB_ACTIONS=true -- 'no%such..HEAD'

where="$T/shallow"
expect_error 'a shallow checkout gets one error line' \
  '::error::cannot enumerate HEAD~1..HEAD — the range is not available in this checkout.' \
  GITHUB_ACTIONS=true -- 'HEAD~1..HEAD'
if grep -qxF 'The checkout is shallow: check out with fetch-depth: 0.' "$T/err"; then
  pass 'a shallow checkout names fetch-depth: 0'
else
  fail 'a shallow checkout names fetch-depth: 0' "$(both)"
fi
where="$repo"

echo '--- a hook that is not executable ---'
printf '#!/bin/sh\nexit 0\n' >"$T/hook"
chmod 644 "$T/hook"
expect_error 'in Actions the hook error is one error line on stderr' \
  "::error::$T/hook is not executable, git will not run it. Fix with: git update-index --chmod=+x $T/hook" \
  GITHUB_ACTIONS=true COMMIT_MSG_HOOK="$T/hook" -- 'HEAD^!'
expect_error 'outside Actions the hook error is plain text' \
  "$T/hook is not executable, git will not run it. Fix with: git update-index --chmod=+x $T/hook" \
  COMMIT_MSG_HOOK="$T/hook" -- 'HEAD^!'

echo '--- a range that can be listed ---'
run GITHUB_ACTIONS=true -- 'HEAD~1..HEAD'
if [ "$rc" -eq 0 ] && ! grep -q -e '::error' "$T/out" "$T/err" &&
  grep -qxF 'All checked messages follow the commit conventions.' "$T/out"; then
  pass 'a good range passes with no error line'
else
  fail "a good range passes with no error line (rc $rc)" "$(both)"
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
