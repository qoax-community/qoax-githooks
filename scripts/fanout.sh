#!/bin/sh
#
# fanout.sh: add the sync commit to the open pull requests that bump the
# qoax-githooks pin, so that the tracked copy of the hook matches the pin.
#
#   sh fanout.sh                     # a dry run: commit in clones, push nothing
#   sh fanout.sh --apply             # push, after one OK at the terminal
#   sh fanout.sh --apply --batch 5   # one OK for each 5 branches
#   sh fanout.sh --ref v1.1.0        # a branch of its own, with no pull request
#   sh fanout.sh --list              # print the repositories, then stop
#   sh fanout.sh owner/name...       # only these repositories
#
# Run it on your machine. It needs git, and gh with a login that can push.
#
# With no name, it works on the repositories of qoax-community that are not
# archived, and on the four repositories of angel-penchev that track the
# hook. qoax-githooks itself has no copy, so it is not in the list.
#
# For each repository, it finds the open Dependabot pull request that bumps
# qoax-community/qoax-githooks. It clones the repository into a temporary
# folder and checks out the head branch. When the copy differs from the hook
# of the pin, it merges the base branch into a head branch that is behind,
# runs sync-hook.sh, and commits:
#
#   chore: sync the commit-msg hook to vX.Y.Z
#
# The new hook must accept each message of the run first. The commits use
# --no-verify, so the other hooks of the repository do not run: a Git LFS
# pre-push stops when git-lfs is missing, and an npm pre-commit stops when
# node_modules is missing. It never rebases and never force-pushes.
#
# With --ref, it works on the branch chore/qoax-githooks-sync, from the
# default branch. One commit points each `uses: qoax-community/qoax-githooks@`
# step at the commit of the tag, with the tag as the last token of the
# comment, and writes the hook of that release into the copy. Use it when
# Dependabot opened no pull request. Open the pull request yourself.
#
# Exit status: 0 no repository needs a person. 1 a repository needs a person
# (see its ATTN line), or the question got no OK. 2 bad usage.
set -u

url="${QOAX_GITHOOKS_URL:-https://github.com/qoax-community/qoax-githooks.git}"
here="$(cd "$(dirname "$0")" && pwd)"
action=qoax-community/qoax-githooks
own_branch=chore/qoax-githooks-sync
# gh lists the repositories of qoax-community. These are the others.
personal='angel-penchev/infrastructure-reusables
angel-penchev/servacho-infrastructure
angel-penchev/balkanauction-automator
angel-penchev/balkanauction-automator-old'
# Only a person may answer the question, so a pipe must not. The tests give
# a file here.
tty="${QOAX_FANOUT_TTY:-/dev/tty}"
tab="$(printf '\t')"
nl='
'

# Without this, a clone of a Git LFS repository downloads every LFS file. The
# sync needs none of them, and the organisation has a monthly LFS quota.
GIT_LFS_SKIP_SMUDGE=1
# A prompt for a password in one clone would stop the whole run.
GIT_TERMINAL_PROMPT=0
export GIT_LFS_SKIP_SMUDGE GIT_TERMINAL_PROMPT
# A hook or `git rebase --exec` can export these. They would point each git
# command of the run at that repository, not at the clone.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE

say() { printf 'fanout: %s\n' "$*" >&2; }
die() {
  say "$@"
  exit 1
}
usage() {
  say "$1"
  printf 'usage: sh fanout.sh [--apply] [--batch <n>] [--ref <vX.Y.Z>] [<owner/name>...]\n' >&2
  printf '       sh fanout.sh --list\n' >&2
  exit 2
}
# One line for each repository, so that a person can scan the run.
report() { printf '%-4s  %s: %s\n' "$1" "$2" "$3"; }
attn() { report ATTN "$repo" "$label$1"; }
indent() { sed 's/^/        /'; }

ask() {
  printf '%s [y/N] ' "$1"
  if ! (: <"$tty") 2>/dev/null; then
    printf '\n'
    say "No terminal to ask on ($tty)."
    return 1
  fi
  answer=''
  read -r answer <"$tty" || answer=''
  case "$answer" in
    y | Y | yes | Yes | YES) return 0 ;;
  esac
  return 1
}

