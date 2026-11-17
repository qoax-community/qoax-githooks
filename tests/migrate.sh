#!/bin/sh
#
# Cases for scripts/migrate-from-submodule.sh. A fixture qoax-githooks with
# the release files of this checkout stands in for the real one, through
# QOAX_GITHOOKS_URL, so no case needs the network. Each case builds a
# repository of the old layout, clones it, and migrates the clone. The script
# runs under TEST_SHELL. Prints "failures: N".
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
test_shell="${TEST_SHELL:-sh}"
script="$root/scripts/migrate-from-submodule.sh"
fixtures="$here/fixtures"
old="$fixtures/v1.0.7"

# mktemp -d without a template ignores TMPDIR on macOS. git prints the
# physical path of a work tree, and /var on macOS is a symbolic link.
T="$(mktemp -d "${TMPDIR:-/tmp}/migrate.XXXXXX")" && T="$(cd "$T" && pwd -P)" || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

# The fixtures must not see the git configuration of the person who runs the
# tests, a repository above the temporary folder, or the Actions variables of
# the CI job.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$T" GIT_LFS_SKIP_SMUDGE=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT QOAX_GITHOOKS_URL \
  COPY STALE_COPY GITHUB_ACTIONS GITHUB_ACTION_PATH GITHUB_WORKSPACE
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

echo '--- the fixtures ---'
# The cases below are worth only as much as these bytes are the bytes that
# the repositories carry.
constant() { sed -n "s/^$1=\\([0-9a-f]*\\)\$/\\1/p" "$script"; }
hash() { git hash-object --no-filters -- "$1"; }
assert 'tests/fixtures/shim is the blob SHIM' \
  [ "$(hash "$fixtures/shim")" = "$(constant SHIM)" ]
assert 'the v1.0.7 setup-hooks.sh is the blob OLD_SETUP_SH' \
  [ "$(hash "$old/setup-hooks.sh")" = "$(constant OLD_SETUP_SH)" ]
assert 'the v1.0.7 install-git-hooks.mjs is the blob OLD_SETUP_MJS' \
  [ "$(hash "$old/install-git-hooks.mjs")" = "$(constant OLD_SETUP_MJS)" ]
assert 'the v1.0.7 workflow is one of OLD_WORKFLOWS' \
  grep -qx "$(hash "$old/commit-conventions.yml")'\{0,1\}" "$script"
assert 'the v1.0.7 dependabot.yml is one of OLD_DEPENDABOTS' \
  grep -qx "\\(OLD_DEPENDABOTS='\\)\\{0,1\\}$(hash "$old/dependabot.yml")" "$script"

# The release: commit-msg, scripts/ and templates/ of this checkout, at the
# tag of the last line of the manifest. v1 floats on the same commit.
qg="$T/qoax-githooks"
git init -q "$qg"
cp "$root/commit-msg" "$qg/commit-msg"
cp -R "$root/scripts" "$root/templates" "$qg/"
git -C "$qg" add -- commit-msg scripts templates
git -C "$qg" -c core.hooksPath="$T/no-hooks" commit -q -m 'feat: the fixture release'
rel="$(awk 'END { print $1 }' "$root/scripts/hook-releases.txt")"
git -C "$qg" tag -a "$rel" -m "$rel: the fixture release"
git -C "$qg" tag v1
rel_sha="$(git -C "$qg" rev-parse HEAD)"
hook_blob="$(git -C "$qg" rev-parse HEAD:commit-msg)"
git -C "$qg" -c core.hooksPath="$T/no-hooks" commit -q --allow-empty -m 'chore: no release'
untagged_sha="$(git -C "$qg" rev-parse HEAD)"
# A release from before the tracked copy has no templates for it.
tree="$(printf '100755 blob %s\tcommit-msg\n' "$hook_blob" | git -C "$qg" mktree)"
git -C "$qg" tag v0.9.0 "$(git -C "$qg" commit-tree "$tree" -m 'feat: an old release')"
export QOAX_GITHOOKS_URL="file://$qg"

