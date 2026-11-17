#!/bin/sh
#
# Cases for scripts/fanout.sh, and the dry run of scripts/merge-sync-prs.sh.
# Bare repositories stand in for GitHub. A fake gh on PATH clones them
# through file:// URLs, answers the read calls from fixture files, and
# refuses every write. A fixture qoax-githooks comes through
# QOAX_GITHOOKS_URL. No case needs the network. The scripts run under
# TEST_SHELL. Prints "failures: N".
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
test_shell="${TEST_SHELL:-sh}"
script="$root/scripts/fanout.sh"
merger="$root/scripts/merge-sync-prs.sh"

# mktemp -d without a template ignores TMPDIR on macOS. git prints the
# physical path of a work tree, and /var on macOS is a symbolic link.
T="$(mktemp -d "${TMPDIR:-/tmp}/fanout.XXXXXX")" && T="$(cd "$T" && pwd -P)" || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

# The fixtures must not see the git configuration of the person who runs the
# tests, or a repository above the temporary folder.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT QOAX_GITHOOKS_URL \
  QOAX_FANOUT_TTY GIT_LFS_SKIP_SMUDGE
fake="$T/gh"
mkdir -p "$HOME" "$T/no-hooks" "$T/nowhere" "$T/bin" "$T/tmp" "$T/work" \
  "$fake/origins" "$fake/prs" "$fake/heads" "$fake/lists" "$fake/fail" \
  "$fake/sync-prs" "$fake/checks"
: >"$fake/calls"
export PATH="$T/bin:$PATH"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf 'FAIL %s\n' "$1"
  [ -n "${2-}" ] && printf '%s\n' "$2" | sed 's/^/       /'
  return 0
}
# assert NAME COMMAND...: pass when COMMAND succeeds.
assert() {
  name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

where="$T/nowhere"
out=''
# expect NAME WANT_RC WANT_TEXT COMMAND...: run COMMAND in $where. The output
# must hold WANT_TEXT and no shell diagnostic. $out keeps the output.
expect() {
  name="$1" want="$2" text="$3"
  shift 3
  out="$(cd "$where" && "$@" 2>&1)"
  rc=$?
  if [ "$rc" != "$want" ]; then
    fail "$name (rc $rc, want $want)" "$out"
    return
  fi
  case "$out" in
    *"$text"*) ;;
    *)
      fail "$name (no \"$text\")" "$out"
      return
      ;;
  esac
  case "$out" in
    *'unbound variable'* | *'parameter not set'* | *': not found'* | \
      *'command not found'* | *'yntax error'* | *': line '* | *'bad substitution'*)
      fail "$name (shell diagnostic)" "$out"
      return
      ;;
  esac
  pass "$name"
}
# has NAME TEXT: the output of the last expect holds TEXT. lacks: it does not.
has() {
  case "$out" in
    *"$2"*) pass "$1" ;;
    *) fail "$1 (no \"$2\")" "$out" ;;
  esac
}
lacks() {
  case "$out" in
    *"$2"*) fail "$1 (\"$2\" is in the output)" "$out" ;;
    *) pass "$1" ;;
  esac
}
questions() { printf '%s\n' "$out" | grep -c '\[y/N\]'; }

g() {
  d="$1"
  shift
  git -C "$d" -c core.hooksPath="$T/no-hooks" "$@"
}

# The fake gh. Each call goes to $fake/calls, with the value of
# GIT_LFS_SKIP_SMUDGE first.
cat >"$T/bin/gh" <<EOF
#!/bin/sh
d='$fake'
EOF
cat >>"$T/bin/gh" <<'EOF'
printf 'lfs=%s %s\n' "${GIT_LFS_SKIP_SMUDGE-}" "$*" >>"$d/calls"
repo='' head='' fields='' prev=''
for a in "$@"; do
  case "$prev" in
    -R) repo="$a" ;;
    --head) head="$a" ;;
    --json) fields="$a" ;;
  esac
  prev="$a"