list_repos() {
  orgs="$(gh repo list qoax-community --limit 1000 --no-archived \
    --json nameWithOwner --jq '.[].nameWithOwner' 2>"$tmp/err")" ||
    die "gh repo list qoax-community failed: $(sed -n 1p "$tmp/err")"
  # The archived ones stay out, because a push to them fails.
  mine="$(gh repo list angel-penchev --limit 1000 --no-archived \
    --json nameWithOwner --jq '.[].nameWithOwner' 2>"$tmp/err")" ||
    die "gh repo list angel-penchev failed: $(sed -n 1p "$tmp/err")"
  printf '%s\n' "$personal" >"$tmp/personal"
  {
    printf '%s\n' "$orgs"
    printf '%s\n' "$mine" | grep -xF -f "$tmp/personal"
  } | awk -v a="$action" 'NF && $0 != a' | LC_ALL=C sort -u
}

# Prints "file:line: ref" for each step that uses the action. A comment line
# does not count, because it runs nothing.
pins() {
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    awk -v sq="'" '
      BEGIN { re = "^[ \t]*(-[ \t]+)?uses:[ \t]*[\"" sq "]?qoax-community/qoax-githooks@" }
      $0 ~ re {
        ref = $0
        sub(/^[^@]*@/, "", ref)
        sub("[ \t\r\"#" sq "].*$", "", ref)
        print FILENAME ":" FNR ": " ref
      }' "$f"
  done
}

# Points each step that uses the action at SHA. Dependabot updates the
# comment only while the release is its last token, so TAG goes there. Other
# words of the comment stay. With --check, it writes nothing and fails when
# a file would change.
rewrite_pins() { # SHA TAG [--check]
  pins | sed 's/:[0-9]*: .*//' | sort -u >"$tmp/files"
  while IFS= read -r f; do
    awk -v sha="$1" -v tag="$2" -v sq="'" '
      BEGIN {
        name = "qoax-community/qoax-githooks@"
        re = "^[ \t]*(-[ \t]+)?uses:[ \t]*[\"" sq "]?" name
      }
      {
        line = $0
        cr = ""
        if (sub(/\r$/, "", line)) cr = "\r"
        if (line !~ re) { print; next }
        at = index(line, name) + length(name)
        head = substr(line, 1, at - 1)
        rest = substr(line, at)
        match(rest, "^[^ \t\"#" sq "]*")
        rest = substr(rest, RLENGTH + 1)
        q = substr(rest, 1, 1)
        if (q == "\"" || q == sq) rest = substr(rest, 2)
        else q = ""
        h = index(rest, "#")
        if (h == 0) { print head sha q " # " tag cr; next }
        c = substr(rest, h + 1)
        sub(/[ \t]+$/, "", c)
        if (match(c, /v?[0-9]+(\.[0-9]+)*$/) && (RSTART == 1 || substr(c, RSTART - 1, 1) ~ /[ \t]/))
          c = substr(c, 1, RSTART - 1) tag
        else
          c = c " " tag
        print head sha q substr(rest, 1, h) c cr
      }' "$f" >"$tmp/pinned" || return 1
    if ! cmp -s "$f" "$tmp/pinned"; then
      [ "${3-}" != --check ] || return 1
      cat "$tmp/pinned" >"$f" && git add -- "$f" || return 1
    fi
  done <"$tmp/files"
}

# The newest release tag vX.Y.Z at the commit of a pinned ref.
release_of() {
  c="$1"
  if ! printf '%s\n' "$c" | grep -qxE '[0-9a-f]{40}'; then
    c="$(printf '%s\n' "$pairs" | awk -v n="$1" '$2 == n { print $1 }')"
  fi
  [ -n "$c" ] || return 1
  t="$(printf '%s\n' "$pairs" |
    awk -v c="$c" '$1 == c && $2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ { print substr($2, 2) }' |
    sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
  [ -n "$t" ] && printf 'v%s\n' "$t"
}