sed -e "s/@QOAX_GITHOOKS_SHA@/$rel_sha/" -e "s/@QOAX_GITHOOKS_TAG@/$rel/" \
  "$root/templates/.github/workflows/commit-conventions.yml" >"$T/workflow.yml"
want_workflow="$(hash "$T/workflow.yml")"

origin="$T/origin"
repo="$T/repo"
hooks="$T/hooks"
copy="$repo/.githooks/commit-msg"
add() { git -C "$origin" add -- "$@"; }

# old_layout [sh|mjs|none]: a repository of the old layout, not committed
# yet. The argument picks the setup script. sh is the default.
old_layout() {
  rm -rf "$origin"
  git init -q "$origin"
  mkdir -p "$origin/.githooks" "$origin/.github/workflows"
  cp "$fixtures/shim" "$origin/.githooks/commit-msg"
  chmod 755 "$origin/.githooks/commit-msg"
  git -C "$origin" add --chmod=+x -- .githooks/commit-msg
  printf '[submodule ".githooks/shared"]\n\tpath = .githooks/shared\n\turl = ../qoax-githooks.git\n' \
    >"$origin/.gitmodules"
  git -C "$origin" update-index --add --cacheinfo "160000,$rel_sha,.githooks/shared"
  cp "$old/commit-conventions.yml" "$origin/.github/workflows/commit-conventions.yml"
  cp "$old/dependabot.yml" "$origin/.github/dependabot.yml"
  printf '# Demo\n\nClone it with --recurse-submodules, so the shim finds the hook.\n' \
    >"$origin/README.md"
  add .gitmodules .github README.md
  case "${1-sh}" in
    sh)
      mkdir -p "$origin/scripts"
      cp "$old/setup-hooks.sh" "$origin/scripts/setup-hooks.sh"
      git -C "$origin" add --chmod=+x -- scripts/setup-hooks.sh
      ;;
    mjs)
      mkdir -p "$origin/scripts"
      cp "$old/install-git-hooks.mjs" "$origin/scripts/install-git-hooks.mjs"
      add scripts/install-git-hooks.mjs
      ;;
  esac
}

# clone: commit the old layout, clone it, and point core.hooksPath at a
# folder with only a link to the copy, as the script needs.
clone() {
  git -C "$origin" -c core.hooksPath="$T/no-hooks" commit -q -m 'chore: build the fixture'
  rm -rf "$repo" "$hooks"
  git clone -q "file://$origin" "$repo"
  git -C "$repo" checkout -q -b build/commit-msg-copy
  mkdir "$hooks"
  ln -s "$copy" "$hooks/commit-msg"
  git -C "$repo" config core.hooksPath "$hooks"
  where="$repo"
  start="$(git -C "$repo" rev-parse HEAD)"
}

raw() { "$test_shell" "$script" "$@"; }
migrate() { raw --ref "$rel"; }

head_is() { [ "$(git -C "$repo" rev-parse HEAD)" = "$1" ]; }
clean() { [ -z "$(git -C "$repo" status --porcelain)" ]; }
untouched() { head_is "$start" && clean; }
# subjects: the subjects of the commits since the clone, oldest first.
subjects() { git -C "$repo" log --reverse --format=%s "$start..HEAD"; }
subjects_are() {
  want="$(printf '%s\n' "$@")"
  [ "$(subjects)" = "$want" ]
}
entry_of() { git -C "$repo" ls-files -s -- "$1" | cut -d' ' -f1,2; }
blob() { git -C "$repo" rev-parse -q --verify "HEAD:$1"; }
same() { cmp -s "$1" "$2"; }
no_submodule() {
  [ -z "$(git -C "$repo" ls-files -s | awk '$1 == "160000"')" ] &&
    [ -z "$(entry_of .gitmodules)" ]
}
build='build: track a copy of the commit-msg hook'
pin_ci='ci: pin the qoax-githooks commit check'
bump_ci='ci: let Dependabot bump the qoax-githooks pin'

