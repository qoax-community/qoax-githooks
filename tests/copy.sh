#!/usr/bin/env bash
#
# Cases for scripts/check-copy.sh. Each case commits a tree in a new
# repository and runs the script there. It expects an exit code and a piece of
# the output. Bash only, like the script. Prints "failures: N".
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
script="$root/scripts/check-copy.sh"
shim="$here/fixtures/shim"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# The fixtures must not see the git configuration of the person who runs the
# tests. They must not see the Actions variables of the CI job either.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
unset GITHUB_ACTIONS GITHUB_ACTION_PATH GITHUB_WORKSPACE \
  COPY STALE_COPY QOAX_GITHOOKS_URL
mkdir -p "$HOME" "$T/no-hooks"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf 'FAIL %s\n' "$1"
  [ -n "${2-}" ] && printf '%s\n' "$2" | sed 's/^/       /'
  return 0
}

# A small action with its own releases keeps most cases independent of the
# tags. A depth-1 checkout has no tags. v0.1.1 keeps the hook of v0.1.0.
action="$T/action"
mkdir -p "$action/scripts"
cp "$script" "$action/scripts/check-copy.sh"
printf '#!/bin/sh\nexit 0\n' >"$T/old-hook"
printf '#!/bin/sh\n# v0.2.0\nexit 0\n' >"$action/commit-msg"
printf '#!/bin/sh\n# edited\nexit 0\n' >"$T/edited-hook"
old_blob="$(git hash-object --no-filters -- "$T/old-hook")"
new_blob="$(git hash-object --no-filters -- "$action/commit-msg")"
printf 'v0.1.0 %s\nv0.1.1 %s\nv0.2.0 %s\n' "$old_blob" "$old_blob" "$new_blob" \
  >"$action/scripts/hook-releases.txt"

# The same action before its hook has a release line.
unreleased="$T/unreleased"
mkdir -p "$unreleased/scripts"
cp "$script" "$unreleased/scripts/check-copy.sh"
cp "$action/commit-msg" "$unreleased/commit-msg"
printf 'v0.1.0 %s\n' "$old_blob" >"$unreleased/scripts/hook-releases.txt"

repo="$T/repo"
fresh() { rm -rf "$repo" && git init -q "$repo"; }
# put SOURCE PATH +x|-x
put() {
  mkdir -p "$repo/$(dirname "$2")"
  cp "$1" "$repo/$2"
  case "$3" in
    +x) chmod 755 "$repo/$2" ;;
    *) chmod 644 "$repo/$2" ;;
  esac
  git -C "$repo" add --chmod="$3" -- "$2"
}
gitlink() {
  git -C "$repo" update-index --add \
    --cacheinfo "160000,e70b5fc7643f403eb6991a655cb417e48f9ffad8,$1"
}
gitmodules() {
  printf '[submodule ".githooks/shared"]\n\tpath = .githooks/shared\n\turl = https://github.com/qoax-community/qoax-githooks.git\n' \
    >"$repo/.gitmodules"
  git -C "$repo" add .gitmodules
}
commit() {
  git -C "$repo" -c core.hooksPath="$T/no-hooks" commit -q --allow-empty \
    -m 'chore: build the fixture'
}

tool="$action/scripts/check-copy.sh"
where="$repo"

# check NAME WANT_RC WANT_TEXT [NAME=VALUE...]: run $tool in $where with these
# variables. The output must hold WANT_TEXT and no shell diagnostic.
check() {
  local name="$1" want="$2" text="$3" out rc
  shift 3
  out="$(cd "$where" && env "$@" bash "$tool" 2>&1)"
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
    *'unbound variable'* | *'command not found'* | *': line '* | *'syntax error'*)
      fail "$name (shell diagnostic)" "$out"
      return
      ;;
  esac
  pass "$name"
}

# lacks NAME WANT_RC TEXT [NAME=VALUE...]: like check, but the output must
# not hold TEXT.
lacks() {
  local name="$1" want="$2" text="$3" out rc
  shift 3
  out="$(cd "$where" && env "$@" bash "$tool" 2>&1)"
  rc=$?
  if [ "$rc" != "$want" ]; then
    fail "$name (rc $rc, want $want)" "$out"
    return
  fi
  case "$out" in
    *"$text"*)
      fail "$name (has \"$text\")" "$out"
      return
      ;;
  esac
  pass "$name"
}

# The fix for a copy at another path, because sync-hook.sh writes only
# .githooks/commit-msg.
by_hand='sync-hook.sh writes only .githooks/commit-msg. Write the commit-msg file of qoax-githooks v0.2.0, the release that this action pins, to hooks/commit-msg, with mode 100755. Or use the default path, .githooks/commit-msg.'

