#!/bin/sh
#
# merge-sync-prs.sh: merge the open pull requests that bump the qoax-githooks
# pin, when all their checks passed.
#
#   sh merge-sync-prs.sh                 # a dry run: list them, merge nothing
#   sh merge-sync-prs.sh --apply         # list them, ask one time, merge
#   sh merge-sync-prs.sh owner/name...   # only these repositories
#
# Run it on your machine. It needs gh, with a login that can merge. With no
# name, it takes the repositories from fanout.sh --list.
#
# A pull request counts when Dependabot opened it for
# qoax-community/qoax-githooks, or when its head branch is
# chore/qoax-githooks-sync, the branch of fanout.sh --ref. The list shows the
# state of the checks, the repository, the number, the version and the base.
# A pull request is green only when it has checks and each one passed or was
# skipped. Each green one gets a merge commit
#
#   chore: merge pull request #N from OWNER/BRANCH
#
# with the title of the pull request as the body. The merge must find the
# head commit that the list saw, so a push after the list stops that merge.
#
# Exit status: 0 no listing and no merge failed. 1 a listing or a merge
# failed, or the question got no OK. 2 bad usage.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
action=qoax-community/qoax-githooks
own_branch=chore/qoax-githooks-sync
# read splits at this separator. A tab is white space to read, so two tabs
# around an empty field would count as one and shift the fields after it.
us="$(printf '\037')"
nl='
'

say() { printf 'merge-sync-prs: %s\n' "$*" >&2; }
die() {
  say "$@"
  exit 1
}
usage() {
  say "$1"
  printf 'usage: sh merge-sync-prs.sh [--apply] [<owner/name>...]\n' >&2
  exit 2
}
indent() { sed 's/^/        /'; }

# Only a person may answer, so the answer comes from the terminal, never
# from a pipe.
ask() {
  printf '%s [y/N] ' "$1"
  if ! (: </dev/tty) 2>/dev/null; then
    printf '\n'
    say 'No terminal to ask on.'
    return 1
  fi
  answer=''
  read -r answer </dev/tty || answer=''
  case "$answer" in
    y | Y | yes | Yes | YES) return 0 ;;
  esac
  return 1
}

# A pull request with no checks is not green, because then nothing compared
# the copy with the pin.
checks() { # REPO NUMBER
  buckets="$(gh pr checks "$2" -R "$1" --json bucket --jq '.[].bucket' \
    </dev/null 2>"$tmp/err")"
  if [ -z "$buckets" ]; then
    if grep -q 'no checks' "$tmp/err"; then
      printf 'none\n'
    else
      printf 'unknown\n'
    fi
    return
  fi
  printf '%s\n' "$buckets" | awk '
    { seen[$1] = 1 }
    END {
      if (("fail" in seen) || ("cancel" in seen)) { print "failing"; exit }
      if ("pending" in seen) { print "pending"; exit }
      for (b in seen) if (b != "pass" && b != "skipping") { print "unknown"; exit }
      print "green"
    }'
}

# The last version in the title. Dependabot writes "from 1.0.7 to 1.1.0".
version_of() {
  printf '%s\n' "$1" | awk '{
    v = ""
    s = $0
    while (match(s, /v?[0-9]+\.[0-9]+\.[0-9]+/)) {
      v = substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
    }
    if (v != "" && v !~ /^v/) v = "v" v
    print (v == "" ? "?" : v)
  }'
}

apply=0
repos=''
add_repo() {
  printf '%s\n' "$1" | grep -qxE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' ||
    usage "'$1' is not a repository owner/name."
  repos="$repos$1$nl"
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    -h | --help)
      printf 'usage: sh merge-sync-prs.sh [--apply] [<owner/name>...]\n'
      exit 0
      ;;
    --)
      shift
      for r in "$@"; do
        add_repo "$r"
      done
      break
      ;;
    -*) usage "unknown argument: $1" ;;
    *) add_repo "$1" ;;
  esac
  shift
done
command -v gh >/dev/null 2>&1 || die 'gh is not installed.'

# mktemp -d without a template ignores TMPDIR on macOS.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/merge-sync-prs.XXXXXX")" || die 'Cannot make a temporary folder.'
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

if [ -n "$repos" ]; then
  printf '%s' "$repos" >"$tmp/repos"
else
  sh "$here/fanout.sh" --list >"$tmp/repos" || die 'fanout.sh --list failed.'
fi

status=0
total=0
: >"$tmp/green"
# The names come on fd 3, because gh may read stdin.
while IFS= read -r repo <&3; do
  [ -n "$repo" ] || continue
  if ! gh pr list -R "$repo" --state open --limit 200 \
    --json number,headRefName,headRefOid,headRepositoryOwner,baseRefName,title \
    --jq '.[] | [.number, .headRefName, .headRefOid, .headRepositoryOwner.login, .baseRefName, .title] | @tsv' \
    </dev/null >"$tmp/all" 2>"$tmp/err"; then
    printf 'error   %s: gh pr list failed: %s\n' "$repo" "$(sed -n 1p "$tmp/err")"
    status=1
    continue
  fi
  awk -F '\t' -v a="$action" -v b="$own_branch" -v us="$us" '
    BEGIN { OFS = us }
    ($2 ~ /^dependabot\// && (index($2, a) || index($6, a))) || $2 == b { $1 = $1; print }' \
    "$tmp/all" >"$tmp/prs"
  while IFS="$us" read -r number head oid owner base title; do
    [ -n "$number" ] || continue
    total=$((total + 1))
    state="$(checks "$repo" "$number")"
    printf '%-7s %s #%s %s into %s\n' "$state" "$repo" "$number" \
      "$(version_of "$title")" "$base"
    if [ "$state" = green ]; then
      printf '%s\037%s\037%s\037%s\037%s\037%s\n' "$repo" "$number" "$head" "$oid" "$owner" "$title" \
        >>"$tmp/green"
    fi
  done <"$tmp/prs"
done 3<"$tmp/repos"

green="$(awk 'END { print NR }' "$tmp/green")"
printf '\n'
if [ "$total" = 0 ]; then
  printf 'No open pull request bumps %s.\n' "$action"
  exit "$status"
fi
if [ "$green" = 0 ]; then
  printf 'No pull request is green, so nothing is merged.\n'
  exit "$status"
fi
if [ "$apply" = 0 ]; then
  printf 'Dry run: nothing is merged. With --apply, after one OK, these merge:\n'
  while IFS="$us" read -r repo number head oid owner title; do
    printf '  %s #%s: chore: merge pull request #%s from %s/%s\n' \
      "$repo" "$number" "$number" "$owner" "$head"
  done <"$tmp/green"
  exit "$status"
fi

if ! ask "Merge the $green green pull requests?"; then
  printf 'No OK, so nothing is merged.\n'
  exit 1
fi
while IFS="$us" read -r repo number head oid owner title; do
  if gh pr merge "$number" -R "$repo" --merge --match-head-commit "$oid" \
    --subject "chore: merge pull request #$number from $owner/$head" --body "$title" \
    </dev/null >"$tmp/err" 2>&1; then
    printf 'merged  %s #%s\n' "$repo" "$number"
  else
    printf 'failed  %s #%s:\n' "$repo" "$number"
    indent <"$tmp/err"
    status=1
  fi
done <"$tmp/green"
exit "$status"
