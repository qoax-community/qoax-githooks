#!/bin/sh
#
# Cases for scripts/sync-hook.sh. A fixture repository with two releases
# stands in for qoax-githooks, through QOAX_GITHOOKS_URL, so no case needs the
# network. The script runs under TEST_SHELL. Prints "failures: N".
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
test_shell="${TEST_SHELL:-sh}"
script="$root/scripts/sync-hook.sh"

# mktemp -d without a template ignores TMPDIR on macOS. git prints the
# physical path of a work tree, and /var on macOS is a symbolic link.
T="$(mktemp -d "${TMPDIR:-/tmp}/sync.XXXXXX")" && T="$(cd "$T" && pwd -P)" || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

# The fixtures must not see the git configuration of the person who runs the
# tests, or a repository above the temporary folder.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT QOAX_GITHOOKS_URL
mkdir -p "$HOME" "$T/no-hooks" "$T/nowhere"

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

# Two releases. v0.1.0 is a lightweight tag and v0.2.0 an annotated one, as
# the real releases are.
qg="$T/qoax-githooks"
git init -q "$qg"
printf '#!/bin/sh\n# v0.1.0\nexit 0\n' >"$qg/commit-msg"
chmod 755 "$qg/commit-msg"
git -C "$qg" add commit-msg
git -C "$qg" -c core.hooksPath="$T/no-hooks" commit -q -m 'feat: release one'
git -C "$qg" tag v0.1.0
old_sha="$(git -C "$qg" rev-parse HEAD)"
old_blob="$(git -C "$qg" rev-parse HEAD:commit-msg)"
printf '#!/bin/sh\n# v0.2.0\nexit 0\n' >"$qg/commit-msg"
git -C "$qg" add commit-msg
git -C "$qg" -c core.hooksPath="$T/no-hooks" commit -q -m 'feat: release two'
git -C "$qg" tag -a v0.2.0 -m 'v0.2.0: release two'
new_sha="$(git -C "$qg" rev-parse HEAD)"
new_blob="$(git -C "$qg" rev-parse HEAD:commit-msg)"
export QOAX_GITHOOKS_URL="file://$qg"

repo="$T/repo"
copy="$repo/.githooks/commit-msg"
where="$repo"
fresh() {
  rm -rf "$repo" && git init -q "$repo"
  where="$repo"
}
# pin FILE LINE: a workflow whose one step has LINE.
pin() {
  mkdir -p "$repo/.github/workflows"
  printf 'jobs:\n  check:\n    steps:\n%s\n' "$2" >>"$repo/.github/workflows/$1"
  git -C "$repo" add -- ".github/workflows/$1"
}
commit() {
  git -C "$repo" -c core.hooksPath="$T/no-hooks" commit -q --allow-empty \
    -m 'chore: build the fixture'
}
gitlink() {
  git -C "$repo" update-index --add \
    --cacheinfo "160000,e70b5fc7643f403eb6991a655cb417e48f9ffad8,$1"
}
run() { "$test_shell" "$script" "$@"; }
# quiet COMMAND...: run COMMAND in $where, never in the folder of the test.
quiet() { (cd "$where" && "$@") >/dev/null 2>&1; }

# snapshot: what the script must not change. The work tree bytes, the mode,
# the index, the status and the refs.
snapshot() {
  {
    git -C "$repo" ls-files -s
    git -C "$repo" status --porcelain
    git -C "$repo" for-each-ref
    if [ -e "$copy" ] || [ -L "$copy" ]; then
      ls -l "$copy" | cut -c1-10
      git hash-object --no-filters -- "$copy"
    fi
  } 2>&1
}
unchanged() {
  if [ "$(snapshot)" = "$before" ]; then
    pass "$1"
  else
    fail "$1" "$(snapshot)"
  fi
}

# expect NAME WANT_RC WANT_TEXT COMMAND...: run COMMAND in $where. The output
# must hold WANT_TEXT and no shell diagnostic.
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

# lacks NAME TEXT COMMAND...: run COMMAND in $where. The output must not hold
# TEXT.
lacks() {
  name="$1" text="$2"
  shift 2
  out="$(cd "$where" && "$@" 2>&1)"
  case "$out" in
    *"$text"*) fail "$name" "$out" ;;
    *) pass "$name" ;;
  esac
}

