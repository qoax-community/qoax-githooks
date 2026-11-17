#!/usr/bin/env bash
#
# check-copy.sh: compare the tracked copy of the commit-msg hook in a
# repository with the hook of this action.
#
#   scripts/check-copy.sh                       # in the repository to check
#   COPY=hooks/commit-msg scripts/check-copy.sh # a copy at another path
#   COPY='' scripts/check-copy.sh               # the compare is off
#   STALE_COPY=warning scripts/check-copy.sh    # an older release only warns
#
# It reads the tree of HEAD, not the work tree, because only committed bytes
# reach other clones. For a pull request, HEAD is the merge commit, so the
# result is what the base branch gets after the merge.
#
# The rule behind the levels: a state that only a commit can cause always
# fails. A copy of an older release follows STALE_COPY, because a release
# alone causes that state.
#
# The script prints workflow commands only when GITHUB_ACTIONS is set, so the
# local output stays plain.
#
# Exit status: 0 pass, 1 fail, 2 bad input or nothing to read.
set -uo pipefail

# The blob of the shim that ran the hook from the old .githooks/shared
# submodule. Every repository that used the submodule tracks these bytes.
SHIM=f53a4335fd392087d419ac7dff0fe428d1de686c

here="$(cd "$(dirname "$0")" && pwd)"
own="$here/../commit-msg"
manifest="$here/hook-releases.txt"
url="${QOAX_GITHOOKS_URL:-https://github.com/qoax-community/qoax-githooks.git}"

# Only an unset COPY gets the default, because an empty COPY turns the
# compare off.
copy="${COPY-.githooks/commit-msg}"
stale="${STALE_COPY-error}"

# A workflow command ends at a newline and reads % as an escape. A property
# value also ends at a colon or a comma.
escape_data() {
  local s="$1"
  s="${s//%/%25}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  printf '%s' "$s"
}

escape_property() {
  local s
  s="$(escape_data "$1")"
  s="${s//:/%3A}"
  s="${s//,/%2C}"
  printf '%s' "$s"
}

# say LEVEL FILE MESSAGE, where LEVEL is notice, warning or error.
say() {
  local level="$1" file="$2" message="$3" line
  if [ -n "${GITHUB_ACTIONS-}" ]; then
    line="::$level"
    [ -n "$file" ] && line="$line file=$(escape_property "$file")"
    line="$line::$(escape_data "$message")"
  else
    line="$level: $message"
  fi
  if [ "$level" = notice ]; then
    printf '%s\n' "$line"
  else
    printf '%s\n' "$line" >&2
  fi
}

quote() { printf '%q' "$1"; }

# The release with this hook blob. A release that keeps the hook repeats the
# blob of the release before it, so the last line names the newest release.
version_of() {
  awk -v blob="$1" '$2 == blob { version = $1 } END { print version }' "$manifest"
}

# Prints "mode type object" for exactly this path in the tree of HEAD, or
# nothing. For a path that ends in a slash, ls-tree prints the content of the
# tree. Thus the path of each line must match.
entry() {
  local line
  while IFS= read -r -d '' line; do
    if [ "${line#*$'\t'}" = "$1" ]; then
      printf '%s\n' "${line%%$'\t'*}"
    fi
  done < <(git --literal-pathspecs ls-tree -z HEAD -- "$1")
}

case "$stale" in
  error | warning) ;;
  *)
    say error '' "The input stale-copy must be error or warning, not '$stale'."
    exit 2
    ;;
esac

if [ -z "$copy" ]; then
  say notice '' 'The copy check is off, because the input copy is empty.'
  exit 0
fi

# ls-tree reads paths relative to the current directory.
if ! top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  say error '' 'Run this script in the work tree of the repository to check.'
  exit 2
fi
cd "$top" || exit 2
if ! git rev-parse -q --verify 'HEAD^{commit}' >/dev/null; then
  say error '' 'HEAD has no commit, so there is no tree to read.'
  exit 2
fi
if [ ! -f "$own" ] || [ ! -f "$manifest" ]; then
  say error '' "This action is incomplete. It needs $own and $manifest."
  exit 2
fi
if ! own_blob="$(git hash-object --no-filters -- "$own")"; then
  say error '' "Cannot hash $own."
  exit 2
fi
own_version="$(version_of "$own_blob")"

while [ "${copy#./}" != "$copy" ]; do
  copy="${copy#./}"
done
copy_q="$(quote "$copy")"
sync_command="d=\"\$(mktemp -d)\" && git clone -q --depth 1 $(quote "$url") \"\$d\" && sh \"\$d/scripts/sync-hook.sh\""

# sync-hook.sh writes only .githooks/commit-msg. For a copy at another path,
# the sync command would write the wrong file, so the fix is in words.
if [ "$copy" = .githooks/commit-msg ]; then
  write_hook="$sync_command"
