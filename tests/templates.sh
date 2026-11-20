#!/bin/sh
#
# Cases for the files in templates/. The POSIX setup script runs under
# TEST_SHELL, the npm one under node. Each case runs in a new repository.
# Prints "failures: N".
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
test_shell="${TEST_SHELL:-sh}"
templates="$root/templates"
posix="$templates/posix/setup-hooks.sh"
npm="$templates/npm/install-git-hooks.mjs"
workflow="$templates/.github/workflows/commit-conventions.yml"
dependabot="$templates/.github/dependabot.yml"

# mktemp -d without a template ignores TMPDIR on macOS. git prints the
# physical path of a work tree, and the temporary folder can sit behind a
# symbolic link, as /var does on macOS.
T="$(mktemp -d "${TMPDIR:-/tmp}/templates.XXXXXX")" && T="$(cd "$T" && pwd -P)" || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

# The fixtures must not see the git configuration of the person who runs the
# tests, or a repository above the temporary folder.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
mkdir -p "$HOME" "$T/bin" "$T/nowhere"

# A git that logs each call, so the last case can show that no setup script
# runs git submodule. node finds it on PATH too.
real_git="$(command -v git)"
cat >"$T/bin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$T/git.log'
exec '$real_git' "\$@"
EOF
chmod 755 "$T/bin/git"
PATH="$T/bin:$PATH"
export PATH

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf 'FAIL %s\n' "$1"
  [ -n "${2-}" ] && printf '%s\n' "$2" | sed 's/^/       /'
  return 0
}

repo="$T/repo"
where="$repo"
fresh() {
  rm -rf "$repo" && git init -q "$repo"
  where="$repo"
}

# check NAME KIND WANT_RC WANT_TEXT WANT_HOOKS_PATH: run the setup script of
# KIND (posix or npm) in $where. An empty WANT_TEXT wants no output, and a
# leading ! wants the text absent. WANT_HOOKS_PATH - wants core.hooksPath
# unset.
check() {
  name="$1 ($2)" kind="$2" want_rc="$3" text="$4" want_path="$5"
  if [ "$kind" = posix ]; then
    out="$(cd "$where" && "$test_shell" "$posix" 2>&1)"
  else
    out="$(cd "$where" && node "$npm" 2>&1)"
  fi
  rc=$?
  path="$(git -C "$repo" config --get core.hooksPath)" || path=-
  problem=''
  [ "$rc" = "$want_rc" ] || problem="rc $rc, want $want_rc"
  case "$text" in
    '') [ -z "$out" ] || problem="$problem output is not empty" ;;
    !*)
      case "$out" in
        *"${text#!}"*) problem="$problem \"${text#!}\" is in the output" ;;
      esac
      ;;
    *)
      case "$out" in
        *"$text"*) ;;
        *) problem="$problem no \"$text\"" ;;
      esac
      ;;
  esac
  [ "$path" = "$want_path" ] ||
    problem="$problem core.hooksPath is '$path', want '$want_path'"
  case "$out" in
    *'unbound variable'* | *'parameter not set'* | *': not found'* | \
      *'command not found'* | *'yntax error'* | *'Error: '*)
      problem="$problem shell or node diagnostic"
      ;;
  esac
  if [ -n "$problem" ]; then
    fail "$name ($problem )" "$out"
  else
    pass "$name"
  fi
}

# leftover: a checkout of the old submodule, as a pull leaves it.
leftover() {
  mkdir -p "$repo/.githooks/shared"
  printf 'gitdir: ../../.git/modules/.githooks/shared\n' >"$repo/.githooks/shared/.git"
  printf '#!/bin/sh\n' >"$repo/.githooks/shared/commit-msg"
}

kinds=posix
if command -v node >/dev/null 2>&1; then
  kinds='posix npm'
else
  fail 'node is installed, so the npm script can run'
fi

