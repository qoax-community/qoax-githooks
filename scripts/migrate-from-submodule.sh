#!/bin/sh
#
# migrate-from-submodule.sh: move a repository from the qoax-githooks
# submodule at .githooks/shared to a tracked copy of the hook at
# .githooks/commit-msg.
#
#   sh migrate-from-submodule.sh --ref v1.1.0
#   sh migrate-from-submodule.sh --ref <commit sha of a release>
#
# Run it in a fresh temporary clone, on a new branch. First point
# core.hooksPath at a folder that holds only commit-msg, a symbolic link to
# .githooks/commit-msg of the clone:
#
#   hooks="$(mktemp -d)"
#   ln -s "$(git rev-parse --show-toplevel)/.githooks/commit-msg" "$hooks/commit-msg"
#   git config core.hooksPath "$hooks"
#
# Then the new hook checks each commit of the script, and no other hook runs.
# With .githooks, a tracked pre-commit can stop the commits, and the Git LFS
# hooks stop the push when git-lfs is not installed.
#
# The script makes up to three commits:
#
#   build: track a copy of the commit-msg hook
#   ci: pin the qoax-githooks commit check
#   ci: let Dependabot bump the qoax-githooks pin
#
# It replaces a file only when it knows the blob, so nothing that a
# repository added is lost. On any other blob it stops and prints what to
# edit by hand. Commit that edit, then run the script again with the same
# --ref. It goes on from where it stopped. Commit an edit before the move
# with --no-verify, because the shim cannot find the hook then. Commit an
# edit after the move as usual, so that the new hook checks it.
#
# A setup script that it does not know stays as it is when it runs no git
# submodule command. The list at the end shows its lines that name the old
# layout. On a migrated repository the script changes nothing. Last, it runs
# the self-test, prints the diff and lists the lines to check by hand. It
# never pushes.
#
# Exit status: 0 the repository is migrated and the self-test passed.
# 1 the script stopped: see its message. 2 bad usage.
set -u

url="${QOAX_GITHOOKS_URL:-https://github.com/qoax-community/qoax-githooks.git}"
copy=.githooks/commit-msg
ignore=.githooks/.gitignore
workflow=.github/workflows/commit-conventions.yml
dependabot=.github/dependabot.yml

# The shim that ran the hook from the submodule. Every repository that used
# the submodule tracks these bytes.
SHIM=f53a4335fd392087d419ac7dff0fe428d1de686c
# The setup scripts of templates/ in v1.0.0 to v1.0.7. They only check the
# submodule out and set core.hooksPath, so the new templates lose nothing.
OLD_SETUP_SH=6a7f9acc8bb249cd898fc66ad278bbdb66505dff
OLD_SETUP_MJS=2f2e77b0032cbc8c5e92e14852c0b316f63600c5
# Workflows and Dependabot files that hold only the old wiring: the
# templates of v1.0.x and the variants that the repositories carry.
OLD_WORKFLOWS='07ecff11585ae22bd729773f25c9d954f01bf0a2
47b118d08c130746771db29d655fbdf6e5eb15f3
00d012f4c9d2660431f8d6bbb2b56dba5a683b59'
OLD_DEPENDABOTS='956ccf5642033e85a5ff7fee0a14f0b496759bac
35ca5c4b3b480648dc2308bee9dc3bc15a1ad118
159cfe5d35a33487f67ec3e081ae24ecda721101
c0ee830b1d693c38c2a5998359c67e815aae5c84'
# setup.cmd runs this line before it sets core.hooksPath. Without the
# submodule the line fails, and setup.cmd stops there.
SETUP_CMD_LINE='git submodule update --init .githooks/shared || exit /b 1'
# A line that runs a git submodule command, in sh, cmd or node. Prose that
# names the old submodule does not match.
CALLS_SUBMODULE='submodule[^a-z.]+(add|update|init|sync|foreach|deinit|absorbgitdirs)'

