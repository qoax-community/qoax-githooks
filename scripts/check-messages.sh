#!/usr/bin/env bash
#
# check-messages.sh — run commit-msg over a range of commits.
#
# The hook validates one message at a time, at the moment it is written. This
# runs the same hook over messages that already exist: a pull request's commits
# in CI, or a range you name locally before pushing.
#
#   scripts/check-messages.sh main..HEAD          # a range you name
#   scripts/check-messages.sh                     # a range from the CI event
#   COMMIT_MSG_HOOK=/path/to/commit-msg scripts/check-messages.sh main..HEAD
#
# With no range, it reads the event GitHub Actions describes through the
# environment: EVENT_NAME, BASE_SHA and HEAD_SHA for a pull request,
# PUSH_BEFORE and PUSH_AFTER for a push. PR_TITLE, when set, is checked too:
# with squash merging it becomes the commit subject on the default branch.
#
# Findings are annotated for Actions only when GITHUB_ACTIONS is set, so the
# local output stays plain. Exit status is the number of failures, capped at 1.
#
set -uo pipefail

# Workflow commands only mean something to Actions; locally they are noise.
annotate() { [ -n "${GITHUB_ACTIONS-}" ] && printf "$@"; return 0; }
plain()    { [ -z "${GITHUB_ACTIONS-}" ] && printf "$@"; return 0; }
err()      { annotate '::error::'; printf "$@" >&2; }

summary() {
  [ -n "${GITHUB_STEP_SUMMARY-}" ] || return 0
  cat >>"$GITHUB_STEP_SUMMARY"
}

# The hook next to this script, unless told otherwise. A caller checking out
# this repository somewhere else can point at any copy.
here="$(cd "$(dirname "$0")" && pwd)"
hook="${COMMIT_MSG_HOOK:-$here/../commit-msg}"

# A hook without the executable bit is silently skipped by git, so contributors
# would get no validation at all. Catch that here.
if [ ! -x "$hook" ]; then
  err '%s is not executable, git will not run it. Fix with: git update-index --chmod=+x %s\n' \
    "$hook" "$hook"
  exit 1
fi

# The hook reports on a message that is already stored, so it must not use the
# "commit aborted" wording it uses at commit time.
export COMMIT_MSG_REPORT_ONLY=1

message="$(mktemp)"
output="$(mktemp)"
trap 'rm -f "$message" "$output"' EXIT
failures=0

# Validate the message in $1, labelled $2 for the log and the summary.
check() {
  local label="$2"
  if "$hook" "$1" >"$output" 2>&1; then
    annotate '::notice::%s — ok\n' "$label"
    plain 'ok  %s\n' "$label"
    # A pass can still have something to say; do not swallow it.
    [ -s "$output" ] && cat "$output"
    return 0
  fi
  failures=$((failures + 1))
  annotate '::group::%s — rejected\n' "$label"
  plain 'FAIL %s\n' "$label"
  cat "$output"
  annotate '::endgroup::\n'
  {
    # An indented block rather than a fenced one: the hook echoes the message
    # back, and a message may contain a fence of its own.
    printf '### %s\n\n' "$label"
    sed 's/^/    /' "$output"
    printf '\n'
  } | summary
}

if [ "$#" -gt 0 ]; then
  range="$1"
elif [ "${EVENT_NAME-}" = pull_request ]; then
  range="$(git merge-base "$BASE_SHA" "$HEAD_SHA")..${HEAD_SHA}"
elif [ -n "${PUSH_BEFORE-}" ] && \
     [ -n "${PUSH_BEFORE#0000000000000000000000000000000000000000}" ]; then
  range="${PUSH_BEFORE}..${PUSH_AFTER}"
elif [ -n "${PUSH_AFTER-}" ]; then
  # The branch was created by this push, so there is no range to compare
  # against. Everything it carries would mean the whole history, which predates
  # this convention, so check the tip and say plainly that the rest went
  # unchecked rather than implying it did. "<rev>^!" is that commit and nothing
  # it descends from, which works for a root commit and does not drag in a
  # merge's second parent the way "<rev>~1.." would.
  range="${PUSH_AFTER}^!"
  annotate '::notice::branch created by this push — only its tip commit is checked\n'
else
  printf 'usage: %s <range>\n' "$0" >&2
  printf '   or: set EVENT_NAME and the shas GitHub Actions provides\n' >&2
  exit 2
fi

# A range that cannot be enumerated is a broken assumption, not an empty
# result: after a force-push the old tip is simply gone. Say so instead of
# quietly falling back to checking one commit.
if ! commits="$(git rev-list --no-merges --reverse "$range")"; then
  err 'cannot enumerate %s — the range is not available in this checkout, ' "$range"
  printf 'which happens after a force-push. Re-run this job.\n' >&2
  exit 1
fi

if [ -z "$commits" ]; then
  printf 'no commits in %s\n' "$range"
fi

for sha in $commits; do
  git log -1 --format=%B "$sha" >"$message"
  check "$message" "commit $(git log -1 --format=%h "$sha")"
done

# Passed through the environment rather than interpolated into a workflow's
# script, so a title can never be read as shell.
if [ -n "${PR_TITLE-}" ]; then
  printf '%s\n' "$PR_TITLE" >"$message"
  # A commit may carry an autosquash marker; git squashes it away. A title may
  # not: squash merging makes it the subject on the default branch.
  COMMIT_MSG_NO_AUTOSQUASH=1 check "$message" 'pull request title'
fi

if [ "$failures" -gt 0 ]; then
  printf "\n%s message(s) do not follow the commit conventions: Conventional\n" "$failures" >&2
  printf 'Commits v1.0.0 plus the house rules the hook reports above.\n' >&2
  printf 'Rewrite them with `git rebase -i` (or edit the pull request title) and push again.\n' >&2
  exit 1
fi

printf 'All checked messages follow the commit conventions.\n'