gitlink() { [ -n "$(git ls-files -s -- .githooks | awk '$1 == "160000"')" ]; }
staged() { ! git diff --cached --quiet; }

clone() { # REPO DIR
  # No hook may run in the clone, so core.hooksPath names an empty folder.
  # With core.autocrlf=false the work tree holds the committed bytes, and the
  # check of the copy judges the commit, not this machine.
  gh repo clone "$1" "$2" -- -q --no-tags -c core.hooksPath="$no_hooks" \
    -c core.autocrlf=false </dev/null >"$tmp/err" 2>&1 && return 0
  attn "the clone failed:"
  indent <"$tmp/err"
  return 1
}

# A rebase would need a force-push, and a person may have pushed to the
# branch. A merge keeps every commit.
merge_base() { # BASE BRANCH
  merge_msg="chore: merge $1 into the qoax-githooks bump"
  if git merge -q --no-verify --no-edit -m "$merge_msg" "origin/$1" >"$tmp/err" 2>&1; then
    return 0
  fi
  git merge --abort >/dev/null 2>&1
  attn "origin/$1 does not merge into $2 without a conflict. Merge it by hand."
  return 1
}

sync_copy() {
  sh "$here/sync-hook.sh" >"$tmp/sync" 2>&1 && return 0
  attn 'sync-hook.sh failed:'
  indent <"$tmp/sync"
  return 1
}

# The hook needs bash 4 or later. Without it, the hook warns and lets each
# message through, so first it must reject a bad one.
hook_accepts() { # MESSAGE...
  printf 'bad message\n' >"$tmp/msg"
  COMMIT_MSG_REPORT_ONLY=1 ./.githooks/commit-msg "$tmp/msg" >"$tmp/err" 2>&1
  if [ "$?" != 1 ]; then
    attn "the new hook does not reject 'bad message'. Does bash 4 or later run it?"
    indent <"$tmp/err"
    return 1
  fi
  for m in "$@"; do
    printf '%s\n' "$m" >"$tmp/msg"
    if ! COMMIT_MSG_REPORT_ONLY=1 ./.githooks/commit-msg "$tmp/msg" >"$tmp/err" 2>&1; then
      attn "the new hook rejects '$m'. Nothing is pushed."
      indent <"$tmp/err"
      return 1
    fi
  done
}

commit() { # MESSAGE
  git commit -q --no-verify -m "$1" >"$tmp/err" 2>&1 && return 0
  attn 'git commit failed:'
  indent <"$tmp/err"
  return 1
}

# finish BRANCH START NOTE: check the messages of $merge_msg (a merge that
# is made already) and $sync_msg (the staged change), commit the change, and
# get the branch ready to push.
finish() {
  to="$1" from="$2" note="$3"
  set --
  [ -z "$merge_msg" ] || set -- "$merge_msg"
  [ -z "$sync_msg" ] || set -- "$@" "$sync_msg"
  hook_accepts "$@" || return 1
  if [ -n "$sync_msg" ]; then
    commit "$sync_msg" || return 1
  fi
  ready "$to" "$from" "$note"
}

ready() { # BRANCH START NOTE
  n="$(git rev-list --first-parent --count "$2..HEAD")"
  word=commits
  [ "$n" != 1 ] || word=commit
  report PLAN "$repo" "${label}push $n $word to $1${3-}"
  git log --first-parent --reverse --format='%s' "$2..HEAD" | indent
  if [ "$apply" = 1 ]; then
    printf '%s\t%s\t%s\t%s\n' "$repo" "$dir" "$1" "$label" >>"$tmp/ready"
  fi
}

