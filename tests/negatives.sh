#!/usr/bin/env bash
#
# Messages that must NOT be rejected. Several rules here are deliberately
# fuzzy — an attribution trailer, a generic "AI" — and the cost of getting one
# wrong is a real contributor blocked, so each has a counter-case.
H="$1"; D="$(mktemp -d)"; fails=0
n(){ local want="$1" name="$2" msg="$3" rc
  printf '%b' "$msg" > "$D/m"; NO_COLOR=1 bash "$H" "$D/m" >/dev/null 2>&1; rc=$?
  local st="ok  "; [ "$rc" = "$want" ] || { st="FAIL"; fails=$((fails+1)); }
  printf '%s want=%s got=%s  %s\n' "$st" "$want" "$rc" "$name"; }
n 0 "human whose name contains ai" 'feat: x\n\nCo-authored-by: Ai Tanaka <ai@example.com>'
n 0 "maintainer in a trailer"      'feat: x\n\nReviewed-by: The Maintainer <m@x.com>'
n 0 "prose mentioning a chain"     'docs: x\n\nThe chain of AI-adjacent words: maintainer, aircraft, plait.'
n 0 "trailer value with aircraft"  'feat: x\n\nRefs: aircraft-42'
n 1 "generic AI attribution"       'feat: x\n\nGenerated-by: AI'
n 1 "generic ai lowercase"         'feat: x\n\nGenerated with: an ai'
n 0 "valid footers"                'feat: x\n\nRefs: #1\nReviewed-by: Z'
n 0 "footer value is a colon word" 'feat: x\n\nRefs: see also: #1'
echo "failures: $fails"