# The index entry of the copy: "mode blob".
staged() {
  git -C "$repo" ls-files -s -- .githooks/commit-msg | cut -d' ' -f1,2
}
copy_is() { # BLOB: the index and the work tree hold this hook.
  [ "$(staged)" = "100755 $1" ] && [ -f "$copy" ] && [ ! -L "$copy" ] && [ -x "$copy" ] &&
    [ "$(git hash-object --no-filters -- "$copy")" = "$1" ]
}

echo '--- the pin ---'
fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
commit
refs="$(git -C "$repo" for-each-ref)"
expect 'a sha pin writes the copy' 0 \
  "synced: .githooks/commit-msg is now the commit-msg hook of qoax-githooks $new_sha, the pin in .github/workflows." run
assert 'the copy is the hook with mode 100755' copy_is "$new_blob"
assert 'the refs of the repository do not change' \
  [ "$(git -C "$repo" for-each-ref)" = "$refs" ]
expect 'a second run finds the copy in place' 0 \
  "ok: .githooks/commit-msg is the commit-msg hook of qoax-githooks $new_sha" run
expect '--check passes on the synced copy' 0 'ok: .githooks/commit-msg' run --check

fresh
pin a.yml '      - uses: qoax-community/qoax-githooks@v0.2.0'
commit
expect 'a tag pin writes the copy' 0 'is now the commit-msg hook of qoax-githooks v0.2.0 (' run
assert 'the tag pin gives the hook of the tag' copy_is "$new_blob"

fresh
pin a.yml "      - name: Check
        uses: 'qoax-community/qoax-githooks@$new_sha' # v0.2.0"
commit
expect 'a quoted pin under a name writes the copy' 0 'synced:' run
assert 'the quoted pin gives the hook of the sha' copy_is "$new_blob"

fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
pin b.yaml "      - uses: qoax-community/qoax-githooks@$old_sha # v0.1.0"
commit
before="$(snapshot)"
expect 'pins that disagree fail' 1 'pin qoax-community/qoax-githooks at more than one ref' run
expect 'the error names each pin' 1 ".github/workflows/b.yaml:4: $old_sha" run
unchanged 'pins that disagree write nothing'

fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0
      # - uses: qoax-community/qoax-githooks@$old_sha # v0.1.0
#     uses: qoax-community/qoax-githooks@v0.1.0"
commit
expect 'a commented uses line does not count' 0 'synced:' run
assert 'the copy follows the step, not the comment' copy_is "$new_blob"

fresh
printf 'readme\n' >"$repo/README.md"
git -C "$repo" add README.md
commit
before="$(snapshot)"
expect 'no pin and no --ref fails' 1 'Pass --ref with a tag or a commit sha.' run
unchanged 'no pin writes nothing'
expect '--ref writes that release without a pin' 0 \
  'is now the commit-msg hook of qoax-githooks v0.1.0 (' run --ref v0.1.0
assert '--ref gives the hook of that release' copy_is "$old_blob"
expect '--ref= works too' 0 'qoax-githooks v0.2.0 (' run --ref=v0.2.0
assert '--ref= gives the hook of that release' copy_is "$new_blob"

echo '--- --ref over the pin ---'
fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
commit
expect '--ref wins over the pin' 0 'qoax-githooks v0.1.0 (' run --ref v0.1.0
assert '--ref writes the hook of the ref' copy_is "$old_blob"
expect '--check against the pin finds the older hook' 1 \
  "the index has blob $old_blob, and the hook is blob $new_blob" run --check
expect '--check with a sha --ref passes' 0 'ok:' run --check --ref "$old_sha"

echo '--- --check ---'
fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
commit
before="$(snapshot)"
expect '--check fails with no copy' 1 'the index has no entry at this path' run --check
expect '--check says how to write it' 1 'Run sync-hook.sh without --check to write it.' run --check
unchanged '--check writes nothing'
quiet run
commit

awk '{ printf "%s\r\n", $0 }' "$copy" >"$T/crlf"
cat "$T/crlf" >"$copy"
before="$(snapshot)"
expect '--check catches a CRLF work tree' 1 'the work tree file has CRLF line ends' run --check
expect 'the CRLF error names the LF rule' 1 \
  "Add '/.githooks/** text eol=lf' to .gitattributes and commit it" run --check