# The sync commit on the head branch of the Dependabot pull request.
sync_pr() ( # REPO DIR
  repo="$1" dir="$2" label=''
  if ! prs="$(gh pr list -R "$repo" --state open --limit 200 \
    --json number,headRefName,baseRefName,title \
    --jq '.[] | [.number, .headRefName, .baseRefName, .title] | @tsv' \
    </dev/null 2>"$tmp/err")"; then
    attn "gh pr list failed: $(sed -n 1p "$tmp/err")"
    exit 1
  fi
  # Dependabot names the branch after the dependency, and the title names it
  # too. Either one is enough.
  prs="$(printf '%s\n' "$prs" | awk -F '\t' -v a="$action" '
    $2 ~ /^dependabot\// && (index($2, a) || index($4, a)) { print $1 "\t" $2 "\t" $3 }')"
  case "$prs" in
    '')
      report NONE "$repo" "no open Dependabot pull request bumps $action"
      exit 0
      ;;
    *"$nl"*)
      attn "more than one open pull request bumps $action: $(printf '%s\n' "$prs" |
        cut -f1 | sed 's/^/#/' | paste -s -d ' ' -)"
      exit 1
      ;;
  esac
  number="$(printf '%s\n' "$prs" | cut -f1)"
  head="$(printf '%s\n' "$prs" | cut -f2)"
  base="$(printf '%s\n' "$prs" | cut -f3)"
  label="#$number: "

  clone "$repo" "$dir" || exit 1
  cd "$dir" || exit 1
  if ! git rev-parse -q --verify "refs/remotes/origin/$head" >/dev/null ||
    ! git rev-parse -q --verify "refs/remotes/origin/$base" >/dev/null; then
    attn "the clone lacks the branch $head or $base."
    exit 1
  fi
  if ! git switch -q -c "$head" "origin/$head" 2>"$tmp/err"; then
    attn "git switch $head failed: $(sed -n 1p "$tmp/err")"
    exit 1
  fi
  if gitlink; then
    report SKIP "$repo" "$label$head still has the submodule. Migrate $base first."
    exit 0
  fi
  if sh "$here/sync-hook.sh" --check >/dev/null 2>&1; then
    report OK "$repo" "${label}the copy matches the pin. Nothing to push."
    exit 0
  fi

  start="$(git rev-parse HEAD)"
  merge_msg=''
  if ! git merge-base --is-ancestor "origin/$base" HEAD; then
    merge_base "$base" "$head" || exit 1
  fi
  sync_copy || exit 1
  sync_msg=''
  if staged; then
    pin="$(pins | sed -n '1s/^.*: //p')"
    if ! tag="$(release_of "$pin")"; then
      attn "the pin $pin is no release tag vX.Y.Z at $url."
      exit 1
    fi
    sync_msg="chore: sync the commit-msg hook to $tag"
  fi
  if [ -z "$merge_msg$sync_msg" ]; then
    report OK "$repo" "${label}the commit has the hook of the pin. Only the work tree differed, so nothing to push."
    exit 0
  fi
  finish "$head" "$start" ''
)

# The OK line of --ref. A fresh branch starts at the tip of the base, so then
# the base has the pin and the hook.
in_place() {
  if [ -n "$fresh" ]; then
    report OK "$repo" "$base already pins $ref and has its hook. Nothing to push."
  else
    report OK "$repo" "$own_branch already pins $ref and has its hook$note. Nothing to push."
  fi
}