else
  if [ -n "$own_version" ]; then
    pinned="qoax-githooks $own_version, the release that this action pins,"
  else
    pinned='the qoax-githooks commit that this action pins'
  fi
  write_hook="sync-hook.sh writes only .githooks/commit-msg. Write the commit-msg file of $pinned to $copy, with mode 100755. Or use the default path, .githooks/commit-msg."
fi

# after COMMAND: COMMAND, then the step that writes the hook.
after() {
  if [ "$copy" = .githooks/commit-msg ]; then
    printf '%s && %s' "$1" "$sync_command"
  else
    printf '%s\n  %s' "$1" "$write_hook"
  fi
}

read -r copy_mode copy_type copy_object <<<"$(entry "$copy")"
read -r _ gitmodules_type _ <<<"$(entry .gitmodules)"

link_count=0
links=''
first_link=''
while IFS= read -r -d '' line; do
  case "$line" in
    160000\ *)
      path="${line#*$'\t'}"
      link_count=$((link_count + 1))
      links="$links $(quote "$path")"
      [ -n "$first_link" ] || first_link="$path"
      ;;
  esac
done < <(git ls-tree -r -z HEAD -- .githooks)

# This case runs first. A repository that still uses the submodule also has a
# file at the copy path: the shim.
if [ "$link_count" -gt 0 ]; then
  if [ "$link_count" -eq 1 ] && [ "$first_link" = .githooks/shared ] &&
    [ "$gitmodules_type" = blob ] && [ "$copy_object" = "$SHIM" ]; then
    say notice .githooks/shared "not migrated yet: .githooks/shared is still a submodule, so the copy check is skipped. To move off the submodule, use scripts/migrate-from-submodule.sh of qoax-githooks."
    exit 0
  fi
  say error "$first_link" "A submodule entry is under .githooks:$links. Only the old layout can have one: a submodule at .githooks/shared, a .gitmodules file and the shim at $copy. Remove the entry and write the hook, then commit:
  $(after "git rm -q --cached --$links")"
  exit 1
fi

if [ -z "$copy_mode" ]; then
  # The self test is in this case only. With uses: ./ the action path is the
  # workspace. A self test before the other cases thus passes every fixture
  # that the CI of qoax-githooks commits.
  if [ -n "${GITHUB_ACTION_PATH-}" ] && [ -n "${GITHUB_WORKSPACE-}" ] &&
    [ "$GITHUB_ACTION_PATH" -ef "$GITHUB_WORKSPACE" ]; then
    say notice '' "There is no copy at $copy, because this is qoax-githooks itself. Its own commit-msg is the hook."
    exit 0
  fi
  say error "$copy" "There is no tracked copy of the commit-msg hook at $copy. Write it, then commit:
  $write_hook
A repository with no copy must set copy: '' on the action."
  exit 1
fi

if [ "$copy_object" = "$SHIM" ]; then
  say error "$copy" "$copy is the old shim, but the submodule is gone. The shim needs the submodule to run the hook. Write the full hook over the shim, then commit:
  $write_hook"
  exit 1
fi

if [ "$copy_mode" != 100755 ] || [ "$copy_type" != blob ]; then
  if [ "$copy_mode" = 100644 ]; then
    fix="git update-index --chmod=+x $copy_q"
  elif [ "$copy_type" = blob ]; then
    fix="$(after "rm -f -- $copy_q")"
  else
    # rm -f cannot remove a folder, and a submodule is a folder in the work
    # tree. git rm -r removes the index entries too.
    fix="$(after "git rm -r -q -- $copy_q")"
  fi
  say error "$copy" "$copy has mode $copy_mode. It must be a regular file with mode 100755, so that every clone gets an executable hook. Fix it, then commit:
  $fix"
  exit 1
fi

if [ "$copy_object" = "$own_blob" ]; then
  if [ -n "$own_version" ]; then
    printf 'ok: %s is the commit-msg hook of qoax-githooks %s.\n' "$copy" "$own_version"
  else
    printf 'ok: %s is the commit-msg hook of this qoax-githooks commit. No release has this hook yet.\n' "$copy"
  fi
  exit 0
fi

copy_version="$(version_of "$copy_object")"
if [ -n "$copy_version" ]; then
  say "$stale" "$copy" "$copy is the hook of qoax-githooks $copy_version, but this action has the hook of ${own_version:-a newer commit}. Update the copy to the pin of the action, then commit:
  $write_hook"
  [ "$stale" = error ] && exit 1
  exit 0
fi

say error "$copy" "$copy is not the hook of any qoax-githooks release up to ${own_version:-this commit} (blob $copy_object). Somebody edited it, or it comes from a release that is newer than the pin of the action. Write the hook of the pin over it, then commit:
  $write_hook"
exit 1
