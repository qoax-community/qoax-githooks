#!/usr/bin/env bash
#
# What the hook keeps below a scissors line, across cleanup modes and comment
# characters. git cuts at one exact line and nothing else, and every part of
# that has been wrong at some point, so all of it is pinned here.
# sc.sh — scissors handling across cleanup modes. Prints "failures: N".
H="$1"; D="$(mktemp -d)"; fails=0
r(){ local name="$1" mode="$2" want="$3" msg="$4" out rc st
  printf '%b' "$msg" > "$D/m"
  out="$(NO_COLOR=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.cleanup \
        GIT_CONFIG_VALUE_0="$mode" bash "$H" "$D/m" 2>&1)"; rc=$?
  st="ok  "; [ "$rc" = "$want" ] || { st="FAIL"; fails=$((fails+1)); }
  printf '%s %-38s mode=%-9s exit=%s  %s\n' "$st" "$name" "$mode" "$rc" \
    "$(printf '%s\n' "$out" | grep -F '·' | sed 's/^ *//' | paste -sd' | ' -)"
}
M='# ------------------------ >8 ------------------------'
r "authored marker then git marker+diff" verbatim 1 "feat: valid subject\n\n$M\nReviewed by: Alice\n\n$M\ndiff --git a/x b/y\nindex 1..2\n"
r "git marker + diff only"               verbatim 0 "feat: valid subject\n\nBody.\n\n$M\ndiff --git a/x b/y\n"
r "authored marker, no diff"             verbatim 1 "feat: valid subject\n\n$M\nReviewed by: Z"
r "authored marker, no diff"             strip    1 "feat: valid subject\n\n$M\nReviewed by: Z"
r "scissors mode cuts at the first"      scissors 0 "feat: valid subject\n\n$M\nReviewed by: Z"
r "diff pasted with no marker"           verbatim 1 "feat: x\n\ndiff --git a/b b/c\nReviewed by: Z"
r "two authored markers, no diff"        verbatim 1 "feat: x\n\n$M\nBody.\n\n$M\nReviewed by: Z"
r "loose marker is content"              scissors 1 "feat: x\n\nx-- >8 --\nReviewed by: Z"
r "short rule of dashes is content"      scissors 1 "feat: x\n\n# --- >8 ---\nReviewed by: Z"
r "text after the rule is content"       scissors 1 "feat: x\n\n# ------------------------ >8 ------------------------ x\nReviewed by: Z"
r "alnum commentChar marker"             verbatim 0 "feat: x\n\na ------------------------ >8 ------------------------\ndiff --git a/x b/y\n"
# core.commentChar decides the opener; unset means "#".
cc(){ local name="$1" cc="$2" want="$3" msg="$4" out rc st
  printf '%b' "$msg" > "$D/m"
  out="$(NO_COLOR=1 GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.cleanup GIT_CONFIG_VALUE_0=scissors \
        GIT_CONFIG_KEY_1=core.commentChar GIT_CONFIG_VALUE_1="$cc" bash "$H" "$D/m" 2>&1)"; rc=$?
  st="ok  "; [ "$rc" = "$want" ] || { st="FAIL"; fails=$((fails+1)); }
  printf '%s %-38s cc=%-6s exit=%s\n' "$st" "$name" "$cc" "$rc"; }
R=' ------------------------ >8 ------------------------'
cc "x opener under commentChar=#"  '#'  1 "feat: x\n\nx$R\nReviewed by: Z"
cc "x opener under commentChar=x"  'x'  0 "feat: x\n\nx$R\nReviewed by: Z"
cc "x opener under commentChar=auto" auto 0 "feat: x\n\nx$R\nReviewed by: Z"
cc "hash opener under commentChar=x" 'x' 1 "feat: x\n\n#$R\nReviewed by: Z"

echo "failures: $fails"