# The pin and the copy of --ref, on a branch of its own.
sync_ref() ( # REPO DIR
  repo="$1" dir="$2" label=''
  clone "$repo" "$dir" || exit 1
  cd "$dir" || exit 1
  if [ -z "$(git for-each-ref refs/remotes/origin)" ]; then
    report SKIP "$repo" 'the repository is empty.'
    exit 0
  fi
  base="$(git symbolic-ref -q --short refs/remotes/origin/HEAD)" || base=''
  base="${base#origin/}"
  if [ -z "$base" ] || ! git rev-parse -q --verify "refs/remotes/origin/$base" >/dev/null; then
    attn 'the clone has no default branch.'
    exit 1
  fi
  fresh=1
  from="origin/$base"
  if git rev-parse -q --verify "refs/remotes/origin/$own_branch" >/dev/null &&
    ! git merge-base --is-ancestor "origin/$own_branch" "origin/$base"; then
    # The branch has commits that the base lacks, so it is open work. A
    # branch that the base contains takes the base tip as a fast-forward.
    fresh=''
    from="origin/$own_branch"
  fi
  if ! git switch -q -c "$own_branch" "$from" 2>"$tmp/err"; then
    attn "git switch $own_branch failed: $(sed -n 1p "$tmp/err")"
    exit 1
  fi
  start="$(git rev-parse HEAD)"
  if gitlink; then
    report SKIP "$repo" "$base still has the submodule. Migrate it first."
    exit 0
  fi
  if [ -z "$(pins)" ]; then
    if [ -n "$(git ls-files -- .githooks/commit-msg)" ]; then
      attn "it has .githooks/commit-msg, but no workflow uses $action."
      exit 1
    fi
    report SKIP "$repo" "it does not use $action."
    exit 0
  fi

  if ! pr="$(gh pr list -R "$repo" --head "$own_branch" --state open \
    --json number --jq '.[].number' </dev/null 2>/dev/null)"; then
    note=', and gh cannot say if it has a pull request'
  elif [ -n "$pr" ]; then
    note=", pull request #$(printf '%s\n' "$pr" | sed -n 1p)"
  else
    note=', with no pull request yet'
  fi

  merge_msg=''
  if [ -z "$fresh" ] && ! git merge-base --is-ancestor "origin/$base" HEAD; then
    # A merge restarts the checks of the pull request. So the base goes in
    # only when the pin or the copy must change, as in sync_pr. That way a
    # second run pushes nothing.
    if [ "$(pins | sed 's/^.*: //' | sort -u)" = "$ref_sha" ] &&
      rewrite_pins "$ref_sha" "$ref" --check &&
      sh "$here/sync-hook.sh" --check >/dev/null 2>&1; then
      in_place
      exit 0
    fi
    merge_base "$base" "$own_branch" || exit 1
  fi
  rewrite_pins "$ref_sha" "$ref" || {
    attn 'the pins could not be rewritten.'
    exit 1
  }
  if [ "$(pins | sed 's/^.*: //' | sort -u)" != "$ref_sha" ]; then
    attn "a pin still names another ref. Edit it by hand:"
    pins | indent
    exit 1
  fi
  pin_moved=''
  git diff --cached --quiet -- .github/workflows || pin_moved=1
  sync_copy || exit 1
  copy_moved=''
  git diff --cached --quiet -- .githooks/commit-msg || copy_moved=1

  if ! staged && [ -z "$merge_msg" ]; then
    in_place
    exit 0
  fi
  sync_msg=''
  if [ -n "$pin_moved" ] && [ -n "$copy_moved" ]; then
    sync_msg="chore: bump qoax-githooks to $ref and sync the commit-msg hook"
  elif [ -n "$pin_moved" ]; then
    sync_msg="chore: bump qoax-githooks to $ref"
  elif [ -n "$copy_moved" ]; then
    sync_msg="chore: sync the commit-msg hook to $ref"
  fi
  finish "$own_branch" "$start" "$note"
)

push_batch() {
  [ -s "$tmp/ready" ] || return 0
  n="$(awk 'END { print NR }' "$tmp/ready")"
  printf '\nReady to push:\n'
  while IFS="$tab" read -r r d b l; do
    printf '  %s %s\n' "$r" "$b"
  done <"$tmp/ready"
  question="Push these $n branches?"
  [ "$n" != 1 ] || question='Push this branch?'
  if ! ask "$question"; then
    printf 'No OK, so nothing of this batch is pushed. The run stops here.\n'
    return 1
  fi
  while IFS="$tab" read -r r d b l; do
    # A plain push fails when the branch moved since the clone. That is the
    # safe result: run fanout.sh again.
    if git -C "$d" push -q --no-verify origin "HEAD:refs/heads/$b" </dev/null >"$tmp/err" 2>&1; then
      report PUSH "$r" "$l$b is at $(git -C "$d" rev-parse --short HEAD)"
    else
      report ATTN "$r" "${l}the push to $b failed. Run fanout.sh again."
      indent <"$tmp/err"
      status=1
    fi
    rm -rf "$d"
  done <"$tmp/ready"
  : >"$tmp/ready"
}