echo '--- the script and its fixture ---'
if [ -x "$script" ]; then
  pass 'scripts/check-copy.sh is executable'
else
  fail 'scripts/check-copy.sh is executable'
fi
constant="$(sed -n 's/^SHIM=\([0-9a-f]*\)$/\1/p' "$script")"
shim_blob="$(git hash-object --no-filters -- "$shim")"
if [ -n "$constant" ] && [ "$shim_blob" = "$constant" ]; then
  pass 'tests/fixtures/shim hashes to the SHIM constant'
else
  fail "tests/fixtures/shim hashes to the SHIM constant ($shim_blob, SHIM=$constant)"
fi

echo '--- inputs ---'
fresh
put "$action/commit-msg" .githooks/commit-msg +x
commit
check 'stale-copy must be error or warning' 2 \
  "must be error or warning, not 'fatal'" STALE_COPY=fatal
check 'an empty stale-copy is not valid' 2 'must be error or warning' STALE_COPY=
check 'stale-copy error is valid' 0 'ok:' STALE_COPY=error
check 'stale-copy warning is valid' 0 'ok:' STALE_COPY=warning

echo '--- 1: copy is empty ---'
check '1 an empty copy turns the compare off' 0 'notice: The copy check is off' COPY=
check '1 the notice is an annotation in Actions' 0 \
  '::notice::The copy check is off' COPY= GITHUB_ACTIONS=true

echo '--- 2: a submodule entry under .githooks ---'
fresh
put "$shim" .githooks/commit-msg +x
gitlink .githooks/shared
gitmodules
commit
check '2 the old layout passes' 0 'not migrated yet'
check '2 the old layout passes with an annotation' 0 \
  '::notice file=.githooks/shared::not migrated yet' GITHUB_ACTIONS=true
check '2 the old layout passes in qoax-githooks itself' 0 'not migrated yet' \
  GITHUB_ACTION_PATH="$repo" GITHUB_WORKSPACE="$repo"

fresh
put "$shim" .githooks/commit-msg -x
gitlink .githooks/shared
gitmodules
commit
check '2 the old layout passes with a 100644 shim' 0 'not migrated yet'

fresh
put "$action/commit-msg" .githooks/commit-msg +x
gitlink .githooks/shared
gitmodules
commit
check '2 a gitlink next to the full hook fails' 1 'A submodule entry is under .githooks'
check '2 the error prints the fix' 1 \
  'git rm -q --cached -- .githooks/shared && d="$(mktemp -d)"'
check '2 the error is an annotation on the gitlink' 1 \
  '::error file=.githooks/shared::A submodule entry' GITHUB_ACTIONS=true
check '2 a copy at another path gets the fix in words' 1 \
  "git rm -q --cached -- .githooks/shared
  $by_hand" COPY=hooks/commit-msg
lacks '2 a copy at another path gets no sync command' 1 'git clone' COPY=hooks/commit-msg

fresh
put "$shim" .githooks/commit-msg +x
gitlink .githooks/shared
commit
check '2 a gitlink without .gitmodules fails' 1 'A submodule entry is under .githooks'

fresh
put "$shim" .githooks/commit-msg +x
gitlink .githooks/other
gitmodules
commit
check '2 a gitlink at another path fails' 1 \
  'git rm -q --cached -- .githooks/other &&'

fresh
put "$shim" .githooks/commit-msg +x
gitlink .githooks/shared
gitlink .githooks/more
gitmodules
commit
check '2 two gitlinks fail' 1 'git rm -q --cached -- .githooks/more .githooks/shared &&'

fresh
gitlink .githooks/shared
gitmodules
commit
check '2 comes before the self test' 1 'A submodule entry is under .githooks' \
  GITHUB_ACTION_PATH="$repo" GITHUB_WORKSPACE="$repo"

echo '--- 3: no copy ---'
fresh
printf 'readme\n' >"$repo/README.md"
git -C "$repo" add README.md
commit
check '3 no copy fails' 1 'There is no tracked copy of the commit-msg hook at .githooks/commit-msg'
check '3 the error prints the sync command' 1 \
  'git clone -q --depth 1 https://github.com/qoax-community/qoax-githooks.git "$d" && sh "$d/scripts/sync-hook.sh"'
check '3 the error names the opt-out' 1 "must set copy: '' on the action"
check '3 the sync command uses QOAX_GITHOOKS_URL' 1 \
  'git clone -q --depth 1 file:///example/qoax-githooks.git "$d"' \
  QOAX_GITHOOKS_URL=file:///example/qoax-githooks.git
check '3 no copy in qoax-githooks itself passes' 0 'because this is qoax-githooks itself' \
  GITHUB_ACTION_PATH="$repo" GITHUB_WORKSPACE="$repo/."