echo '--- inputs ---'
old_layout
clone
expect 'no --ref is a usage error' 2 'pass --ref with a release tag' raw
expect 'an unknown argument is a usage error' 2 'unknown argument: --force' raw --force
where="$T/nowhere"
expect 'a folder outside a repository' 2 'run this script in the work tree' migrate
where="$repo"
expect 'a tag that does not exist' 1 'has no tag v9.9.9' raw --ref v9.9.9
expect 'a sha with no release tag' 1 "No release tag vX.Y.Z at $QOAX_GITHOOKS_URL points at $untagged_sha" \
  raw --ref "$untagged_sha"
expect 'a release from before the tracked copy' 1 'It is older than the tracked copy.' \
  raw --ref v0.9.0
assert 'the failed runs change nothing' untouched

echo '--- core.hooksPath ---'
git -C "$repo" config --unset core.hooksPath
expect 'core.hooksPath unset' 1 "It is 'unset'." migrate
git -C "$repo" config core.hooksPath .githooks
expect 'core.hooksPath at .githooks' 1 'must point at a folder that holds only commit-msg' migrate
git -C "$repo" config core.hooksPath "$hooks"
rm "$hooks/commit-msg"
cp "$copy" "$hooks/commit-msg"
expect 'a copy of the shim, not a link to it' 1 "symbolic link to .githooks/commit-msg" migrate
rm "$hooks/commit-msg"
ln -s "$copy" "$hooks/commit-msg"
printf '#!/bin/sh\n' >"$hooks/pre-commit"
expect 'a second hook in the folder' 1 'holds only commit-msg' migrate
rm "$hooks/pre-commit"
printf 'more\n' >>"$repo/README.md"
expect 'a change in the work tree' 1 'The work tree or the index has changes.' migrate
git -C "$repo" checkout -q -- README.md
assert 'the stopped runs change nothing' untouched

echo '--- scripts/setup-hooks.sh, the common case ---'
expect 'the migration passes' 0 'The self-test passed. Nothing is pushed.' migrate
assert 'three commits, in order' subjects_are "$build" "$pin_ci" "$bump_ci"
assert 'the copy is the hook with mode 100755' [ "$(entry_of .githooks/commit-msg)" = "100755 $hook_blob" ]
assert 'no gitlink and no .gitmodules' no_submodule
assert '.githooks/.gitignore is the snippet' same "$repo/.githooks/.gitignore" "$root/templates/gitignore"
assert '.gitattributes is the snippet' same "$repo/.gitattributes" "$root/templates/gitattributes"
assert 'scripts/setup-hooks.sh is the new template' \
  same "$repo/scripts/setup-hooks.sh" "$root/templates/posix/setup-hooks.sh"
assert 'scripts/setup-hooks.sh keeps mode 100755' \
  [ "$(entry_of scripts/setup-hooks.sh | cut -d' ' -f1)" = 100755 ]
assert 'the workflow is the template with the pin' \
  [ "$(blob .github/workflows/commit-conventions.yml)" = "$want_workflow" ]
assert 'dependabot.yml is the template' \
  same "$repo/.github/dependabot.yml" "$root/templates/.github/dependabot.yml"
assert 'git status is clean' clean
has 'check-copy.sh passes' "ok: .githooks/commit-msg is the commit-msg hook of qoax-githooks $rel."
has 'the hook rejects a bad message' "ok: the hook rejects 'bad message'."
has 'the hook accepts a good message' "ok: the hook accepts 'chore: test the hook'."
has 'sync-hook.sh --check passes' "the pin in .github/workflows."
has 'it prints the diff' 'scripts/setup-hooks.sh'
has 'it names the README line for a hand edit' 'README.md:3:'
lacks 'the new template is not a setup script of its own' 'is not the template of'
lacks 'the diff leaves out the body of the hook' '+readonly SPEC_URL='