unchanged '--check writes nothing for CRLF'
expect 'a sync writes LF over CRLF' 0 'synced:' run
assert 'the work tree has LF again' copy_is "$new_blob"

# Only a rule that the repository commits counts.
mkdir -p "$repo/.git/info"
printf '/.githooks/** text eol=lf\n' >"$repo/.git/info/attributes"
cat "$T/crlf" >"$copy"
expect 'a rule in info/attributes does not count' 1 \
  "Add '/.githooks/** text eol=lf' to .gitattributes" run --check
rm -f "$repo/.git/info/attributes"
printf '/.githooks/** text eol=lf\n' >"$repo/.gitattributes"
expect 'a rule in a .gitattributes that is not committed does not count' 1 \
  "Add '/.githooks/** text eol=lf' to .gitattributes and commit it" run --check
lacks 'a rule that is not committed gets no checkout fix' 'git checkout' run --check
git -C "$repo" add .gitattributes
expect 'a staged rule does not count either' 1 \
  "Add '/.githooks/** text eol=lf' to .gitattributes and commit it" run --check
git -C "$repo" rm -q --cached .gitattributes
rm -f "$repo/.gitattributes"
quiet run

git -C "$repo" update-index --chmod=-x -- .githooks/commit-msg
expect '--check catches mode 100644 in the index' 1 'the index has mode 100644, not 100755' run --check
expect 'a sync stages mode 100755' 0 'synced:' run
assert 'the index has mode 100755 again' copy_is "$new_blob"

chmod 644 "$copy"
expect '--check catches a work tree file that is not executable' 1 \
  'the work tree file is not executable' run --check
quiet run
assert 'a sync makes the work tree file executable' copy_is "$new_blob"

printf '# edited\n' >>"$copy"
expect '--check catches an edit in the work tree' 1 'the work tree file is blob' run --check
quiet run

rm -f "$copy"
ln -s ../README.md "$copy"
expect '--check catches a symbolic link' 1 'the work tree has a symbolic link at this path' run --check
expect 'a sync replaces the symbolic link' 0 'synced:' run
assert 'the copy is a file again' copy_is "$new_blob"

echo '--- --check with the LF rule ---'
rule_fix='cd "$(git rev-parse --show-toplevel)" && rm -f -- .githooks/commit-msg && git checkout -- .githooks/commit-msg'
fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
printf '/.githooks/** text eol=lf\n' >"$repo/.gitattributes"
git -C "$repo" add .gitattributes
quiet run
commit
cat "$T/crlf" >"$copy"
before="$(snapshot)"
expect '--check with the rule catches a CRLF work tree' 1 \
  'the work tree file has CRLF line ends' run --check
expect 'the error says that the file differs from the index' 1 \
  'so the work tree file differs' run --check
expect 'the error names the checkout fix' 1 "$rule_fix" run --check
lacks 'the error does not ask for the rule again' "Add '/.githooks/**" run --check
unchanged '--check writes nothing for CRLF with the rule'
quiet sh -c "$rule_fix"
expect 'the checkout fix gives the hook back' 0 'ok:' run --check

# The fix must work where the script runs, and it runs anywhere in the work
# tree.
mkdir -p "$repo/sub/dir"
where="$repo/sub/dir"
cat "$T/crlf" >"$copy"
expect 'a subdirectory gets the same checkout fix' 1 "$rule_fix" run --check
quiet sh -c "$rule_fix"
expect 'the checkout fix works from a subdirectory' 0 'ok:' run --check
where="$repo"

# A checkout writes CRLF again when info/attributes overrides the rule, so
# the checkout fix would not help.
printf '/.githooks/** text eol=crlf\n' >"$repo/.git/info/attributes"
cat "$T/crlf" >"$copy"
before="$(snapshot)"
expect 'a rule against it in info/attributes is named' 1 \
  'a rule of this clone overrides that' run --check
