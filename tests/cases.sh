#!/usr/bin/env bash
# One message per case: the expected exit code, then the message itself.
# A case also fails if the hook leaks a shell diagnostic, which is how a
# bad array subscript went unnoticed until a reviewer found it.
H="$1"; D="$(mktemp -d)"; fails=0
report_only=0

t(){ local name="$1" want="$2" msg="$3" out rc st
  printf '%s' "$msg" > "$D/m"
  if ((report_only)); then
    out="$(NO_COLOR=1 COMMIT_MSG_REPORT_ONLY=1 "$H" "$D/m" 2>&1)"; rc=$?
  else
    out="$(NO_COLOR=1 "$H" "$D/m" 2>&1)"; rc=$?
  fi
  st="ok  "; [ "$rc" = "$want" ] || { st="FAIL"; fails=$((fails + 1)); }
  case "$out" in *"bad array subscript"*|*"unbound variable"*|*": line "*)
    st="FAIL"; fails=$((fails + 1)) ;;
  esac
  printf '%s %-36s exit=%s  %s
' "$st" "$name" "$rc"     "$(printf '%s
' "$out" | grep -E '^[[:space:]]+(✗|!) ' | sed 's/^ *//' | paste -sd' | ' -)"
}

echo "--- valid messages must still pass ---"
t "plain" 0 'feat(lang): add polish language'
t "breaking + footers" 0 'refactor!: drop support for node 18

BREAKING CHANGE: uses stdlib APIs from node 20+

Refs: #123
Reviewed-by: someone'
t "multi-paragraph body" 0 'fix: prevent racing of requests

Introduce a request id and a reference to latest request.

Remove timeouts which were used to mitigate the racing issue.

Reviewed-by: Z
Refs: #123'
t "conventional revert" 0 'revert: let us never again speak of the noodle incident

Refs: 676104e, a215868'
t "scope that ends in -ed" 0 'feat(shared): add helper'
t "noun first word ending -ing" 0 'feat: string handling for names'
t "prose with a colon at the end" 0 'chore(hooks): add commit-msg hook

Enable locally with: git config core.hooksPath .githooks'
echo "--- house style now blocks ---"
t "uppercase type" 1 'FEAT: add thing'
t "unknown type" 1 'wibble: do a thing'
t "typo type" 1 'feet: add polish language'
t "long subject" 1 "feat: $(python3 -c 'print("x"*85)')"
t "capital + period" 1 'feat: Add the thing.'
t "past tense" 1 'feat: added the thing'
t "uppercase scope" 1 'feat(Auth): add login'
# git strips this before the hook sees it in every mode but verbatim, where it
# is rejected — covered separately against a repo with commit.cleanup=verbatim.
t "trailing whitespace (git strips it)" 0 'feat: add thing   '
t "long body line" 1 "docs: x

$(python3 -c 'print("word "*25)')"
t "issue ref in subject" 1 'fix: prevent race, closes #42'
t "security type is allowed" 0 'security: upgrade dependencies'
echo "--- spec MUSTs ---"
t "no separator" 1 'Added stuff'
t "empty scope" 1 'feat(): x'
t "double scope" 1 'feat(api)(ui): add page'
t "no blank after subject" 1 'feat: x
glued'
t "footer token spaces" 1 'feat: x

Reviewed by: Z'
t "lowercase breaking change" 1 'feat: x

breaking change: it broke'
echo "--- this round's copilot fixes ---"
t "dashed AI trailer" 1 'feat: x

Generated-with: Copilot'
t "spaced token earlier para" 1 'fix: y

Reviewed by: Alice

Refs: #1'
t "comment above subject" 1 '# note
feat: add hook'
echo "--- scissors, attribution reach, autosquash title ---"
t "hand-typed scissors + bad footer" 1 'feat: valid subject

# ------------------------ >8 ------------------------
Reviewed by: Z'
t "verbose diff below scissors" 0 'feat: x

# ------------------------ >8 ------------------------
diff --git a/f b/f
+++ b/f
@@ -1 +1 @@'
t "AI trailer with prose after it" 1 'feat: x

Co-authored-by: Copilot <bot@github.com>

More details.'
t "prose naming a tool" 0 'fix: y

remove text generated with Copilot from the footer'
t "BREAKING CHANGES prose paragraph" 1 'feat: x

BREAKING CHANGE: remove v1

BREAKING CHANGES are documented below'
printf '%s' 'fixup! feat: add hook' > "$D/m"
COMMIT_MSG_NO_AUTOSQUASH=1 NO_COLOR=1 COMMIT_MSG_REPORT_ONLY=1 "$H" "$D/m" >/dev/null 2>&1 \
  && { echo "FAIL autosquash title accepted"; fails=$((fails+1)); } || echo "ok   autosquash title rejected"