say() { printf '%s\n' "$*"; }
problem() {
  problems="$problems
  - $*"
}
stop() {
  printf 'stop: %s\n' "$*" >&2
  exit 1
}
usage() {
  printf 'migrate-from-submodule: %s\n' "$1" >&2
  printf 'usage: sh migrate-from-submodule.sh --ref <release tag or commit sha>\n' >&2
  exit 2
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

# Prints "mode blob" of exactly this path in the index, or nothing.
entry() {
  git ls-files -s -- "$1" |
    awk -v p="$1" 'BEGIN { FS = "\t" } $2 == p { split($1, f, " "); print f[1] " " f[2] }'
}
blob_of() {
  e="$(entry "$1")"
  printf '%s' "${e#* }"
}
known() {
  [ -n "$1" ] && printf '%s\n' "$2" | grep -qxF -- "$1"
}

# Prints "file:line: ref" for each step that uses ACTION. A comment line does
# not count, because it runs nothing.
uses() {
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    awk -v action="$1" -v sq="'" '
      BEGIN {
        gsub(/\./, "[.]", action)
        re = "^[ \t]*(-[ \t]+)?uses:[ \t]*[\"" sq "]?" action "@"
      }
      $0 ~ re {
        ref = $0
        sub(/^[^@]*@/, "", ref)
        sub("[ \t\r\"#" sq "].*$", "", ref)
        print FILENAME ":" FNR ": " ref
      }' "$f"
  done
}

# Prints each step that uses qoax-githooks without the release as the last
# token of its comment. Dependabot updates the comment only in that form.
untagged() {
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    awk -v tag="$1" -v sq="'" '
      BEGIN { re = "^[ \t]*(-[ \t]+)?uses:[ \t]*[\"" sq "]?qoax-community/qoax-githooks@" }
      $0 ~ re {
        line = $0
        sub(/[ \t\r]+$/, "", line)
        n = length(line) - length(tag)
        if (n < 2 || substr(line, n + 1) != tag || substr(line, n, 1) != " " ||
          index(line, "#") == 0) print FILENAME ":" FNR
      }' "$f"
  done
}

# The workflows are done when every step pins the release, with its tag in
# the comment, and no step calls the reusable workflow of qoax-reusables.
workflows_pinned() {
  pins="$(uses qoax-community/qoax-githooks)"
  [ -n "$pins" ] || return 1
  [ "$(printf '%s\n' "$pins" | sed 's/.*: //' | sort -u)" = "$sha" ] || return 1
  [ -z "$(untagged "$tag")" ] || return 1
  [ -z "$(uses qoax-community/qoax-reusables/.github/workflows/commit-conventions.yml)" ]
}

# Dependabot is done when no entry bumps a submodule and an entry for GitHub
# Actions can bump the pin.
dependabot_moved() {
  [ -f "$dependabot" ] || return 1
  ! grep -qE '^[[:space:]]*-?[[:space:]]*package-ecosystem:[[:space:]]*["'"'"']?gitsubmodule' \
    "$dependabot" || return 1
  [ "$(actions_entry_bumps qoax-community/qoax-githooks <"$dependabot")" = yes ]
}

# Prints yes when an entry for GitHub Actions can bump ACTION: no ignore of
# that entry names it, and its allow list names it, if it has one. A name
# can hold the wildcard *, as in Dependabot. An ignore that leaves some
# versions open still counts, because the pin must follow every release. The
# parse knows block YAML and lists on one line. In any other form the entry
# cannot bump, so the worst result is a stop that asks for a hand edit.
actions_entry_bumps() { # ACTION
  awk -v action="$1" -v sq="'" '
    BEGIN {
      keyre = "^[\"" sq "]?[A-Za-z_-]+[\"" sq "]?[ \t]*:([ \t]|$)"
      namere = "dependency-name[\"" sq "]?[ \t]*:[ \t]*[\"" sq "]?[A-Za-z0-9_.*/-]+"
      e = -1
      k = -1
    }
    function glob(p, s, n, part, i, at, rest) {
      n = split(p, part, "[*]")
      if (n == 1) return p == s
      if (substr(s, 1, length(part[1])) != part[1]) return 0
      rest = substr(s, length(part[1]) + 1)
      for (i = 2; i < n; i++) {
        at = index(rest, part[i])
        if (at == 0) return 0
        rest = substr(rest, at + length(part[i]))
      }
      return length(rest) >= length(part[n]) &&
        substr(rest, length(rest) - length(part[n]) + 1) == part[n]
    }
    function names(s, kind, v) {
      while (match(s, namere)) {
        v = substr(s, RSTART, RLENGTH)
        sub("^[^:]*:[ \t]*[\"" sq "]?", "", v)
        if (glob(v, action)) {
          if (kind == "ignore") blocked = 1
          else allowed = 1
        }
        s = substr(s, RSTART + RLENGTH)
      }
    }
    function entry_done() {
      if (eco == "github-actions" && !blocked && (!has_allow || allowed)) ok = 1
      eco = ""
      block = ""
      blocked = 0
      has_allow = 0
      allowed = 0
    }
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/[ \t]+#.*$/, "", line)
      if (line ~ /^[ \t]*(#|$)/) next
      match(line, /^ */)
      ind = RLENGTH
      body = substr(line, ind + 1)
      # YAML lets the list of updates start in column 0 too.
      if (ind == 0 && body !~ /^-([ \t]|$)/) {
        if (in_updates) entry_done()
        name = body
        sub(/[ \t]*:.*$/, "", name)
        in_updates = (name == "updates")
        e = -1
        k = -1
        next
      }
      if (!in_updates) next
      if (body ~ /^-([ \t]|$)/ && (e < 0 || ind == e)) {
        entry_done()
        e = ind
        rest = body
        sub(/^-[ \t]*/, "", rest)
        k = -1
        if (rest == "") next
        k = ind + length(body) - length(rest)
        ind = k
        body = rest
      } else if (k < 0) {
        k = ind
      }
      if (ind == k && match(body, keyre)) {
        name = body
        sub("[ \t]*:.*$", "", name)
        gsub("[\"" sq "]", "", name)
        value = body
        sub("^[^:]*:[ \t]*", "", value)
        block = name
        if (name == "package-ecosystem") {
          gsub("[\"" sq "]", "", value)
          sub(/[ \t]+$/, "", value)
          eco = value
        }
        if (name == "allow") has_allow = 1
        if (name == "allow" || name == "ignore") names(value, name)
        next
      }
      if (ind > k || body ~ /^-/)
        if (block == "allow" || block == "ignore") names(body, block)
    }
    END {
      if (in_updates) entry_done()
      print (ok ? "yes" : "no")
    }'
}

# The .gitattributes files of the work tree count, because this script checks
# the rule again after it stages one. Other clones do not get the global
# attributes of the person who runs this script, or the info/attributes of
# this clone. Thus check-attr runs with a scratch git folder that has no
# info/attributes.
lf_rule() {
  attrs="$(scrubbed env GIT_ATTR_NOSYSTEM=1 git --git-dir="$tmp/attr.git" --work-tree="$top" \
    -c core.attributesFile="$tmp/no-attributes" check-attr text eol -- "$copy")" || return 1
  case "$attrs" in
    *'text: unset'*) return 1 ;;
    *'eol: lf'*) return 0 ;;
  esac
  return 1
}