expect 'the error names the path of info/attributes' 1 '    .git/info/attributes.' run --check
lacks 'a rule against it in info/attributes gets no checkout fix' 'git checkout' run --check
unchanged '--check writes nothing with a rule against it'
expect 'a sync writes LF in spite of the local rule' 0 'synced:' run
expect '--check passes after that sync' 0 'ok:' run --check
rm -f "$repo/.git/info/attributes"

# A clone that git checked out with CRLF before the rule came in. Its stat
# data matches the index, so git checkout alone would skip the file.
fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
quiet run
commit
git -C "$repo" config core.autocrlf true
rm -f "$copy"
quiet git checkout -- .githooks/commit-msg
assert 'the fixture checkout wrote CRLF' grep -q "$(printf '\r')" "$copy"
printf '/.githooks/** text eol=lf\n' >"$repo/.gitattributes"
quiet git add .gitattributes
# git warns here that the CRLF copy would become LF on add. That is the state
# under test.
commit 2>/dev/null
expect 'a CRLF checkout from before the rule gets the checkout fix' 1 "$rule_fix" run --check
quiet sh -c "$rule_fix"
expect 'the checkout fix works after a checkout from before the rule' 0 'ok:' run --check

# The index holds another release, so a checkout would not give the hook.
quiet git config --unset core.autocrlf
quiet run --ref v0.1.0
commit
awk '{ printf "%s\r\n", $0 }' "$copy" >"$T/crlf-old"
cat "$T/crlf-old" >"$copy"
expect 'with another blob in the index the error says a sync writes LF' 1 \
  'so a sync writes it with LF' run --check
lacks 'with another blob in the index the error names no checkout' 'git checkout' \
  run --check

echo '--- where it runs ---'
fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
commit
mkdir -p "$repo/sub/dir"
where="$repo/sub/dir"
expect 'runs from a subdirectory' 0 'synced: .githooks/commit-msg' run
assert 'the copy is at the top of the work tree' copy_is "$new_blob"
where="$repo"

fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
commit
git -C "$repo" worktree add -q --detach "$T/wt"
mkdir -p "$T/wt/sub"
where="$T/wt/sub"
expect 'runs in a linked worktree' 0 'synced: .githooks/commit-msg' run
expect '--check passes in the linked worktree' 0 'ok:' run --check
if [ "$(git -C "$T/wt" ls-files -s -- .githooks/commit-msg | cut -d' ' -f1,2)" = "100755 $new_blob" ] &&
  [ -x "$T/wt/.githooks/commit-msg" ]; then
  pass 'the copy is in the linked worktree'
else
  fail 'the copy is in the linked worktree'
fi
if [ ! -e "$copy" ] && [ -z "$(staged)" ]; then
  pass 'the main work tree does not change'
else
  fail 'the main work tree does not change'
fi
where="$repo"
git -C "$repo" worktree remove --force "$T/wt"

echo '--- refusals ---'
fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
mkdir -p "$repo/.githooks"
cp "$here/fixtures/shim" "$repo/.githooks/commit-msg"
git -C "$repo" add --chmod=+x .githooks/commit-msg
gitlink .githooks/shared
commit
before="$(snapshot)"
expect 'a gitlink under .githooks stops the sync' 1 \
  'A submodule entry is under .githooks: .githooks/shared' run
expect 'the stop names the migrate script' 1 'scripts/migrate-from-submodule.sh' run
expect 'a gitlink under .githooks stops --check' 1 'A submodule entry' run --check
unchanged 'a gitlink means no write'

fresh
pin a.yml "      - uses: qoax-community/qoax-githooks@$new_sha # v0.2.0"
commit
before="$(snapshot)"
expect 'an unreachable URL fails' 1 'Cannot fetch' \
  env QOAX_GITHOOKS_URL="file://$T/missing.git" "$test_shell" "$script"
expect 'a missing tag fails' 1 'Cannot fetch v9.9.9' run --ref v9.9.9
unchanged 'a failed fetch writes nothing'
expect 'an unknown argument is a usage error' 2 'unknown argument: --force' run --force
expect '--ref needs a value' 2 '--ref needs a tag or a commit sha.' run --ref
where="$T/nowhere"
expect 'a folder outside a repository' 2 'Run this script in the work tree' run
where="$repo"

echo "failures: $fails"
[ "$fails" -eq 0 ]