NO_COLOR=1 COMMIT_MSG_REPORT_ONLY=1 "$H" "$D/m" >/dev/null 2>&1 \
  && echo "ok   autosquash commit exempt" || { echo "FAIL autosquash commit rejected"; fails=$((fails+1)); }

t "empty first word" 1 'feat:: add hook'
t "dash attribution trailer" 1 'feat: add hook

Generated-by: Copilot'
t "created-with trailer" 1 'feat: add hook

Created-with: Claude'
t "prose --- under scissors" 1 'feat: add hook

# ------------------------ >8 ------------------------
--- old behaviour
Reviewed by: Alice'

t "double-space breaking change" 1 'feat: add hook

BREAKING  CHANGE: remove v1'
t "assisted-by trailer" 1 'feat: add hook

Assisted-by: Copilot'
t "indented subject columns" 1 ' feat: Added hook'
t "stranded footer paragraph" 1 'feat: add hook

Refs: #1

More details.'
t "stacked footer paragraphs" 0 'feat: add hook

Body text here.

BREAKING CHANGE: y

Refs: #1'

echo "--- round 9 ---"
t "tab after footer colon" 1 'feat: x

Refs:	Refs42'
t "tab after BREAKING colon" 1 'feat!: x

BREAKING CHANGE:	remove v1'
t "no space after BREAKING colon" 1 'feat!: x

BREAKING CHANGE:remove v1'
t "closing keyword cross-repo" 1 'feat: close owner/repo#42'
t "closing keyword url" 1 'feat: close https://github.com/o/r/issues/42'
t "plain #42 still fine" 0 'feat: mention #42 in the docs'
t "tab-separated long line" 1 "docs: x

$(python3 -c 'print("\t".join(["word"]*40))')"
t "spaced token, no space sep" 1 'feat: x

Reviewed by:Alice'
t "human named like a tool" 0 'feat: x

Co-authored-by: Claude Shannon <claude@example.com>'
t "agent coauthor by domain" 1 'feat: x

Co-authored-by: Claude <noreply@anthropic.com>'
t "agent coauthor by bot tag" 1 'feat: x

Co-authored-by: copilot-swe-agent[bot] <x@y.com>'
t "prose ending in a colon" 0 'docs: x

This does the following:
- a
- b'

echo "--- round 10 ---"
t "scope column past a space" 1 'feat (Auth): add x'
t "scope column inside spaces" 1 'feat( Auth ): add x'
t "attribution, no space sep" 1 'feat: x

Generated-by:Copilot'
t "attribution, double space" 1 'feat: x

Generated  by: Copilot'
t "attribution, double dash" 1 'feat: x

Generated--by: Copilot'
t "tab inside BREAKING token" 1 'feat!: x

BREAKING	CHANGE: remove v1'
t "canonical breaking still ok" 0 'feat!: x

BREAKING CHANGE: remove v1'
t "dashed breaking still ok" 0 'feat!: x

BREAKING-CHANGE: remove v1'

echo "--- round 11 ---"
t "doubled space before hash" 1 'feat: x

Refs  #42'
t "tab before hash" 1 'feat: x

Refs	#42'
t "hash separator is valid" 0 'feat: x

Refs #42'
t "lowercase breaking, hash form" 1 'feat!: x

breaking change #remove v1'
t "breaking change hash form ok" 0 'feat!: x

BREAKING CHANGE #remove v1'
t "breaking change hash, no value" 1 'feat!: x

BREAKING CHANGE #'
t "non-imperative plus bang" 1 'feat: added!'
t "non-imperative plus question" 1 'feat: added?'
t "version in description" 0 'feat: v1.2 bump support'

echo "--- round 12 ---"
t "doubled space after colon" 1 'feat: x

Refs:  #42'
t "single space after colon" 0 'feat: x

Refs: #42'

echo "--- round 13 ---"
t "bare footer token" 1 'feat: x

Refs:'
t "generic AI attribution" 1 'feat: x

Generated-by: AI'
t "spaced token, colon no space" 1 'feat: x

Generated by:Copilot'
t "missing description" 1 'feat:'

echo "--- report-only (CI over a stored message) ---"
report_only=1
t "stored '#' line is body text" 1 'feat: add hook
# body'
t "stored scissors line is content" 1 'feat: add hook

# ------------------------ >8 ------------------------
Reviewed by: Z'
t "stored message from git log %B" 0 'feat: add hook

A body paragraph.
'
report_only=0

echo "--- round 14 ---"
t "mixed dashed and spaced token" 1 'feat: x

Signed-off by: Alice'

echo "failures: $fails"