head="$(git -C "$repo" rev-parse HEAD)"
expect 'a second run passes' 0 'This run made no commit. The repository is already migrated.' migrate
assert 'a second run changes nothing' head_is "$head"
assert 'a second run leaves git status clean' clean
expect 'a run with the sha of the release changes nothing' 0 'This run made no commit.' \
  raw --ref "$rel_sha"
expect 'v1 names the release tag of its commit' 0 "Migrating to qoax-githooks $rel (" raw --ref v1
assert 'the runs with other refs change nothing' head_is "$head"

printf 'notes\n' >"$repo/notes.txt"
expect 'an untracked file fails the self-test' 1 'git status is not clean.' migrate
has 'the stop names the self-test' 'The self-test failed.'
rm -f "$repo/notes.txt"

printf '#!/bin/sh\n# another hook\nexit 0\n' >"$copy"
git -C "$repo" -c core.hooksPath="$T/no-hooks" commit -q -am 'chore: change the copy'
expect 'a copy of another hook stops it' 1 'The repository has moved already.' migrate
has 'the stop names sync-hook.sh' 'scripts/sync-hook.sh of qoax-githooks'

echo '--- --ref as a sha ---'
old_layout
clone
expect 'the migration passes with a sha' 0 'The self-test passed.' raw --ref "$rel_sha"
assert 'the workflow names the sha and the release tag' \
  [ "$(blob .github/workflows/commit-conventions.yml)" = "$want_workflow" ]

echo '--- scripts/install-git-hooks.mjs ---'
old_layout mjs
printf '*.png binary' >"$origin/.gitattributes"
add .gitattributes
clone
expect 'the migration passes' 0 'The self-test passed.' migrate
assert 'scripts/install-git-hooks.mjs is the new template' \
  same "$repo/scripts/install-git-hooks.mjs" "$root/templates/npm/install-git-hooks.mjs"
printf '*.png binary\n/.githooks/** text eol=lf\n' >"$T/want"
assert 'the LF rule goes on a line of its own' same "$repo/.gitattributes" "$T/want"

echo '--- setup.cmd, and no scripts/ folder ---'
for ends in lf crlf; do
  old_layout none
  printf '%s\n' '@echo off' 'cd /d "%~dp0" || exit /b 1' '' \
    'git submodule update --init .githooks/shared || exit /b 1' \
    'git config core.hooksPath .githooks || exit /b 1' \
    'git lfs install --local || exit /b 1' >"$T/setup.cmd"
  printf '%s\n' '@echo off' 'cd /d "%~dp0" || exit /b 1' '' \
    'git config core.hooksPath .githooks || exit /b 1' \
    'git lfs install --local || exit /b 1' >"$T/want"
  if [ "$ends" = crlf ]; then
    for f in setup.cmd want; do
      awk '{ printf "%s\r\n", $0 }' "$T/$f" >"$T/$f.crlf" && mv "$T/$f.crlf" "$T/$f"
    done
  fi
  cp "$T/setup.cmd" "$origin/setup.cmd"
  printf '.githooks/*        text eol=lf\n*.png filter=lfs diff=lfs merge=lfs -text\n' \
    >"$origin/.gitattributes"
  add setup.cmd .gitattributes
  attributes="$(git -C "$origin" hash-object .gitattributes)"
  clone
  expect "the migration passes ($ends)" 0 'The self-test passed.' migrate
  assert "setup.cmd loses only the submodule line ($ends)" same "$repo/setup.cmd" "$T/want"
  assert "an LF rule that matches stays as it is ($ends)" [ "$(blob .gitattributes)" = "$attributes" ]
  assert "no scripts/ folder appears ($ends)" [ ! -e "$repo/scripts" ]
done

echo '--- lefthook, and a Dependabot file to edit by hand ---'
old_layout none
printf 'commit-msg:\n  jobs:\n    - name: conventional-commits\n      run: .githooks/commit-msg {1}\n' \
  >"$origin/lefthook.yml"
