#!/usr/bin/env bash
#
# Degenerate messages through every cleanup mode, with report-only on and off.
# Nothing is asserted about the findings: this looks only for a crash, an exit
# code that is neither 0 nor 1, or a shell diagnostic leaking into the report.
H="$1"; D="$(mktemp -d)"; bad=0; n=0
msgs=( '' ':' '::' 'feat' 'feat:' 'feat::' 'feat: ' 'feat: !' ' ' $'\t' $'\n\n\n' $'#\n#\n#'
       $'feat: x\n\nRefs:  ' $'feat: x\n\nRefs:\t' $'feat: x\n\nRefs  #' $'feat: x\n\nRefs#42'
       $'feat: x\n\nBREAKING CHANGE #' $'feat: x\n\nBREAKING\tCHANGE #x'
       $'feat: 👨‍👩‍👧‍👦🇬🇧1️⃣⚠️.\n\n🚀' $'feat: x\n\nCo-authored-by: <>'
       $'# --- >8 ---\ndiff --git a/x b/y' $'feat: x\n\n# --- >8 ---\n# --- >8 ---\ndiff --git a/x b/y'
       $'feat (  ) : x' $' feat: x' $'  :  ' $'feat: x\n\nA-b  #1' )
for mode in default verbatim whitespace strip scissors; do
  for m in "${msgs[@]}"; do
    printf '%s' "$m" > "$D/f"
    for ro in '' '1'; do
      out="$(NO_COLOR=1 COMMIT_MSG_REPORT_ONLY="$ro" GIT_CONFIG_COUNT=1 \
             GIT_CONFIG_KEY_0=commit.cleanup GIT_CONFIG_VALUE_0="$mode" \
             bash "$H" "$D/f" 2>&1)"; rc=$?; n=$((n+1))
      case "$rc" in 0|1) ;; *) echo "RC$rc mode=$mode ro=$ro $(printf %q "$m")"; bad=1;; esac
      case "$out" in
        *"bad array subscript"*|*"unbound variable"*|*"$H: line"*|*"invalid arithmetic"*|*"printf:"*)
          echo "DIAG mode=$mode ro=$ro $(printf %q "$m")"; printf '%s\n' "$out" | head -3; bad=1;;
      esac
    done
  done
done
echo "fuzz clean=$((1-bad)) ($n runs)"