# add_repo NAME: one name for each line, so that no word splitting or glob
# can change a name.
add_repo() {
  printf '%s\n' "$1" | grep -qxE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' ||
    usage "'$1' is not a repository owner/name."
  repos="$repos$1$nl"
}

apply=0
batch=0
ref=''
list=0
repos=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --list) list=1 ;;
    --batch)
      [ "$#" -ge 2 ] || usage '--batch needs a number.'
      batch="$2"
      shift
      ;;
    --batch=*) batch="${1#--batch=}" ;;
    --ref)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage '--ref needs a release tag vX.Y.Z.'
      ref="$2"
      shift
      ;;
    --ref=?*) ref="${1#--ref=}" ;;
    -h | --help)
      printf 'usage: sh fanout.sh [--apply] [--batch <n>] [--ref <vX.Y.Z>] [<owner/name>...]\n'
      printf '       sh fanout.sh --list\n'
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
case "$batch" in
  '' | *[!0-9]*) usage "--batch needs a number, not '$batch'." ;;
esac
if [ -n "$ref" ] && ! printf '%s\n' "$ref" | grep -qxE 'v[0-9]+\.[0-9]+\.[0-9]+'; then
  usage "--ref needs a release tag vX.Y.Z, not '$ref'."
fi
command -v git >/dev/null 2>&1 || die 'git is not installed.'
command -v gh >/dev/null 2>&1 || die 'gh is not installed.'

# mktemp -d without a template ignores TMPDIR on macOS.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fanout.XXXXXX")" || die 'Cannot make a temporary folder.'
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
no_hooks="$tmp/no-hooks"
mkdir "$no_hooks" || die "Cannot make $no_hooks."
: >"$tmp/ready"

if [ "$list" = 1 ]; then
  list_repos
  exit 0
fi
if [ -n "$repos" ]; then
  printf '%s' "$repos" >"$tmp/repos"
else
  list_repos >"$tmp/repos" || exit 1
fi

# ls-remote prints an annotated tag twice. The ^{} line has the commit.
remote_tags="$(git ls-remote --tags "$url" 2>"$tmp/err")" ||
  die "Cannot list the tags of $url: $(sed -n 1p "$tmp/err")"
pairs="$(printf '%s\n' "$remote_tags" | awk '
  BEGIN { FS = "\t" }
  $2 ~ /^refs\/tags\// {
    name = substr($2, 11)
    if (name ~ /\^\{\}$/) peeled[substr(name, 1, length(name) - 3)] = $1
    else plain[name] = $1
  }
  END { for (n in plain) print ((n in peeled) ? peeled[n] : plain[n]) " " n }')"
ref_sha=''
if [ -n "$ref" ]; then
  ref_sha="$(printf '%s\n' "$pairs" | awk -v n="$ref" '$2 == n { print $1 }')"
  [ -n "$ref_sha" ] || die "$url has no tag $ref."
fi

status=0
stopped=''
i=0
# The names come on fd 3, because a command in the loop may read stdin.
while IFS= read -r repo <&3; do
  [ -n "$repo" ] || continue
  i=$((i + 1))
  dir="$tmp/clone-$i"
  if [ -n "$ref" ]; then
    sync_ref "$repo" "$dir" || status=1
  else
    sync_pr "$repo" "$dir" || status=1
  fi
  if ! awk -F '\t' -v d="$dir" '$2 == d { f = 1 } END { exit !f }' "$tmp/ready"; then
    rm -rf "$dir"
  fi
  if [ "$batch" -gt 0 ] && [ "$(awk 'END { print NR }' "$tmp/ready")" -ge "$batch" ]; then
    push_batch || {
      stopped=1
      break
    }
  fi
done 3<"$tmp/repos"
[ -n "$stopped" ] || push_batch || stopped=1

if [ "$apply" = 0 ]; then
  printf '\nDry run: nothing is pushed. Run it again with --apply to push.\n'
fi
[ -z "$stopped" ] || status=1
if [ "$status" != 0 ] && [ -z "$stopped" ]; then
  say 'A repository needs a person. See its ATTN line.'
fi
exit "$status"
