#!/bin/sh
#
# sync-hook.sh: write the commit-msg hook of a qoax-githooks release into the
# tracked copy at .githooks/commit-msg.
#
#   sh sync-hook.sh                # the release that .github/workflows pins
#   sh sync-hook.sh --ref v1.1.0   # a tag or a commit sha
#   sh sync-hook.sh --check        # write nothing, exit 1 if the copy differs
#
# The pin is the ref of each `uses: qoax-community/qoax-githooks@<ref>` line.
# CI compares the copy with the hook of that pin, so the pin is the default.
#
# Run it anywhere in the work tree, also in a linked worktree. It fetches the
# ref into a temporary bare repository, so the refs of this repository do not
# change. It stages the copy with mode 100755. It never commits or pushes.
#
# --check compares the index blob, the index mode and the bytes in the work
# tree. CI reads only committed blobs, so only the work-tree compare can see a
# copy that a checkout wrote with CRLF line ends.
#
# Exit status: 0 the copy is the hook, or the script wrote it. 1 the copy
# differs (--check), or the script cannot sync. 2 bad usage.
set -u

url="${QOAX_GITHOOKS_URL:-https://github.com/qoax-community/qoax-githooks.git}"
copy=.githooks/commit-msg

say() { printf 'sync-hook: %s\n' "$*" >&2; }
die() {
  say "$@"
  exit 1
}
usage() {
  say "$1"
  printf 'usage: sh sync-hook.sh [--check] [--ref <tag or commit sha>]\n' >&2
  exit 2
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

# A hook or `git rebase --exec` can export GIT_DIR and its friends. They name
# this repository, and must not reach the temporary one. The prompt would wait
# for a password that a wrong URL never accepts.
scrubbed() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
    GIT_TERMINAL_PROMPT=0 "$@"
  )
}
bare() { scrubbed git --git-dir="$tmp/git" "$@"; }

# gives_lf ATTRS: the check-attr output for text and eol gives LF. git
# ignores eol when text is unset.
gives_lf() {
  case "$1" in
    *'text: unset'*) return 1 ;;
    *'eol: lf'*) return 0 ;;
  esac
  return 1
}

# Only the rules that HEAD commits count, because only they reach other
# clones. An edit of .gitattributes that is not committed, the info/attributes
# of this clone and the global attributes do not count. Thus check-attr runs
# in a scratch repository with no info/attributes. With no template,
# init.templateDir cannot add one. Its work tree holds only the two files that
# can give the copy a rule, as HEAD has them.
lf_rule() {
  scrubbed git init -q --bare --template= "$tmp/attr.git" || return 1
  mkdir -p "$tmp/attr-tree/.githooks" || return 1
  for f in .gitattributes .githooks/.gitattributes; do
    git cat-file blob "HEAD:$f" >"$tmp/attr-tree/$f" 2>/dev/null || rm -f "$tmp/attr-tree/$f"
  done
  attrs="$(scrubbed env GIT_ATTR_NOSYSTEM=1 git --git-dir="$tmp/attr.git" \
    --work-tree="$tmp/attr-tree" -c core.attributesFile="$tmp/no-attributes" \
    check-attr text eol -- "$copy")" || return 1
  gives_lf "$attrs"
}

# A checkout in this clone writes the copy with LF. Here every rule counts,
# because git checkout reads them all.
checkout_lf() {
  attrs="$(git check-attr text eol -- "$copy")" || return 1
  gives_lf "$attrs"
}

ref=''
check=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    --ref)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage '--ref needs a tag or a commit sha.'
      ref="$2"
      shift
      ;;
    --ref=?*) ref="${1#--ref=}" ;;
    -h | --help)
      printf 'usage: sh sync-hook.sh [--check] [--ref <tag or commit sha>]\n'
      exit 0
      ;;
    *) usage "unknown argument: $1" ;;
  esac
  shift
done

if ! top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  say 'Run this script in the work tree of the repository to sync.'
  exit 2
fi
cd "$top" || exit 2

# A gitlink under .githooks is the old layout. Its shim runs the hook from the
# submodule, so a copy next to it would never run.
links="$(git ls-files -s -- .githooks | awk '$1 == "160000" { sub(/^[^\t]*\t/, ""); print }')"
if [ -n "$links" ]; then
  die "A submodule entry is under .githooks: $(printf '%s' "$links" | tr '\n' ' ')
  Move the repository off the submodule first, with
  scripts/migrate-from-submodule.sh of qoax-githooks."
fi

pin_source=--ref
if [ -z "$ref" ]; then
  lines="$(pins)"
  if [ -z "$lines" ]; then
    die "No workflow in .github/workflows uses qoax-community/qoax-githooks@<ref>.
  Pass --ref with a tag or a commit sha."
  fi
  refs="$(printf '%s\n' "$lines" | sed 's/.*: //' | sort -u)"
  if [ "$(printf '%s\n' "$refs" | awk 'END { print NR }')" -gt 1 ]; then
    die "The workflows pin qoax-community/qoax-githooks at more than one ref:
$(printf '%s\n' "$lines" | sed 's/^/  /')
  Give each step the same pin, or pass --ref."
  fi
  if [ -z "$refs" ]; then
    die "A workflow names qoax-community/qoax-githooks with no ref:
$(printf '%s\n' "$lines" | sed 's/^/  /')"
  fi
  ref="$refs"
  pin_source=.github/workflows
fi