printf '{\n  "scripts": {\n    "bootstrap": "git submodule update --init --recursive && pnpm install"\n  }\n}\n' \
  >"$origin/package.json"
printf 'version: 2\nupdates:\n  - package-ecosystem: gitsubmodule\n    directory: /\n    schedule:\n      interval: weekly\n  - package-ecosystem: github-actions\n    directory: /\n    schedule:\n      interval: weekly\n' \
  >"$origin/.github/dependabot.yml"
add lefthook.yml package.json .github/dependabot.yml
lefthook="$(git -C "$origin" hash-object lefthook.yml)"
dependabot="$(git -C "$origin" hash-object .github/dependabot.yml)"
clone
expect 'an unknown dependabot.yml stops it' 1 \
  "$bump_ci" migrate
has 'the stop names the file and its blob' ".github/dependabot.yml, blob $dependabot"
has 'the stop says how to go on' "Then run this script again with --ref $rel."
assert 'the commits before the stop are there' subjects_are "$build" "$pin_ci"
assert 'the stop leaves git status clean' clean
# try NAME RC: commit the dependabot.yml of the work tree, run the script, and
# drop the commit again.
try() {
  git -C "$repo" commit -q -am 'ci: try a Dependabot entry'
  if [ "$2" = 0 ]; then
    expect "$1" 0 'The self-test passed.' migrate
  else
    expect "$1" 1 "$bump_ci" migrate
    has "$1: the stop names the rule" 'No ignore of'
  fi
  git -C "$repo" reset -q --hard HEAD~1
}
printf 'version: 2\nupdates:\n  - package-ecosystem: github-actions\n    directory: /\n    ignore:\n      - dependency-name: qoax-community/qoax-githooks\n        versions: ["2.x"]\n' \
  >"$repo/.github/dependabot.yml"
try 'an ignore of the pin stops it' 1
printf 'version: 2\nupdates:\n  - package-ecosystem: github-actions\n    ignore: [{dependency-name: "qoax-community/*"}]\n' \
  >"$repo/.github/dependabot.yml"
try 'an ignore with a wildcard, on one line, stops it' 1
printf 'version: 2\nupdates:\n- package-ecosystem: github-actions\n  allow:\n  - dependency-name: actions/checkout\n' \
  >"$repo/.github/dependabot.yml"
try 'an allow list without the pin stops it' 1
printf 'version: 2\nupdates:\n- package-ecosystem: npm\n  directory: /\n  ignore:\n  - dependency-name: qoax-community/qoax-githooks\n- package-ecosystem: "github-actions" # the pin\n  directory: /\n  allow:\n  - dependency-name: "qoax-community/*"\n' \
  >"$repo/.github/dependabot.yml"
try 'an allow list with the pin passes' 0
printf 'version: 2\nupdates:\n  - package-ecosystem: github-actions\n    directory: /\n    schedule:\n      interval: weekly\n' \
  >"$repo/.github/dependabot.yml"
git -C "$repo" commit -q -am "$bump_ci"
expect 'the run after the hand edit passes' 0 'The self-test passed.' migrate
has 'lefthook keeps running the copy' 'lefthook.yml runs .githooks/commit-msg.'
has 'package.json is a line to check' 'package.json:3:'
assert 'lefthook.yml does not change' [ "$(blob lefthook.yml)" = "$lefthook" ]
assert 'the hand edit stays' subjects_are "$build" "$pin_ci" "$bump_ci"

echo '--- a workflow to edit by hand ---'
old_layout
printf 'name: Commits\non: [pull_request]\njobs:\n  commits:\n    uses: qoax-community/qoax-reusables/.github/workflows/commit-conventions.yml@main\n' \
  >"$origin/.github/workflows/commit-conventions.yml"