done
key="$(printf '%s' "$repo" | tr / _)"
case "$1 $2" in
  'repo clone')
    src="$3" dir="$4"
    shift 4
    [ "${1-}" != -- ] || shift
    exec git clone "$@" "file://$d/origins/$src.git" "$dir"
    ;;
  'repo list')
    [ ! -f "$d/lists/$3" ] || cat "$d/lists/$3"
    exit 0
    ;;
  'pr list')
    if [ -f "$d/fail/$key" ]; then
      echo 'HTTP 404: Not Found' >&2
      exit 1
    fi
    case "$fields" in
      *headRefOid*) f="$d/sync-prs/$key" ;;
      *) if [ -n "$head" ]; then f="$d/heads/$key"; else f="$d/prs/$key"; fi ;;
    esac
    [ ! -f "$f" ] || cat "$f"
    exit 0
    ;;
  'pr checks')
    if [ -f "$d/checks/$key-$3" ]; then
      cat "$d/checks/$key-$3"
      exit 0
    fi
    echo "no checks reported on the 'x' branch" >&2
    exit 1
    ;;
esac
echo "fake gh refuses: $*" >&2
exit 1
EOF
chmod 755 "$T/bin/gh"

# The fixture qoax-githooks. Each release has a hook that wants a
# Conventional Commits subject. The hook of v0.3.0 also rejects the type
# chore. The hook of v0.4.0 lets every message through, as the real hook
# does when no bash 4 or later is there.
qg="$T/qoax-githooks"
git init -q -b main "$qg"
hook() { # VERSION
  printf '#!/bin/sh\n# %s\n' "$1"
  case "$1" in
    v0.4.0)
      printf 'exit 0\n'
      return
      ;;
  esac
  cat <<'EOF'
first="$(sed -n 1p "$1")"
if ! printf '%s\n' "$first" | grep -qE '^[a-z]+(\([a-z0-9-]+\))?!?: [^ ]'; then
  echo "commit-msg: not a Conventional Commits subject: $first" >&2
  exit 1
fi
EOF
  if [ "$1" = v0.3.0 ]; then
    printf 'case "$first" in chore*) echo "commit-msg: no chore" >&2; exit 1 ;; esac\n'
  fi
  printf 'exit 0\n'
}
release() { # TAG [annotated]
  hook "$1" >"$qg/commit-msg"
  chmod 755 "$qg/commit-msg"
  g "$qg" add commit-msg
  g "$qg" commit -q -m "feat: release $1"
  if [ -n "${2-}" ]; then
    git -C "$qg" tag -a "$1" -m "$1: a release"
  else
    git -C "$qg" tag "$1"
  fi
}
release v0.1.0
sha1="$(git -C "$qg" rev-parse HEAD)" blob1="$(git -C "$qg" rev-parse HEAD:commit-msg)"
release v0.2.0 annotated
sha2="$(git -C "$qg" rev-parse HEAD)" blob2="$(git -C "$qg" rev-parse HEAD:commit-msg)"
release v0.3.0 annotated
sha3="$(git -C "$qg" rev-parse HEAD)"
release v0.4.0 annotated
export QOAX_GITHOOKS_URL="file://$qg"

key() { printf '%s' "$1" | tr / _; }
origin() { printf '%s/origins/%s.git' "$fake" "$1"; }
tip() { git -C "$(origin "$1")" rev-parse -q --verify "refs/heads/$2"; }
workflow() { # SHA COMMENT
  printf 'on:\n  pull_request:\njobs:\n  commit-conventions:\n'
  printf '    name: Conventional Commits\n    runs-on: ubuntu-latest\n    steps:\n'
  printf '      - uses: actions/checkout@v5\n'
  printf '      - name: Validate commit messages, the PR title and the hook copy\n'
  printf '        uses: qoax-community/qoax-githooks@%s # %s\n' "$1" "$2"
}