# mktemp -d without a template ignores TMPDIR on macOS.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/sync-hook.XXXXXX")" || die 'Cannot make a temporary folder.'
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

scrubbed git init -q --bare "$tmp/git" || die "Cannot make a repository in $tmp."
if ! bare fetch -q --depth 1 --no-tags "$url" "$ref"; then
  die "Cannot fetch $ref from $url."
fi
commit="$(bare rev-parse -q --verify 'FETCH_HEAD^{commit}')" ||
  die "$ref at $url is not a commit."
want="$(bare rev-parse -q --verify "$commit:commit-msg")" ||
  die "qoax-githooks $ref has no commit-msg."
[ "$(bare cat-file -t "$want")" = blob ] || die "commit-msg in qoax-githooks $ref is not a file."

release="qoax-githooks $ref"
[ "$ref" = "$commit" ] || release="$release ($commit)"
[ "$pin_source" = --ref ] || release="$release, the pin in $pin_source"

# The index can hold more than one stage of a path in a merge, or a folder at
# the path. Only one exact entry counts.
entry="$(git ls-files -s -- "$copy" |
  awk -v p="$copy" 'BEGIN { FS = "\t" } $2 == p { print $1 }')"
have_mode=''
have_blob=''
problems=''
problem() {
  problems="$problems
  - $*"
}
case "$entry" in
  '') problem 'the index has no entry at this path' ;;
  *'
'*) problem 'the index has more than one stage of it (a merge conflict)' ;;
  *)
    have_mode="${entry%% *}"
    have_blob="${entry#* }"
    have_blob="${have_blob%% *}"
    ;;
esac
if [ -n "$have_blob" ] && [ "$have_blob" != "$want" ]; then
  problem "the index has blob $have_blob, and the hook is blob $want"
fi
if [ -n "$have_mode" ] && [ "$have_mode" != 100755 ]; then
  problem "the index has mode $have_mode, not 100755"
fi
if [ -L "$copy" ]; then
  problem 'the work tree has a symbolic link at this path'
elif [ ! -f "$copy" ]; then
  problem 'the work tree has no file at this path'
else
  work="$(git hash-object --no-filters -- "$copy")"
  if [ "$work" != "$want" ]; then
    if grep -q "$(printf '\r')" "$copy"; then
      # With the committed rule in place, the CRLF comes from an edit, from a
      # checkout made before the rule, from an index blob that is not the
      # hook, or from a rule of this clone against it. Another rule in
      # .gitattributes does not fix it.
      if ! lf_rule; then
        problem "the work tree file has CRLF line ends, and git cannot run it.
    Add '/.githooks/** text eol=lf' to .gitattributes and commit it, so that
    every clone checks the hook out with LF. Then sync again."
      elif [ "$have_blob" != "$want" ]; then
        problem "the work tree file has CRLF line ends, and git cannot run it.
    .gitattributes already gives it eol=lf, so a sync writes it with LF."
      elif checkout_lf; then
        # git checkout alone skips a file whose stat data matches the index,
        # as after a checkout made before the rule. Thus the rm. The cd is
        # there because the script runs anywhere in the work tree.
        problem "the work tree file has CRLF line ends, and git cannot run it.
    .gitattributes already gives it eol=lf, so the work tree file differs
    from the index, even when git status shows no change. Run sync-hook.sh
    without --check, or run:
    cd \"\$(git rev-parse --show-toplevel)\" && rm -f -- $copy && git checkout -- $copy"
      else
        problem "the work tree file has CRLF line ends, and git cannot run it.
    .gitattributes gives it eol=lf, but a rule of this clone overrides that,
    so a checkout writes CRLF again. Remove that rule, then sync again. Look
    in an edit of .gitattributes that is not committed, and in
    $(git rev-parse --git-path info/attributes)."
      fi
    else
      problem "the work tree file is blob $work, not the hook"
    fi
  fi
  [ -x "$copy" ] || problem 'the work tree file is not executable'
fi

if [ -z "$problems" ]; then
  printf 'ok: %s is the commit-msg hook of %s.\n' "$copy" "$release"
  exit 0
fi

if [ "$check" = 1 ]; then
  die "$copy is not the commit-msg hook of $release:$problems
  Run sync-hook.sh without --check to write it."
fi

if [ -d "$copy" ] && [ ! -L "$copy" ]; then
  die "$copy is a folder. Remove it, then sync again."
fi
mkdir -p .githooks || die 'Cannot make the folder .githooks.'
bare cat-file blob "$want" >"$tmp/commit-msg" || die "Cannot read the hook of $release."
# rm first, so that a symbolic link at the path is replaced, not followed.
rm -f "$copy" || die "Cannot replace $copy."
cp "$tmp/commit-msg" "$copy" || die "Cannot write $copy."
chmod 755 "$copy" || die "Cannot make $copy executable."
git add --chmod=+x -- "$copy" || die "Cannot stage $copy."

staged="$(git ls-files -s -- "$copy" |
  awk -v p="$copy" 'BEGIN { FS = "\t" } $2 == p { print $1 }')"
case "$staged" in
  "100755 $want 0") ;;
  *)
    die "git add staged '$staged', not the hook (blob $want).
  A clean filter or an eol setting in .gitattributes changed the bytes."
    ;;
esac
printf 'synced: %s is now the commit-msg hook of %s.\n' "$copy" "$release"
printf '  It is staged with mode 100755. Commit it.\n'