add .github/workflows/commit-conventions.yml
clone
expect 'an unknown workflow stops it' 1 "uses: qoax-community/qoax-githooks@$rel_sha # $rel" migrate
assert 'only the first commit is there' subjects_are "$build"
printf 'name: Commits\non: [pull_request]\njobs:\n  commits:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v5\n        with:\n          fetch-depth: 0\n      - uses: qoax-community/qoax-githooks@%s\n' \
  "$rel_sha" >"$repo/.github/workflows/commit-conventions.yml"
git -C "$repo" commit -q -am "$pin_ci"
expect 'a pin without the release in its comment is not done' 1 \
  '.github/workflows/commit-conventions.yml, blob' migrate
printf 'name: Commits\non: [pull_request]\njobs:\n  commits:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v5\n        with:\n          fetch-depth: 0\n      - uses: qoax-community/qoax-githooks@%s # %s\n' \
  "$rel_sha" "$rel" >"$repo/.github/workflows/commit-conventions.yml"
git -C "$repo" commit -q -am 'ci: name the release of the pin'
expect 'the run after the hand edit passes' 0 'The self-test passed.' migrate
assert 'the run after the hand edit replaces dependabot.yml' \
  same "$repo/.github/dependabot.yml" "$root/templates/.github/dependabot.yml"

echo '--- other tracked hooks ---'
old_layout
printf '#!/bin/sh\necho "the pre-commit hook ran" >&2\nexit 1\n' >"$origin/.githooks/pre-commit"
git -C "$origin" add --chmod=+x -- .githooks/pre-commit
clone
expect 'a tracked pre-commit that fails does not stop it' 0 'The self-test passed.' migrate
lacks 'the tracked pre-commit does not run' 'the pre-commit hook ran'

# no_lfs_path: PATH, with each folder that has git-lfs replaced by links to
# its other files. The runners of GitHub Actions have git-lfs in /usr/bin.
no_lfs_path() {
  result=''
  saved_ifs="$IFS"
  IFS=:
  for dir in $PATH; do
    IFS="$saved_ifs"
    if [ -n "$dir" ] && [ -e "$dir/git-lfs" ]; then
      shadow="$T/shadow/$(printf '%s' "$dir" | tr '/' '_')"
      mkdir -p "$shadow"
      for f in "$dir"/*; do
        [ "${f##*/}" = git-lfs ] || ln -s "$f" "$shadow/${f##*/}"
      done
      dir="$shadow"
    fi
    result="${result:+$result:}$dir"
  done
  IFS="$saved_ifs"
  printf '%s' "$result"
}
lfs_stub() {
  cat >"$origin/.githooks/$1" <<EOF
#!/bin/sh
command -v git-lfs >/dev/null 2>&1 || { printf >&2 "\\nThis repository is configured for Git LFS but 'git-lfs' was not found on your path.\\n"; exit 2; }
git lfs $1 "\$@"
EOF
  git -C "$origin" add --chmod=+x -- ".githooks/$1"
}
old_layout
for h in pre-push post-checkout post-commit post-merge; do
  lfs_stub "$h"
done
clone
no_lfs="$(no_lfs_path)"
if (PATH="$no_lfs" && export PATH && ! command -v git-lfs >/dev/null 2>&1); then
  pass 'git-lfs is not on the PATH of the next case'
else
  fail 'git-lfs is not on the PATH of the next case'
fi
expect 'the Git LFS stubs with no git-lfs do not stop it' 0 'The self-test passed.' \
  env PATH="$no_lfs" "$test_shell" "$script" --ref "$rel"
lacks 'the Git LFS stubs do not run' 'configured for Git LFS'
expect 'the stubs fail when they run' 0 'configured for Git LFS' \
  env PATH="$no_lfs" git -c core.hooksPath=.githooks commit -q --allow-empty -m 'chore: run the stubs'

echo '--- a setup script of its own ---'
old_layout none
mkdir -p "$origin/scripts"
printf '#!/bin/sh\n[ -e .githooks/shared/commit-msg ] || exit 1\ngit config core.hooksPath .githooks\n' \
  >"$origin/scripts/setup-hooks.sh"