# consumer NAME [SHA TAG BLOB]: a migrated repository on its origin, at
# v0.1.0 unless the arguments name another release. Its tracked hooks fail
# and leave a mark, so a case can see that none ran. $w is its work tree.
consumer() {
  w="$T/work/$1"
  o="$(origin "$1")"
  rm -rf "$w" "$o"
  git init -q -b main "$w"
  git init -q --bare -b main "$o"
  mkdir -p "$w/.github/workflows" "$w/.githooks"
  workflow "${2:-$sha1}" "${3:-v0.1.0}" >"$w/.github/workflows/commit-conventions.yml"
  git -C "$qg" cat-file blob "${4:-$blob1}" >"$w/.githooks/commit-msg"
  chmod 755 "$w/.githooks/commit-msg"
  for h in pre-commit prepare-commit-msg post-commit pre-merge-commit post-merge \
    post-checkout pre-push; do
    printf '#!/bin/sh\necho "%s ran in %s" >>"%s"\nexit 1\n' "$h" "$1" "$T/ran" \
      >"$w/.githooks/$h"
    chmod 755 "$w/.githooks/$h"
  done
  g "$w" add .github .githooks
  g "$w" commit -q -m 'build: track a copy of the commit-msg hook'
  g "$w" push -q "$o" main
}
bump_branch=dependabot/github_actions/qoax-community/qoax-githooks-0.2.0
bump_title='ci: bump qoax-community/qoax-githooks from 0.1.0 to 0.2.0'
# bump NAME NUMBER: the Dependabot branch and pull request to v0.2.0.
bump() {
  w="$T/work/$1"
  g "$w" switch -q -c "$bump_branch" main
  workflow "$sha2" v0.2.0 >"$w/.github/workflows/commit-conventions.yml"
  g "$w" add .github/workflows/commit-conventions.yml
  g "$w" commit -q -m "$bump_title"
  g "$w" push -q "$(origin "$1")" "$bump_branch"
  g "$w" switch -q main
  printf '%s\t%s\tmain\t%s\n' "$2" "$bump_branch" "$bump_title" >>"$fake/prs/$(key "$1")"
}

# A person's global configuration that runs the tracked hooks of each clone.
# fanout.sh must keep every one of them from running.
printf '[core]\n\thooksPath = .githooks\n' >"$T/hooked.gitconfig"
answer() { printf '%s\n' "$1" >"$T/answer"; }
run() {
  env GIT_CONFIG_GLOBAL="$T/hooked.gitconfig" QOAX_FANOUT_TTY="$T/answer" \
    TMPDIR="$T/tmp" "$test_shell" "$script" "$@"
}
answer n

echo '--- usage ---'
expect 'an unknown argument is a usage error' 2 'unknown argument: --force' run --force
expect '--ref needs a release tag' 2 "--ref needs a release tag vX.Y.Z, not 'main'." \
  run --ref main
expect '--ref needs a value' 2 '--ref needs a release tag vX.Y.Z.' run --ref
expect '--batch needs a number' 2 "--batch needs a number, not 'x'." \
  run --batch x qoax-community/alpha
expect 'a name needs an owner' 2 "'alpha' is not a repository owner/name." run alpha
expect 'a tag that is not there stops the run' 1 "has no tag v9.9.9" \
  run --ref v9.9.9 qoax-community/alpha

echo '--- the list of repositories ---'
printf 'qoax-community/zeta\nqoax-community/qoax-githooks\nqoax-community/alpha\n' \
  >"$fake/lists/qoax-community"
printf 'angel-penchev/servacho-infrastructure\nangel-penchev/other\nangel-penchev/balkanauction-automator\n' \
  >"$fake/lists/angel-penchev"