check '3 another action path is not qoax-githooks itself' 1 'There is no tracked copy' \
  GITHUB_ACTION_PATH="$action" GITHUB_WORKSPACE="$repo"
check '3 a missing copy at another path fails' 1 'There is no tracked copy' \
  COPY=hooks/commit-msg
check '3 a copy at another path gets the fix in words' 1 \
  "Write it, then commit:
  $by_hand
A repository with no copy" COPY=hooks/commit-msg
lacks '3 a copy at another path gets no sync command' 1 'git clone' COPY=hooks/commit-msg
check '3 the default path with ./ gets the sync command' 1 'sh "$d/scripts/sync-hook.sh"' \
  COPY=./.githooks/commit-msg
check '3 the fix in words is in the annotation' 1 \
  'then commit:%0A  sync-hook.sh writes only .githooks/commit-msg.' \
  COPY=hooks/commit-msg GITHUB_ACTIONS=true
tool="$unreleased/scripts/check-copy.sh"
check '3 the fix in words for an action with no release line' 1 \
  'Write the commit-msg file of the qoax-githooks commit that this action pins to hooks/commit-msg, with mode 100755.' \
  COPY=hooks/commit-msg
tool="$action/scripts/check-copy.sh"
check '3 the annotation escapes the file property' 1 \
  '::error file=hooks/a%2Cb%3Ac::There is no tracked copy' \
  COPY=hooks/a,b:c GITHUB_ACTIONS=true
check '3 the annotation keeps the command in one line' 1 \
  'then commit:%0A  d="$(mktemp -d)"' GITHUB_ACTIONS=true

fresh
put "$action/commit-msg" .githooks/commit-msg +x
commit
git -C "$repo" rm -q .githooks/commit-msg
commit
check '3 a deleted copy fails' 1 'There is no tracked copy'

echo '--- 4: the shim without the submodule ---'
fresh
put "$shim" .githooks/commit-msg +x
commit
check '4 the shim alone fails' 1 'is the old shim, but the submodule is gone'
check '4 the error prints the sync command' 1 'sh "$d/scripts/sync-hook.sh"'

echo '--- 5: the mode of the copy ---'
fresh
put "$action/commit-msg" .githooks/commit-msg -x
commit
check '5 mode 100644 fails' 1 '.githooks/commit-msg has mode 100644'
check '5 the error prints the chmod command' 1 \
  'git update-index --chmod=+x .githooks/commit-msg'

fresh
cp "$action/commit-msg" "$repo/real-hook"
mkdir -p "$repo/.githooks"
ln -s ../real-hook "$repo/.githooks/commit-msg"
git -C "$repo" add real-hook .githooks/commit-msg
commit
check '5 a symlink fails' 1 '.githooks/commit-msg has mode 120000'
check '5 the error prints the fix for a symlink' 1 \
  'rm -f -- .githooks/commit-msg && d="$(mktemp -d)"'

fresh
cp "$action/commit-msg" "$repo/real-hook"
mkdir -p "$repo/hooks"
ln -s ../real-hook "$repo/hooks/commit-msg"
git -C "$repo" add real-hook hooks/commit-msg
commit
check '5 a symlink at another path gets the fix in words' 1 \
  "rm -f -- hooks/commit-msg
  $by_hand" COPY=hooks/commit-msg
lacks '5 a symlink at another path gets no sync command' 1 'git clone' COPY=hooks/commit-msg

# rm -f cannot remove a folder, so the fix must use git rm -r.
fresh
mkdir -p "$repo/.githooks/commit-msg" "$repo/hooks/commit-msg"
printf 'x\n' >"$repo/.githooks/commit-msg/x"
printf 'x\n' >"$repo/hooks/commit-msg/x"
git -C "$repo" add .githooks hooks
commit
check '5 a folder fails' 1 '.githooks/commit-msg has mode 040000'
check '5 the error removes the folder with git rm' 1 \
  'git rm -r -q -- .githooks/commit-msg && d="$(mktemp -d)"'
check '5 a folder at another path gets git rm and the fix in words' 1 \
  "git rm -r -q -- hooks/commit-msg
  $by_hand" COPY=hooks/commit-msg
if (cd "$repo" && git rm -r -q -- hooks/commit-msg) && [ ! -e "$repo/hooks/commit-msg" ] &&
  [ -z "$(git -C "$repo" ls-files -- hooks)" ]; then
  pass '5 the git rm of the fix removes the folder'
else
  fail '5 the git rm of the fix removes the folder'
fi

