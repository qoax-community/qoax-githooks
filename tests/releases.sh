#!/usr/bin/env bash
#
# Checks scripts/hook-releases.txt against the release tags and the hook.
# check-copy.sh names a copy by this file. A wrong line names the wrong
# release. A missing line turns an older copy into an edited one, and an
# edited copy always fails. Prints "failures: N".
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
manifest="$root/scripts/hook-releases.txt"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf 'FAIL %s\n' "$1"
  [ -n "${2-}" ] && printf '%s\n' "$2" | sed 's/^/       /'
  return 0
}

echo '--- the manifest ---'
bad="$(grep -nvE '^v[0-9]+\.[0-9]+\.[0-9]+ [0-9a-f]{40}$' "$manifest")"
if [ -z "$bad" ]; then
  pass 'each line is a version and a blob'
else
  fail 'each line is a version and a blob' "$bad"
fi

duplicates="$(cut -d' ' -f1 "$manifest" | sort | uniq -d)"
if [ -z "$duplicates" ]; then
  pass 'each version has one line'
else
  fail 'each version has one line' "$duplicates"
fi

# The release PR adds the line, so a change to the hook without its line
# fails here before the release.
own="$(git hash-object --no-filters -- "$root/commit-msg")"
last="$(awk 'END { print $1 " " $2 }' "$manifest")"
if [ "${last#* }" = "$own" ]; then
  pass "the last line ($last) is the current commit-msg"
else
  fail "the last line ($last) is the current commit-msg ($own)"
fi

echo '--- the tags ---'
tags="$(git -C "$root" tag -l 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null)"
if [ -z "$tags" ] && [ -n "${GITHUB_ACTIONS-}" ]; then
  # CI is the one place where every pull request runs this compare. A skip
  # there would pass a wrong manifest line with no notice.
  fail 'the checkout has the release tags' \
    'This clone has no release tags. Check out with fetch-depth: 0, so that the tags are there.'
elif [ -z "$tags" ]; then
  printf 'skip this clone has no release tags, as in a depth-1 checkout.\n'
  printf '     Run git fetch --tags, then run this test again to compare the tags.\n'
else
  for tag in $tags; do
    if ! blob="$(git -C "$root" rev-parse -q --verify "$tag:commit-msg")"; then
      fail "$tag has a commit-msg"
      continue
    fi
    if grep -qxF "$tag $blob" "$manifest"; then
      pass "$tag $blob"
    else
      fail "$tag has the line \"$tag $blob\""
    fi
  done
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