for kind in $kinds; do
  echo "--- the $kind setup script ---"
  fresh
  check 'sets core.hooksPath when it is unset' "$kind" 0 \
    'commit message validation enabled (core.hooksPath = .githooks)' .githooks
  check 'is quiet when core.hooksPath is .githooks' "$kind" 0 '' .githooks

  fresh
  git -C "$repo" config core.hooksPath custom/hooks
  check 'leaves another value alone' "$kind" 0 \
    'core.hooksPath is set to "custom/hooks", leaving it alone' custom/hooks
  check 'names the command that turns it on' "$kind" 0 \
    'Run `git config core.hooksPath .githooks` to turn it on' custom/hooks

  fresh
  git -C "$repo" config core.hooksPath ''
  check 'leaves an empty value alone' "$kind" 0 \
    'core.hooksPath is set to an empty value' ''

  fresh
  mkdir -p "$repo/sub/dir"
  where="$repo/sub/dir"
  check 'runs from a subdirectory' "$kind" 0 'validation enabled' .githooks

  fresh
  leftover
  git -C "$repo" config core.hooksPath .githooks
  check 'prints the clean-up for a leftover checkout' "$kind" 0 \
    'rm -rf .githooks/shared "$(git rev-parse --git-dir)/modules/.githooks"' .githooks
  check 'names the folder of the clean-up' "$kind" 0 "run these lines in $repo:" .githooks
  if [ -f "$repo/.githooks/shared/commit-msg" ] && [ -f "$repo/.githooks/shared/.git" ]; then
    pass "deletes nothing ($kind)"
  else
    fail "deletes nothing ($kind)"
  fi
  mkdir -p "$repo/sub"
  where="$repo/sub"
  check 'finds a leftover checkout from a subdirectory' "$kind" 0 'leftover checkout' .githooks

  fresh
  leftover
  git -C "$repo" update-index --add \
    --cacheinfo "160000,e70b5fc7643f403eb6991a655cb417e48f9ffad8,.githooks/shared"
  check 'is quiet about a submodule that is still tracked' "$kind" 0 '!leftover' .githooks

  fresh
  rm -rf "$repo/.git"
  check 'skips a folder outside a work tree' "$kind" 0 '' -
done

echo '--- git submodule ---'
if [ ! -s "$T/git.log" ]; then
  fail 'the setup scripts called git through the logging wrapper'
elif grep -nE '(^| )submodule( |$)' "$T/git.log" >"$T/submodule.log"; then
  fail 'no setup script calls git submodule' "$(cat "$T/submodule.log")"
else
  pass 'no setup script calls git submodule'
fi
if grep -rnE 'git +submodule +(add|update|init|sync|foreach|deinit)' "$templates" \
  >"$T/grep.log"; then
  fail 'no template runs git submodule' "$(cat "$T/grep.log")"
else
  pass 'no template runs git submodule'
fi
if [ ! -e "$templates/.githooks/commit-msg" ] && [ ! -e "$templates/.gitmodules" ]; then
  pass 'the shim and .gitmodules templates are gone'
else
  fail 'the shim and .gitmodules templates are gone'
fi

echo '--- the workflow template ---'
for placeholder in @QOAX_GITHOOKS_SHA@ @QOAX_GITHOOKS_TAG@; do
  count="$(grep -c "$placeholder" "$workflow")"
  if [ "$count" = 1 ]; then
    pass "$placeholder is in one line"
  else
    fail "$placeholder is in one line (in $count)"
  fi
done
sha=0123456789abcdef0123456789abcdef01234567
sed -e "s/@QOAX_GITHOOKS_SHA@/$sha/" -e 's/@QOAX_GITHOOKS_TAG@/v1.2.3/' \
  "$workflow" >"$T/workflow.yml"
if grep -qxE " +uses: qoax-community/qoax-githooks@$sha # v1\\.2\\.3" "$T/workflow.yml"; then
  pass 'the rendered pin is a sha, with the release as the last token'
else
  fail 'the rendered pin is a sha, with the release as the last token' \
    "$(grep -n 'qoax-githooks@' "$T/workflow.yml")"
fi
if grep -q '@QOAX_GITHOOKS_' "$T/workflow.yml"; then
  fail 'no placeholder is left after the render'
else
  pass 'no placeholder is left after the render'