expect '--list prints the repositories' 0 'qoax-community/alpha' run --list
assert '--list has qoax-community and the listed angel-penchev ones, not qoax-githooks' \
  [ "$out" = 'angel-penchev/balkanauction-automator
angel-penchev/servacho-infrastructure
qoax-community/alpha
qoax-community/zeta' ]

echo '--- a dry run ---'
consumer qoax-community/alpha
bump qoax-community/alpha 12
# Other open pull requests that are not the bump.
printf '3\tdependabot/npm_and_yarn/left-pad-1.3.0\tmain\tchore: bump left-pad\n' \
  >>"$fake/prs/qoax-community_alpha"
printf '4\tfeat/docs\tmain\tdocs: name qoax-community/qoax-githooks\n' \
  >>"$fake/prs/qoax-community_alpha"
consumer qoax-community/beta
bump qoax-community/beta 7
printf 'readme\n' >"$w/README.md"
g "$w" add README.md
g "$w" commit -q -m 'docs: add a readme'
g "$w" push -q "$(origin qoax-community/beta)" main
alpha_tip="$(tip qoax-community/alpha "$bump_branch")"
beta_tip="$(tip qoax-community/beta "$bump_branch")"
beta_main="$(tip qoax-community/beta main)"
tips() {
  printf '%s %s %s\n' "$(tip qoax-community/alpha "$bump_branch")" \
    "$(tip qoax-community/beta "$bump_branch")" "$(tip qoax-community/beta main)"
}
before="$(tips)"

expect 'a dry run plans the sync commit' 0 \
  "PLAN  qoax-community/alpha: #12: push 1 commit to $bump_branch" \
  run qoax-community/alpha qoax-community/beta
has 'the plan names the sync commit' '        chore: sync the commit-msg hook to v0.2.0'
has 'a branch behind main gets a merge first' \
  "PLAN  qoax-community/beta: #7: push 2 commits to $bump_branch"
has 'the plan names the merge' '        chore: merge main into the qoax-githooks bump'
has 'the dry run says that it pushed nothing' 'Dry run: nothing is pushed.'
lacks 'the dry run asks nothing' '[y/N]'
assert 'the dry run pushes nothing' [ "$(tips)" = "$before" ]
expect 'with no name, the run takes the list' 0 'PLAN  qoax-community/alpha: #12' run
has 'the list gives the angel-penchev repositories' \
  'NONE  angel-penchev/servacho-infrastructure: no open Dependabot pull request'
lacks 'the list leaves qoax-githooks out' 'qoax-community/qoax-githooks: '

echo '--- --apply ---'
expect 'without an OK nothing is pushed' 1 'No OK, so nothing of this batch is pushed.' \
  run --apply qoax-community/alpha qoax-community/beta
has 'the question lists both branches' "  qoax-community/beta $bump_branch"
assert 'one batch asks one time' [ "$(questions)" = 1 ]
assert 'a no pushes nothing' [ "$(tips)" = "$before" ]
expect 'without a terminal nothing is pushed' 1 'No terminal to ask on' \
  env QOAX_FANOUT_TTY="$T/no-terminal" GIT_CONFIG_GLOBAL="$T/hooked.gitconfig" \
  TMPDIR="$T/tmp" "$test_shell" "$script" --apply qoax-community/alpha
assert 'no terminal pushes nothing' [ "$(tips)" = "$before" ]

answer y
expect 'an OK pushes the sync commit' 0 \
  "PUSH  qoax-community/alpha: #12: $bump_branch is at" \
  run --apply --batch 1 qoax-community/alpha qoax-community/beta
has 'the branch behind main is pushed too' "PUSH  qoax-community/beta: #7: $bump_branch is at"
assert '--batch 1 asks for each branch' [ "$(questions)" = 2 ]

o="$(origin qoax-community/alpha)"
new="$(tip qoax-community/alpha "$bump_branch")"
assert 'alpha: the old head is the parent of the sync commit' \
  [ "$(git -C "$o" rev-parse "$new^")" = "$alpha_tip" ]
assert 'alpha: the sync commit has its subject' \
  [ "$(git -C "$o" log -1 --format=%s "$new")" = 'chore: sync the commit-msg hook to v0.2.0' ]
assert 'alpha: the sync commit changes only the copy' \
  [ "$(git -C "$o" diff --name-only "$alpha_tip" "$new")" = .githooks/commit-msg ]
assert 'alpha: the copy is the v0.2.0 hook with mode 100755' \
  [ "$(git -C "$o" ls-tree "$new" -- .githooks/commit-msg | cut -f1)" = "100755 blob $blob2" ]

o="$(origin qoax-community/beta)"
new="$(tip qoax-community/beta "$bump_branch")"
assert 'beta: the sync commit has its subject' \
  [ "$(git -C "$o" log -1 --format=%s "$new")" = 'chore: sync the commit-msg hook to v0.2.0' ]
assert 'beta: below it is a merge of the old head and main' \
  [ "$(git -C "$o" rev-list --parents -n 1 "$new^" | cut -d' ' -f2-)" = "$beta_tip $beta_main" ]
assert 'beta: the merge has its subject' \
  [ "$(git -C "$o" log -1 --format=%s "$new^")" = 'chore: merge main into the qoax-githooks bump' ]
assert 'beta: the copy is the v0.2.0 hook with mode 100755' \
  [ "$(git -C "$o" ls-tree "$new" -- .githooks/commit-msg | cut -f1)" = "100755 blob $blob2" ]
assert 'beta: main did not change' [ "$(tip qoax-community/beta main)" = "$beta_main" ]
assert 'no tracked hook ran in a clone' [ ! -e "$T/ran" ]
[ ! -e "$T/ran" ] || sed 's/^/       /' "$T/ran"
clones="$(grep ' repo clone ' "$fake/calls")"
assert 'gh cloned the repositories' [ -n "$clones" ]
assert 'every clone had GIT_LFS_SKIP_SMUDGE=1' \
  [ -z "$(printf '%s\n' "$clones" | grep -v '^lfs=1 ')" ]

echo '--- a second run ---'
before="$(tips)"
expect 'a second run finds the copies in place' 0 \
  'OK    qoax-community/alpha: #12: the copy matches the pin. Nothing to push.' \
  run --apply qoax-community/alpha qoax-community/beta
has 'the second run finds beta in place too' 'OK    qoax-community/beta: #7: the copy matches the pin.'
lacks 'the second run asks nothing' '[y/N]'
assert 'the second run pushes nothing' [ "$(tips)" = "$before" ]

echo '--- repositories that need a person ---'
consumer qoax-community/gamma
cp "$here/fixtures/shim" "$w/.githooks/commit-msg"
g "$w" add .githooks/commit-msg
g "$w" update-index --add \
  --cacheinfo "160000,e70b5fc7643f403eb6991a655cb417e48f9ffad8,.githooks/shared"
g "$w" commit -q -m 'build: the old layout'
g "$w" push -q "$(origin qoax-community/gamma)" main
bump qoax-community/gamma 5
consumer qoax-community/delta
bump qoax-community/delta 9
workflow "$sha1" 'pinned v0.1.0' >"$w/.github/workflows/commit-conventions.yml"
g "$w" add .github/workflows/commit-conventions.yml
g "$w" commit -q -m 'ci: say why the pin stays'
g "$w" push -q "$(origin qoax-community/delta)" main
delta_tip="$(tip qoax-community/delta "$bump_branch")"
printf '1\t%s\tmain\t%s\n2\tdependabot/github_actions/qoax-community/qoax-githooks-0.3.0\tmain\tci: bump qoax-community/qoax-githooks from 0.1.0 to 0.3.0\n' \
  "$bump_branch" "$bump_title" >"$fake/prs/qoax-community_epsilon"
: >"$fake/fail/qoax-community_zeta"
answer y
expect 'a run with problems exits 1' 1 \
  "SKIP  qoax-community/gamma: #5: $bump_branch still has the submodule. Migrate main first." \
  run --apply qoax-community/gamma qoax-community/delta qoax-community/epsilon \
  qoax-community/zeta qoax-community/eta
has 'a merge conflict needs a person' \
  "ATTN  qoax-community/delta: #9: origin/main does not merge into $bump_branch without a conflict."
has 'two bump pull requests need a person' \
  'ATTN  qoax-community/epsilon: more than one open pull request bumps qoax-community/qoax-githooks: #1 #2'
has 'a failed gh call needs a person' \
  'ATTN  qoax-community/zeta: gh pr list failed: HTTP 404: Not Found'
has 'no bump pull request is fine' \
  'NONE  qoax-community/eta: no open Dependabot pull request bumps qoax-community/qoax-githooks'
lacks 'nothing to push asks nothing' '[y/N]'
assert 'the conflict pushes nothing' [ "$(tip qoax-community/delta "$bump_branch")" = "$delta_tip" ]
rm -f "$fake/fail/qoax-community_zeta"

echo '--- --ref ---'
consumer qoax-community/kappa
# A second step with a quoted pin and more words in the comment, and a
# commented line that runs nothing.
printf '      - uses: %sqoax-community/qoax-githooks@%s%s # the hook, v0.1.0\n' \
  "'" "$sha1" "'" >"$T/b.yaml"
printf 'jobs:\n  other:\n    steps:\n' >"$w/.github/workflows/b.yaml"
cat "$T/b.yaml" >>"$w/.github/workflows/b.yaml"
printf '      # uses: qoax-community/qoax-githooks@%s # v0.1.0\n' "$sha1" \
  >>"$w/.github/workflows/commit-conventions.yml"
g "$w" add .github/workflows
g "$w" commit -q -m 'ci: add a second check'
g "$w" push -q "$(origin qoax-community/kappa)" main
kappa_main="$(tip qoax-community/kappa main)"
sync_branch=chore/qoax-githooks-sync

expect '--ref plans a branch of its own' 0 \
  "PLAN  qoax-community/kappa: push 1 commit to $sync_branch, with no pull request yet" \
  run --ref v0.2.0 qoax-community/kappa
has '--ref names the commit' '        chore: bump qoax-githooks to v0.2.0 and sync the commit-msg hook'
assert 'the dry run of --ref pushes no branch' [ -z "$(tip qoax-community/kappa "$sync_branch")" ]

answer y
expect '--ref --apply pushes the branch' 0 \
  "PUSH  qoax-community/kappa: $sync_branch is at" \
  run --apply --ref v0.2.0 qoax-community/kappa
o="$(origin qoax-community/kappa)"
new="$(tip qoax-community/kappa "$sync_branch")"
assert '--ref: one commit on top of main' [ "$(git -C "$o" rev-parse "$new^")" = "$kappa_main" ]
assert '--ref: the commit has the pins and the copy' \
  [ "$(git -C "$o" diff --name-only "$kappa_main" "$new")" = '.githooks/commit-msg
.github/workflows/b.yaml
.github/workflows/commit-conventions.yml' ]
# line FILE TEXT: FILE at the new tip has the line TEXT.
line() { git -C "$o" show "$new:$1" | grep -qxF -- "$2"; }
assert '--ref: the step pins the commit of the tag, with the tag in the comment' \
  line .github/workflows/commit-conventions.yml \
  "        uses: qoax-community/qoax-githooks@$sha2 # v0.2.0"
assert '--ref: a quoted pin keeps its quotes and its words' \
  line .github/workflows/b.yaml \
  "      - uses: 'qoax-community/qoax-githooks@$sha2' # the hook, v0.2.0"
assert '--ref: a commented line stays' \
  line .github/workflows/commit-conventions.yml \
  "      # uses: qoax-community/qoax-githooks@$sha1 # v0.1.0"
assert '--ref: the copy is the v0.2.0 hook with mode 100755' \
  [ "$(git -C "$o" ls-tree "$new" -- .githooks/commit-msg | cut -f1)" = "100755 blob $blob2" ]
assert '--ref: main did not change' [ "$(tip qoax-community/kappa main)" = "$kappa_main" ]

printf '31\n' >"$fake/heads/qoax-community_kappa"
expect 'a second --ref run finds the branch in place' 0 \
  "OK    qoax-community/kappa: $sync_branch already pins v0.2.0 and has its hook, pull request #31." \
  run --apply --ref v0.2.0 qoax-community/kappa
assert 'the second --ref run pushes nothing' [ "$(tip qoax-community/kappa "$sync_branch")" = "$new" ]
lacks 'the second --ref run asks nothing' '[y/N]'

expect 'a hook that rejects the message stops the push' 1 \
  "ATTN  qoax-community/kappa: the new hook rejects 'chore: bump qoax-githooks to v0.3.0 and sync the commit-msg hook'." \
  run --apply --ref v0.3.0 qoax-community/kappa
expect 'a hook that lets a bad message through stops the push' 1 \
  "ATTN  qoax-community/kappa: the new hook does not reject 'bad message'." \
  run --apply --ref v0.4.0 qoax-community/kappa
assert 'the stopped runs push nothing' [ "$(tip qoax-community/kappa "$sync_branch")" = "$new" ]

# A merge restarts the checks of the pull request, so a branch that is in
# place must not get one when main moves.
w="$T/work/qoax-community/kappa"
printf 'readme\n' >"$w/README.md"
g "$w" add README.md
g "$w" commit -q -m 'docs: add a readme'
g "$w" push -q "$o" main
expect 'a --ref run after main moved finds the branch in place' 0 \
  "OK    qoax-community/kappa: $sync_branch already pins v0.2.0 and has its hook, pull request #31." \
  run --apply --ref v0.2.0 qoax-community/kappa
lacks 'the branch in place gets no merge of main' 'chore: merge main'
lacks 'the branch in place asks nothing' '[y/N]'
assert 'the branch in place gets no push' [ "$(tip qoax-community/kappa "$sync_branch")" = "$new" ]
# The hook of v0.3.0 rejects chore, so the ATTN line names the first message
# that the run would push.
expect 'a branch behind main that needs a change still gets the merge' 1 \
  "ATTN  qoax-community/kappa: the new hook rejects 'chore: merge main into the qoax-githooks bump'." \
  run --apply --ref v0.3.0 qoax-community/kappa
assert 'the run that needs a change pushes nothing here' \
  [ "$(tip qoax-community/kappa "$sync_branch")" = "$new" ]

consumer qoax-community/lambda "$sha2" v0.2.0 "$blob2"
consumer qoax-community/plain
g "$w" rm -q -r .github .githooks/commit-msg
g "$w" commit -q -m 'chore: stop using the hook'
g "$w" push -q "$(origin qoax-community/plain)" main
git init -q --bare -b main "$(origin qoax-community/empty)"
expect '--ref skips what it cannot change' 0 \
  'OK    qoax-community/lambda: main already pins v0.2.0 and has its hook. Nothing to push.' \
  run --apply --ref v0.2.0 qoax-community/lambda qoax-community/gamma \
  qoax-community/plain qoax-community/empty
has '--ref skips the old layout' 'SKIP  qoax-community/gamma: main still has the submodule.'
has '--ref skips a repository with no pin and no copy' \
  'SKIP  qoax-community/plain: it does not use qoax-community/qoax-githooks.'
has '--ref skips an empty repository' 'SKIP  qoax-community/empty: the repository is empty.'
assert 'lambda gets no branch' [ -z "$(tip qoax-community/lambda "$sync_branch")" ]

echo '--- after every run ---'
assert 'no tracked hook ran in any clone' [ ! -e "$T/ran" ]
assert 'no temporary folder is left' [ -z "$(ls -A "$T/tmp")" ]
assert 'gh got no write call' \
  [ -z "$(grep -E ' (pr (create|merge|edit|close|comment)|api|release|repo (create|edit|delete))' "$fake/calls")" ]

echo '--- merge-sync-prs.sh, dry run ---'
pr_line() { # NUMBER HEAD OID OWNER BASE TITLE
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}
pr_line 12 "$bump_branch" "$(tip qoax-community/alpha "$bump_branch")" qoax-community main \
  "$bump_title" >"$fake/sync-prs/qoax-community_alpha"
pr_line 3 dependabot/npm_and_yarn/left-pad-1.3.0 "$sha1" qoax-community main \
  'chore: bump left-pad' >>"$fake/sync-prs/qoax-community_alpha"
printf 'pass\nskipping\n' >"$fake/checks/qoax-community_alpha-12"
pr_line 7 "$bump_branch" "$sha1" qoax-community main "$bump_title" \
  >"$fake/sync-prs/qoax-community_beta"
printf 'pass\nfail\n' >"$fake/checks/qoax-community_beta-7"
pr_line 31 "$sync_branch" "$sha2" qoax-community main \
  'chore: bump qoax-githooks to v0.2.0 and sync the commit-msg hook' \
  >"$fake/sync-prs/qoax-community_kappa"
printf 'pass\npending\n' >"$fake/checks/qoax-community_kappa-31"
pr_line 40 "$bump_branch" "$sha2" qoax-community main "$bump_title" \
  >"$fake/sync-prs/qoax-community_lambda"
merge() { env TMPDIR="$T/tmp" "$test_shell" "$merger" "$@"; }
expect 'the dry run lists the green pull request' 0 \
  'green   qoax-community/alpha #12 v0.2.0 into main' \
  merge qoax-community/alpha qoax-community/beta qoax-community/kappa qoax-community/lambda
has 'a failed check is not green' 'failing qoax-community/beta #7 v0.2.0 into main'
has 'the branch of --ref counts, and a running check is not green' \
  'pending qoax-community/kappa #31 v0.2.0 into main'
has 'no checks is not green' 'none    qoax-community/lambda #40 v0.2.0 into main'
lacks 'other pull requests do not count' 'left-pad'
has 'the dry run names the merge subject' \
  "  qoax-community/alpha #12: chore: merge pull request #12 from qoax-community/$bump_branch"
lacks 'the dry run would merge only the green one' '  qoax-community/beta #7: chore: merge'
has 'the dry run merges nothing' 'Dry run: nothing is merged.'
expect 'with no name, merge-sync-prs.sh takes the list of fanout.sh' 0 \
  'green   qoax-community/alpha #12' merge
expect 'an unknown argument is a usage error for merge-sync-prs.sh' 2 \
  'unknown argument: --force' merge --force
assert 'merge-sync-prs.sh merged nothing' [ -z "$(grep ' pr merge ' "$fake/calls")" ]
assert 'merge-sync-prs.sh leaves no temporary folder' [ -z "$(ls -A "$T/tmp")" ]

echo "failures: $fails"
[ "$fails" -eq 0 ]