fresh
gitlink hooks/commit-msg
mkdir -p "$repo/hooks/commit-msg"
commit
check '5 a submodule at another path gets git rm' 1 \
  "hooks/commit-msg has mode 160000. It must be a regular file with mode 100755, so that every clone gets an executable hook. Fix it, then commit:
  git rm -r -q -- hooks/commit-msg" COPY=hooks/commit-msg
if (cd "$repo" && git rm -r -q -- hooks/commit-msg) && [ ! -e "$repo/hooks/commit-msg" ] &&
  [ -z "$(git -C "$repo" ls-files -- hooks)" ]; then
  pass '5 the git rm of the fix removes the submodule'
else
  fail '5 the git rm of the fix removes the submodule'
fi

echo '--- 6: the copy equals the hook ---'
fresh
put "$action/commit-msg" .githooks/commit-msg +x
mkdir -p "$repo/sub/dir"
commit
check '6 an equal copy passes and names the release' 0 \
  'ok: .githooks/commit-msg is the commit-msg hook of qoax-githooks v0.2.0.'
check '6 a leading ./ in copy is the same path' 0 'ok:' COPY=./.githooks/commit-msg
where="$repo/sub/dir"
check '6 runs from a subdirectory' 0 'ok:'
where="$repo"
printf '# not committed\n' >>"$repo/.githooks/commit-msg"
check '6 an edited work tree is ignored' 0 'ok:'
tool="$unreleased/scripts/check-copy.sh"
check '6 a hook with no release line passes' 0 'No release has this hook yet'
tool="$action/scripts/check-copy.sh"

fresh
put "$action/commit-msg" hooks/commit-msg +x
commit
check '6 a copy at another path passes' 0 'ok: hooks/commit-msg' COPY=hooks/commit-msg

echo '--- 7: an older release ---'
fresh
put "$T/old-hook" .githooks/commit-msg +x
commit
check '7 an older release fails by default' 1 \
  'is the hook of qoax-githooks v0.1.1, but this action has the hook of v0.2.0'
check '7 the error prints the sync command' 1 'sh "$d/scripts/sync-hook.sh"'
check '7 stale-copy error fails' 1 'error: .githooks/commit-msg is the hook' \
  STALE_COPY=error
check '7 stale-copy warning passes with a warning' 0 \
  'warning: .githooks/commit-msg is the hook' STALE_COPY=warning
check '7 the warning is an annotation in Actions' 0 \
  '::warning file=.githooks/commit-msg::' STALE_COPY=warning GITHUB_ACTIONS=true
tool="$unreleased/scripts/check-copy.sh"
check '7 an action with no release line says so' 1 \
  'but this action has the hook of a newer commit'
tool="$action/scripts/check-copy.sh"

echo '--- 8: any other blob ---'
fresh
put "$T/edited-hook" .githooks/commit-msg +x
commit
check '8 an edited copy fails' 1 \
  'is not the hook of any qoax-githooks release up to v0.2.0'
check '8 stale-copy warning does not soften it' 1 'is not the hook' STALE_COPY=warning
check '8 an edited copy in qoax-githooks itself fails' 1 'is not the hook' \
  GITHUB_ACTION_PATH="$repo" GITHUB_WORKSPACE="$repo/."
check '8 the error prints the sync command' 1 'sh "$d/scripts/sync-hook.sh"'
check '8 the error is an annotation on the copy' 1 \
  '::error file=.githooks/commit-msg::' GITHUB_ACTIONS=true

fresh
put "$T/edited-hook" hooks/commit-msg +x
commit
check '8 an edited copy at another path gets the fix in words' 1 \
  "Write the hook of the pin over it, then commit:
  $by_hand" COPY=hooks/commit-msg
lacks '8 an edited copy at another path gets no sync command' 1 'git clone' \
  COPY=hooks/commit-msg

echo '--- nothing to read ---'
fresh
check 'a repository with no commit' 2 'HEAD has no commit'
mkdir -p "$T/nowhere"
where="$T/nowhere"
check 'a folder outside a repository' 2 'Run this script in the work tree' \
  GIT_CEILING_DIRECTORIES="$T"
where="$repo"

echo '--- the hook and releases of this checkout ---'
last="$(awk 'END { print $1 }' "$root/scripts/hook-releases.txt")"
fresh
put "$root/commit-msg" .githooks/commit-msg +x
commit
tool="$script"
check 'this commit-msg is the last release' 0 \
  "ok: .githooks/commit-msg is the commit-msg hook of qoax-githooks $last."
fresh
put "$shim" .githooks/commit-msg +x
gitlink .githooks/shared
gitmodules
commit
check 'the shim fixture is the old layout' 0 'not migrated yet'

echo "failures: $fails"
[ "$fails" -eq 0 ]