fi
for line in '  commit-conventions:' '    name: Conventional Commits' \
  '          fetch-depth: 0' '    types: [opened, synchronize, reopened, edited]'; do
  if grep -qxF "$line" "$workflow"; then
    pass "the workflow has the line '$line'"
  else
    fail "the workflow has the line '$line'"
  fi
done
if grep -q 'qoax-reusables' "$workflow"; then
  fail 'the workflow does not call qoax-reusables'
else
  pass 'the workflow does not call qoax-reusables'
fi

echo '--- the Dependabot template ---'
for line in '  - package-ecosystem: github-actions' '      prefix: ci' \
  '      - dependency-name: qoax-community/qoax-githooks'; do
  if grep -qxF "$line" "$dependabot"; then
    pass "dependabot.yml has the line '$line'"
  else
    fail "dependabot.yml has the line '$line'"
  fi
done
if grep -q gitsubmodule "$dependabot"; then
  fail 'dependabot.yml has no gitsubmodule entry'
else
  pass 'dependabot.yml has no gitsubmodule entry'
fi

echo '--- the snippets ---'
printf '/shared/\n' >"$T/want-gitignore"
printf '/.githooks/** text eol=lf\n' >"$T/want-gitattributes"
for name in gitignore gitattributes; do
  if cmp -s "$T/want-$name" "$templates/$name"; then
    pass "templates/$name is the one line"
  else
    fail "templates/$name is the one line" "$(cat "$templates/$name")"
  fi
done

fresh
mkdir -p "$repo/.githooks"
cp "$templates/gitignore" "$repo/.githooks/.gitignore"
cp "$templates/gitattributes" "$repo/.gitattributes"
if git -C "$repo" check-ignore -q .githooks/shared/commit-msg &&
  ! git -C "$repo" check-ignore -q .githooks/commit-msg; then
  pass 'the gitignore hides .githooks/shared and not the copy'
else
  fail 'the gitignore hides .githooks/shared and not the copy'
fi
attrs="$(git -C "$repo" check-attr text eol -- .githooks/commit-msg)"
case "$attrs" in
  *'text: set'*'eol: lf'*) pass 'the gitattributes rule gives the copy eol=lf' ;;
  *) fail 'the gitattributes rule gives the copy eol=lf' "$attrs" ;;
esac

# Git for Windows sets core.autocrlf=true by default. Without the rule, a
# checkout writes the setup script with CRLF, and sh cannot run it.
printf '/scripts/setup-hooks.sh text eol=lf\n' >"$T/want-posix-gitattributes"
if cmp -s "$T/want-posix-gitattributes" "$templates/posix/gitattributes"; then
  pass 'templates/posix/gitattributes is the one line'
else
  fail 'templates/posix/gitattributes is the one line' "$(cat "$templates/posix/gitattributes")"
fi
fresh
mkdir -p "$repo/scripts"
cp "$posix" "$repo/scripts/setup-hooks.sh"
git -C "$repo" add scripts/setup-hooks.sh
git -C "$repo" commit -q --no-verify -m 'build: add the setup script'
rm -rf "$T/crlf"
git clone -q -c core.autocrlf=true "$repo" "$T/crlf"
if grep -q "$(printf '\r')" "$T/crlf/scripts/setup-hooks.sh"; then
  pass 'with no rule, core.autocrlf=true writes the setup script with CRLF'
else
  fail 'with no rule, core.autocrlf=true writes the setup script with CRLF'
fi
cp "$templates/posix/gitattributes" "$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -q --no-verify -m 'build: keep the setup script at LF'
rm -rf "$T/crlf"
git clone -q -c core.autocrlf=true "$repo" "$T/crlf"
if grep -q "$(printf '\r')" "$T/crlf/scripts/setup-hooks.sh"; then
  fail 'with the rule, core.autocrlf=true writes the setup script with LF'
else
  pass 'with the rule, core.autocrlf=true writes the setup script with LF'
fi
if (cd "$T/crlf" && "$test_shell" scripts/setup-hooks.sh >/dev/null 2>&1) &&
  [ "$(git -C "$T/crlf" config --get core.hooksPath)" = .githooks ]; then
  pass 'the setup script of that clone sets core.hooksPath'
else
  fail 'the setup script of that clone sets core.hooksPath'
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