add scripts/setup-hooks.sh
setup="$(git -C "$origin" hash-object scripts/setup-hooks.sh)"
clone
expect 'a setup script with no submodule step stays' 0 'The self-test passed.' migrate
assert 'the setup script of its own does not change' [ "$(blob scripts/setup-hooks.sh)" = "$setup" ]
has 'its line that names .githooks/shared is in the list' 'scripts/setup-hooks.sh:2:'
has 'the output says that it stays' 'scripts/setup-hooks.sh is not the template of qoax-githooks'

echo '--- info/attributes of the clone does not count ---'
old_layout
clone
info="$(git -C "$repo" rev-parse --absolute-git-dir)/info"
mkdir -p "$info"
printf '/.githooks/** text eol=lf\n' >>"$info/attributes"
expect 'a rule only in info/attributes' 0 'The self-test passed.' migrate
assert 'the LF rule goes into .gitattributes' same "$repo/.gitattributes" "$root/templates/gitattributes"
git -C "$repo" rm -q .gitattributes
git -C "$repo" commit -q -m 'chore: drop the attributes'
expect 'a migrated repository with no rule' 1 'No rule in .gitattributes gives' migrate

echo '--- unknown blobs stop it before any change ---'
old_layout
printf '# a local change\n' >>"$origin/.githooks/commit-msg"
add .githooks/commit-msg
clone
expect 'an edited shim' 1 "not the shim (blob $(constant SHIM))" migrate
assert 'an edited shim changes nothing' untouched

old_layout
printf '# a local change\n' >>"$origin/scripts/setup-hooks.sh"
add scripts/setup-hooks.sh
clone
expect 'an edited setup-hooks.sh' 1 'which this script does not know, and it runs git submodule' migrate
has 'the stop names the file' 'scripts/setup-hooks.sh is blob'
assert 'an edited setup-hooks.sh changes nothing' untouched

old_layout mjs
printf '// a local change\n' >>"$origin/scripts/install-git-hooks.mjs"
add scripts/install-git-hooks.mjs
clone
expect 'an edited install-git-hooks.mjs' 1 'scripts/install-git-hooks.mjs is blob' migrate
assert 'an edited install-git-hooks.mjs changes nothing' untouched

old_layout none
printf '@echo off\ngit submodule update --init --recursive || exit /b 1\n' >"$origin/setup.cmd"
add setup.cmd
clone
expect 'a setup.cmd with another submodule line' 1 'setup.cmd runs git submodule in a way' migrate
assert 'that setup.cmd changes nothing' untouched

old_layout
printf '[submodule "vendor/lib"]\n\tpath = vendor/lib\n\turl = ../lib.git\n' >>"$origin/.gitmodules"
git -C "$origin" update-index --add --cacheinfo "160000,$rel_sha,vendor/lib"
add .gitmodules
clone
expect 'a second submodule' 1 'More submodules than .githooks/shared' migrate
has 'the stop lists .gitmodules too' '.gitmodules must name exactly one submodule'
has 'the stop asks for a move by hand' 'Move this repository fully by hand.'
lacks 'the stop does not ask for a part of the move' '.gitmodules must keep the others'
assert 'a second submodule changes nothing' untouched
git -C "$repo" rm -q .githooks/shared
cp "$root/commit-msg" "$copy"
git -C "$repo" add --chmod=+x -- .githooks/commit-msg
git -C "$repo" add -- .gitmodules
git -C "$repo" commit -q -m "$build"
expect 'a run after a part of the move' 1 \
  'This script cannot finish a repository that keeps other submodules.' migrate
has 'the stop names the other submodule' '.gitmodules names other submodules: vendor/lib'

echo '--- not the old layout ---'
rm -rf "$origin"
git init -q "$origin"
printf 'readme\n' >"$origin/README.md"
add README.md
clone
expect 'a repository with no shim and no copy' 1 'There is no .githooks/commit-msg here' migrate

echo "failures: $fails"
[ "$fails" -eq 0 ]