append() { # FILE TEXT_FILE: append, with a newline first if FILE lacks one.
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; then
    printf '\n' >>"$1" || return 1
  fi
  cat "$2" >>"$1"
}

ref=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage '--ref needs a release tag or a commit sha.'
      ref="$2"
      shift
      ;;
    --ref=?*) ref="${1#--ref=}" ;;
    -h | --help)
      printf 'usage: sh migrate-from-submodule.sh --ref <release tag or commit sha>\n'
      exit 0
      ;;
    *) usage "unknown argument: $1" ;;
  esac
  shift
done
[ -n "$ref" ] || usage 'pass --ref with a release tag or its commit sha.'

if ! top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  usage 'run this script in the work tree of the repository to migrate.'
fi
cd "$top" || exit 2
git rev-parse -q --verify 'HEAD^{commit}' >/dev/null || stop 'HEAD has no commit.'

if [ -z "$(entry "$copy")" ]; then
  stop "There is no $copy here, so this is not a repository of the old layout.
  The old layout has the shim at $copy and the submodule at .githooks/shared."
fi

# core.hooksPath must hold only the new hook, so that no other tracked hook
# runs on the commits of this script.
hooks="$(git config --type=path --get core.hooksPath)" || hooks=''
case "$hooks" in
  '' | /*) ;;
  *) hooks="$top/$hooks" ;;
esac
if [ -z "$hooks" ] || [ ! -d "$hooks" ] || [ "$(ls -A "$hooks")" != commit-msg ] ||
  [ ! "$hooks/commit-msg" -ef "$copy" ]; then
  stop "core.hooksPath must point at a folder that holds only commit-msg, a
  symbolic link to $copy of this clone. It is '${hooks:-unset}'. Run:
    hooks=\"\$(mktemp -d)\"
    ln -s \"\$(git rev-parse --show-toplevel)/$copy\" \"\$hooks/commit-msg\"
    git config core.hooksPath \"\$hooks\""
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  stop "The work tree or the index has changes. Use a fresh clone, or commit
  or drop the changes first:
$(git status --short --untracked-files=no | sed 's/^/    /')"
fi

# The workflow names the release by its tag, so a sha needs its tag too.
# ls-remote prints an annotated tag twice. The ^{} line has the commit.
remote_tags="$(scrubbed git ls-remote --tags "$url")" || stop "Cannot list the tags of $url."
pairs="$(printf '%s\n' "$remote_tags" | awk '
  BEGIN { FS = "\t" }
  $2 ~ /^refs\/tags\// {
    name = substr($2, 11)
    if (name ~ /\^\{\}$/) peeled[substr(name, 1, length(name) - 3)] = $1
    else plain[name] = $1
  }
  END { for (n in plain) print ((n in peeled) ? peeled[n] : plain[n]) " " n }')"

ref="${ref#refs/tags/}"
sha=''
if printf '%s\n' "$ref" | grep -qxE '[0-9a-f]{40}'; then
  sha="$ref"
else
  sha="$(printf '%s\n' "$pairs" | awk -v n="$ref" '$2 == n { print $1 }')"
  if [ -z "$sha" ] && printf '%s\n' "$ref" | grep -qxE '[0-9a-f]{7,39}'; then
    sha="$(printf '%s\n' "$pairs" | awk -v p="$ref" 'index($1, p) == 1 { print $1 }' | sort -u)"
    case "$sha" in
      *'
'*) stop "$ref is the start of more than one tagged commit. Pass the full sha." ;;
    esac
  fi
fi
[ -n "$sha" ] || stop "$url has no tag $ref, and $ref is not a commit sha."

release_tags="$(printf '%s\n' "$pairs" |
  awk -v c="$sha" '$1 == c && $2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ { print $2 }')"
if printf '%s\n' "$release_tags" | grep -qxF -- "$ref"; then
  tag="$ref"
else
  # The newest one, if a commit has more than one release tag.
  tag="$(printf '%s\n' "$release_tags" | sed -n 's/^v//p' |
    sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
  [ -z "$tag" ] || tag="v$tag"
fi
if [ -z "$tag" ]; then
  stop "No release tag vX.Y.Z at $url points at $sha.
  The workflow names the release in a comment, so pass a release."
fi

# mktemp -d without a template ignores TMPDIR on macOS.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/migrate-hook.XXXXXX")" || stop 'Cannot make a temporary folder.'
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

scrubbed git init -q --bare "$tmp/git" || stop "Cannot make a repository in $tmp."
# With no template, init.templateDir cannot add an info/attributes either.
scrubbed git init -q --bare --template= "$tmp/attr.git" ||
  stop "Cannot make a repository in $tmp."
bare fetch -q --depth 1 --no-tags "$url" "refs/tags/$tag" || stop "Cannot fetch $tag from $url."
fetched="$(bare rev-parse -q --verify 'FETCH_HEAD^{commit}')"
[ "$fetched" = "$sha" ] || stop "$tag at $url is $fetched now, not $sha."
rel="$tmp/release"
mkdir "$rel" || stop "Cannot make $rel."
bare archive --format=tar "$sha" | (cd "$rel" && tar -xf -) ||
  stop "Cannot unpack qoax-githooks $tag."
for f in commit-msg scripts/check-copy.sh scripts/sync-hook.sh scripts/hook-releases.txt \
  templates/gitignore templates/gitattributes templates/posix/setup-hooks.sh \
  templates/npm/install-git-hooks.mjs templates/.github/dependabot.yml \
  templates/.github/workflows/commit-conventions.yml; do
  [ -f "$rel/$f" ] || stop "qoax-githooks $tag has no $f. It is older than the tracked copy."
done
grep -q '@QOAX_GITHOOKS_SHA@' "$rel/templates/.github/workflows/commit-conventions.yml" ||
  stop "The workflow template of qoax-githooks $tag has no pin to fill in."

hook="$(bare rev-parse "$sha:commit-msg")"
sed -e "s/@QOAX_GITHOOKS_SHA@/$sha/" -e "s/@QOAX_GITHOOKS_TAG@/$tag/" \
  "$rel/templates/.github/workflows/commit-conventions.yml" >"$tmp/workflow.yml"
want_workflow="$(git hash-object --no-filters -- "$tmp/workflow.yml")"
want_dependabot="$(git hash-object --no-filters -- "$rel/templates/.github/dependabot.yml")"
ignore_rule="$(sed -n 1p "$rel/templates/gitignore")"
cr="$(printf '\r')"
start="$(git rev-parse HEAD)"

say "Migrating to qoax-githooks $tag ($sha)."

links="$(git ls-files -s | awk '$1 == "160000" { sub(/^[^\t]*\t/, ""); print }')"

if printf '%s\n' "$links" | grep -qxF .githooks/shared; then
  # The move changes files in one commit. All its checks come first, so a
  # stop leaves the clone as it was.
  problems=''
  if [ "$links" != .githooks/shared ]; then
    problem "More submodules than .githooks/shared: $(printf '%s' "$links" | tr '\n' ' ')
    This script moves only a repository whose one submodule is
    .githooks/shared. Move this repository fully by hand. A run after a part
    of the move cannot finish it, because the script needs .gitmodules gone."
  fi
  paths="$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null)"
  if [ "$(printf '%s\n' "$paths" | sed 's/^[^ ]* //')" != .githooks/shared ]; then
    problem ".gitmodules must name exactly one submodule, at .githooks/shared. It names:
$(printf '%s\n' "${paths:-nothing}" | sed 's/^/      /')"
  fi
  shim="$(entry "$copy")"
  case "$shim" in
    "100755 $SHIM" | "100644 $SHIM") ;;
    *)
      problem "$copy is '$shim', not the shim (blob $SHIM).
    Somebody changed it. Move the extra logic to a hook of its own, put the
    shim back, and commit that with --no-verify."
      ;;
  esac
  for pair in "scripts/setup-hooks.sh $OLD_SETUP_SH templates/posix/setup-hooks.sh" \
    "scripts/install-git-hooks.mjs $OLD_SETUP_MJS templates/npm/install-git-hooks.mjs"; do
    # shellcheck disable=SC2086
    set -- $pair
    b="$(blob_of "$1")"
    if [ -n "$b" ] && [ "$b" != "$2" ] && grep -qE "$CALLS_SUBMODULE" "$1"; then
      problem "$1 is blob $b, which this script does not know, and it runs git submodule.
    Remove the submodule step by hand, as in $3 of qoax-githooks $tag.
    Commit that with --no-verify, because the shim cannot run before the move."
    fi
  done
  if [ -f setup.cmd ]; then
    count="$(grep -cxF -e "$SETUP_CMD_LINE" -e "$SETUP_CMD_LINE$cr" setup.cmd)"
    if [ "$count" -gt 1 ] ||
      grep -vxF -e "$SETUP_CMD_LINE" -e "$SETUP_CMD_LINE$cr" setup.cmd |
      grep -qiE "$CALLS_SUBMODULE"; then
      problem "setup.cmd runs git submodule in a way that this script does not know.
    Remove those lines by hand. Commit that with --no-verify, because the shim
    cannot run before the move."
    fi
  fi
  if [ -f .githooks/.gitattributes ]; then
    problem ".githooks/.gitattributes can override the LF rule of the copy. Check it by hand."
  fi
  [ -z "$problems" ] || stop "Nothing changed. Fix these first:$problems"

  # git rm of the gitlink also edits .gitmodules, which goes next.
  git rm -q -- .githooks/shared || stop 'git rm .githooks/shared failed.'
  git rm -q -f -- .gitmodules || stop 'git rm .gitmodules failed.'

  # The redirect keeps the path, so the link in core.hooksPath now finds the
  # full hook.
  bare cat-file blob "$hook" >"$copy" || stop "Cannot write $copy."
  chmod 755 "$copy" || stop "Cannot make $copy executable."
  git add --chmod=+x -- "$copy" || stop "Cannot stage $copy."
  [ "$(entry "$copy")" = "100755 $hook" ] ||
    stop "git add staged '$(entry "$copy")' for $copy, not '100755 $hook'.
  A clean filter or an eol setting changed the bytes. To start again:
    git reset -q --hard HEAD"

  # Without the ignore rule, git add -A in an old clone commits its leftover
  # checkout back as a submodule.
  if [ ! -f "$ignore" ]; then
    cp "$rel/templates/gitignore" "$ignore" || stop "Cannot write $ignore."
  elif ! grep -qxF -- "$ignore_rule" "$ignore"; then
    append "$ignore" "$rel/templates/gitignore" || stop "Cannot write $ignore."
  fi
  git add -- "$ignore" || stop "Cannot stage $ignore."
  # With core.autocrlf=true and no rule, a checkout writes the hook with CRLF,
  # and then the hook rejects every commit.
  if ! lf_rule; then
    append .gitattributes "$rel/templates/gitattributes" || stop 'Cannot write .gitattributes.'
    git add -- .gitattributes || stop 'Cannot stage .gitattributes.'
    lf_rule || stop "The new rule in .gitattributes does not give $copy eol=lf. Another rule wins.
  To start again: git reset -q --hard HEAD"
  fi

  # Only the files that exist change, because a repository can lack scripts/.
  for pair in "scripts/setup-hooks.sh $OLD_SETUP_SH templates/posix/setup-hooks.sh" \
    "scripts/install-git-hooks.mjs $OLD_SETUP_MJS templates/npm/install-git-hooks.mjs"; do
    # shellcheck disable=SC2086
    set -- $pair
    if [ "$(blob_of "$1")" = "$2" ]; then
      cat "$rel/$3" >"$1" || stop "Cannot write $1."
      git add -- "$1" || stop "Cannot stage $1."
    fi
  done
  if [ -f setup.cmd ] &&
    grep -qxF -e "$SETUP_CMD_LINE" -e "$SETUP_CMD_LINE$cr" setup.cmd; then
    grep -vxF -e "$SETUP_CMD_LINE" -e "$SETUP_CMD_LINE$cr" setup.cmd >"$tmp/setup.cmd"
    cat "$tmp/setup.cmd" >setup.cmd || stop 'Cannot write setup.cmd.'
    git add -- setup.cmd || stop 'Cannot stage setup.cmd.'
  fi

  # The link in core.hooksPath runs the new hook on this message.
  git commit -q -m 'build: track a copy of the commit-msg hook' ||
    stop "git commit failed. The change is staged. To start again:
    git reset -q --hard HEAD"
  say 'done: build: track a copy of the commit-msg hook'
elif [ -n "$(printf '%s\n' "$links" | grep '^\.githooks/')" ]; then
  stop "A submodule entry is under .githooks, but not at .githooks/shared:
$(printf '%s\n' "$links" | grep '^\.githooks/' | sed 's/^/  /')
  Move this repository by hand."
fi

# The repository has no gitlink at .githooks/shared now. Each part of the
# move must be there, at this release.
problems=''
have="$(entry "$copy")"
if [ "$have" != "100755 $hook" ]; then
  case "$have" in
    *" $SHIM") problem "$copy is still the shim, but the submodule is gone." ;;
    100755\ *)
      problem "$copy is blob ${have#* }, not the hook of $tag (blob $hook).
    The repository has moved already. To change the release of the copy, run
    scripts/sync-hook.sh of qoax-githooks with --ref $tag."
      ;;
    *) problem "$copy is '$have', not '100755 $hook'." ;;
  esac
fi
if [ -n "$(entry .gitmodules)" ]; then
  others="$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null |
    sed 's/^[^ ]* //' | grep -vxF .githooks/shared)"
  if [ -n "$others" ]; then
    problem ".gitmodules names other submodules: $(printf '%s' "$others" | tr '\n' ' ')
    This script cannot finish a repository that keeps other submodules.
    Finish the move by hand."
  else
    problem '.gitmodules is still there.'
  fi
fi
if [ ! -f "$ignore" ] || ! grep -qxF -- "$ignore_rule" "$ignore"; then
  problem "$ignore lacks the line $ignore_rule."
fi
lf_rule || problem "No rule in .gitattributes gives $copy eol=lf."
[ "$(blob_of scripts/setup-hooks.sh)" != "$OLD_SETUP_SH" ] ||
  problem 'scripts/setup-hooks.sh is still the old template.'
[ "$(blob_of scripts/install-git-hooks.mjs)" != "$OLD_SETUP_MJS" ] ||
  problem 'scripts/install-git-hooks.mjs is still the old template.'
if [ -f setup.cmd ] && grep -qxF -e "$SETUP_CMD_LINE" -e "$SETUP_CMD_LINE$cr" setup.cmd; then
  problem 'setup.cmd still runs git submodule update.'
fi
[ -z "$problems" ] || stop "This repository is not in a state that this script knows:$problems"

# A workflow or Dependabot file that is already done stays as it is, so a
# run after a hand edit keeps the edit. A known blob gets the template. Any
# other blob is a hand edit.
hand=''
workflow_blob="$(blob_of "$workflow")"
if [ "$workflow_blob" = "$want_workflow" ] || workflows_pinned; then
  workflow_state=done
elif known "$workflow_blob" "$OLD_WORKFLOWS"; then
  workflow_state=replace
else
  workflow_state=hand
  hand="$hand
  - $workflow, blob ${workflow_blob:-none, the file is missing}
    Edit it by hand. The job must run this step after actions/checkout
    with fetch-depth: 0:
      uses: qoax-community/qoax-githooks@$sha # $tag
    No workflow may call the reusable workflow of qoax-reusables. The
    template is templates/.github/workflows/commit-conventions.yml of
    qoax-githooks $tag.
    Commit it as: ci: pin the qoax-githooks commit check"
fi
dependabot_blob="$(blob_of "$dependabot")"
if [ "$dependabot_blob" = "$want_dependabot" ] || dependabot_moved; then
  dependabot_state=done
elif known "$dependabot_blob" "$OLD_DEPENDABOTS"; then
  dependabot_state=replace
else
  dependabot_state=hand
  hand="$hand
  - $dependabot, blob ${dependabot_blob:-none, the file is missing}
    Edit it by hand. Delete the gitsubmodule entry. A github-actions entry
    must be able to bump qoax-community/qoax-githooks, as in
    templates/.github/dependabot.yml of qoax-githooks $tag. No ignore of
    that entry may name it, and its allow list must name it, if it has one.
    Commit it as: ci: let Dependabot bump the qoax-githooks pin"
fi

if [ "$workflow_state" = replace ]; then
  mkdir -p .github/workflows || stop 'Cannot make .github/workflows.'
  cat "$tmp/workflow.yml" >"$workflow" || stop "Cannot write $workflow."
  git add -- "$workflow" || stop "Cannot stage $workflow."
  git commit -q -m 'ci: pin the qoax-githooks commit check' ||
    stop "git commit failed. The change is staged."
  say 'done: ci: pin the qoax-githooks commit check'
fi
if [ "$workflow_state" != hand ] && [ "$dependabot_state" = replace ]; then
  cat "$rel/templates/.github/dependabot.yml" >"$dependabot" || stop "Cannot write $dependabot."
  git add -- "$dependabot" || stop "Cannot stage $dependabot."
  git commit -q -m 'ci: let Dependabot bump the qoax-githooks pin' ||
    stop "git commit failed. The change is staged."
  say 'done: ci: let Dependabot bump the qoax-githooks pin'
fi
if [ -n "$hand" ]; then
  stop "This script does not know the blob of these files:$hand
  Then run this script again with --ref $tag. It goes on from here.
  Nothing is pushed."
fi

say ''
say 'self-test:'
failed=0
check_failed() {
  failed=1
  printf '  FAIL %s\n' "$1"
  [ -z "${2-}" ] || printf '%s\n' "$2" | sed 's/^/       /'
}
out="$(
  unset COPY STALE_COPY GITHUB_ACTIONS GITHUB_ACTION_PATH GITHUB_WORKSPACE
  bash "$rel/scripts/check-copy.sh" 2>&1
)" && say "  $out" || check_failed 'check-copy.sh of the release' "$out"
printf 'bad message\n' >"$tmp/bad"
printf 'chore: test the hook\n' >"$tmp/good"
COMMIT_MSG_REPORT_ONLY=1 "./$copy" "$tmp/bad" >"$tmp/bad.out" 2>&1
rc=$?
if [ "$rc" = 1 ]; then
  say "  ok: the hook rejects 'bad message'."
else
  check_failed "the hook gives rc $rc for 'bad message', not 1. Does bash 4 or later run it?" \
    "$(tail -n 5 "$tmp/bad.out")"
fi
if out="$(COMMIT_MSG_REPORT_ONLY=1 "./$copy" "$tmp/good" 2>&1)"; then
  say "  ok: the hook accepts 'chore: test the hook'."
else
  check_failed "the hook rejects 'chore: test the hook'." "$out"
fi
out="$(QOAX_GITHOOKS_URL="$url" sh "$rel/scripts/sync-hook.sh" --check 2>&1)" &&
  say "  $out" || check_failed 'sync-hook.sh --check of the release' "$out"
ignore_entry="$(entry "$ignore")"
if [ "$(entry "$copy")" = "100755 $hook" ] && [ "${ignore_entry%% *}" = 100644 ] &&
  [ -z "$(entry .gitmodules)" ] &&
  [ -z "$(git ls-files -s -- .githooks | awk '$1 == "160000"')" ]; then
  say "  ok: the index has $copy (100755) and $ignore, no .gitmodules and no gitlink."
else
  check_failed 'the index of .githooks and .gitmodules' \
    "$(git ls-files -s -- .githooks .gitmodules)"
fi
status="$(git status --porcelain)"
if [ -z "$status" ]; then
  say '  ok: git status is clean.'
else
  check_failed 'git status is not clean.' "$status"
fi

say ''
if [ "$start" = "$(git rev-parse HEAD)" ]; then
  say 'This run made no commit. The repository is already migrated.'
else
  say 'The commits of this run:'
  git log --format='  %h %s' "$start..HEAD"
  say ''
  say "The diff of this run, without the hook itself (blob $hook):"
  git --no-pager diff --stat "$start" HEAD
  git --no-pager diff "$start" HEAD -- . ':(exclude).githooks/commit-msg'
fi
if git rev-parse -q --verify refs/remotes/origin/HEAD >/dev/null; then
  say ''
  say 'Against origin/HEAD:'
  git --no-pager diff --stat origin/HEAD HEAD
fi

# The docs stay a hand edit, because they differ in each repository.
say ''
# The setup templates name .githooks/shared in their clean-up note, so
# scripts/ stays out of the list. A setup script of its own comes back in,
# because it can still need the submodule.
own_setup=''
for pair in "scripts/setup-hooks.sh templates/posix/setup-hooks.sh" \
  "scripts/install-git-hooks.mjs templates/npm/install-git-hooks.mjs"; do
  # shellcheck disable=SC2086
  set -- $pair
  b="$(blob_of "$1")"
  if [ -n "$b" ] && [ "$b" != "$(git hash-object --no-filters -- "$rel/$2")" ]; then
    own_setup="$own_setup $1"
  fi
done
mentions_in() {
  git grep -n -I -i -E -e submodule -e 'shim([^m]|$)' -e 'githooks/shared' \
    -e qoax-reusables -- "$@" 2>/dev/null
}
# A minified file can match with one line of a megabyte, so long lines are
# cut. Lock files name npm packages such as es-shim-unscopables.
mentions="$(
  {
    mentions_in ':!.githooks/commit-msg' ':!scripts/' ':!*package-lock.json' \
      ':!*pnpm-lock.yaml' ':!*yarn.lock'
    for f in $own_setup; do
      mentions_in "$f"
    done
  } | awk '{ if (length($0) > 160) print substr($0, 1, 160) " [cut]"; else print }'
)"
if [ -n "$mentions" ]; then
  say 'Check these lines by hand. Each names the submodule, the shim or qoax-reusables.'
  say 'Edit the ones that describe the old layout, and commit them as'
  say "'docs: describe the tracked hook copy':"
  printf '%s\n' "$mentions" | sed 's/^/  /'
else
  say 'No line names the submodule, the shim or qoax-reusables.'
fi
for f in $own_setup; do
  say "$f is not the template of qoax-githooks $tag, so it stays as it is."
  say "  Check by hand that it needs nothing from .githooks/shared."
done
setup=''
for f in scripts/setup-hooks.sh scripts/install-git-hooks.mjs setup.cmd; do
  [ -f "$f" ] && setup="$setup $f"
done
for f in lefthook.yml lefthook.yaml .lefthook.yml .lefthook.yaml; do
  [ -f "$f" ] || continue
  setup="$setup $f"
  if grep -qF "$copy" "$f"; then
    say "$f runs $copy. That keeps working, with no core.hooksPath."
  else
    say "$f does not run $copy. Add a commit-msg job that runs it."
  fi
done
if [ -z "$setup" ]; then
  say "No setup script sets core.hooksPath here. Without one, nobody runs $copy locally."
fi

say ''
if [ "$failed" = 1 ]; then
  stop 'The self-test failed. Nothing is pushed.'
fi
say 'The self-test passed. Nothing is pushed. Review the commits, then push the branch.'
