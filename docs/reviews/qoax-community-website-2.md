# Review history — qoax-community/qoax-community-website#2

The `commit-msg` hook was written in a pull request against the community
website, before it had a repository of its own. This is that review, kept
here because it is the only record of why a good many of the hook's rules
look the way they do.

- **Pull request:** [qoax-community/qoax-community-website#2](https://github.com/qoax-community/qoax-community-website/pull/2) — chore(hooks): add conventional commits commit-msg hook
- **Opened:** 2026-09-07 19:49:34 UTC
- **Review threads:** 38 (37 resolved, 32 since made obsolete by a later change)
- **Inline comments:** 76 · **review summaries:** 16 · **conversation comments:** 11

GitHub cannot move a pull request between repositories, so nothing here is
live: the threads are not resolvable and the line numbers refer to
`.githooks/commit-msg` as it stood in that branch, which is `commit-msg`
here. Diff excerpts are trimmed to the last few lines of each hunk.

---

## Review threads

### 1. `.githooks/commit-msg` line 21 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 19:51:37 UTC

```diff
@@ …
+#   commitMsg.types         space separated list of allowed types
+#   commitMsg.subjectMax    max subject length      (default 72)
+#   commitMsg.bodyMax       max body line length    (default 100)
+#
+set -uo pipefail
+
+readonly SPEC_URL='https://www.conventionalcommits.org/en/v1.0.0/'
+readonly DEFAULT_TYPES=(feat fix docs style refactor perf test build ci chore revert)
```

> This hook relies on Bash 4+ features (e.g. `declare -A`, `${var,,}` / `${var,}`), but macOS still commonly ships Bash 3.2 as `/bin/bash`. Without an explicit version check, contributors on older Bash will get confusing syntax errors during `git commit` instead of a clear message.

**angel-penchev** · 2026-09-07 19:59:18 UTC

> Fixed in 6e48310. You are right that `env bash` can land on 3.2 - the hook needs 4+ for `declare -A`, `${var,,}` and `printf -v`.
>
> Rather than only reporting the problem, the hook now tries to solve it: on bash < 4 it probes `/opt/homebrew/bin/bash`, `/usr/local/bin/bash`, `/usr/bin/bash` and `/bin/bash`, asks each one for its own `BASH_VERSINFO[0]`, and re-execs into the first that reports 4+. A `COMMIT_MSG_HOOK_REEXEC` sentinel makes a second re-exec impossible, so a candidate that misreports its version cannot cause an exec loop.
>
> If no modern bash exists, it prints the version it found, points at `brew install bash`, says plainly that conventions are not being checked, and exits 0. Failing open is deliberate: a hook that blocks every commit on a contributor's Mac tends to get disabled outright, which enforces less than a loud warning does. Happy to flip it to a hard failure if you would rather have the stricter default.

### 2. `.githooks/commit-msg` line 160 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 19:51:37 UTC

```diff
@@ …
+# verbose diff below the scissors line, drop comments, normalise CRLF, then trim
+# blank lines from both ends.
+read_message() {
+  local msg_file="$1" cleaned
+
+  cleaned="$(sed -e '/^# *-\{2,\} >8 -\{2,\}/,$d' -e 's/\r$//' -e '/^#/d' "$msg_file")"
+  cleaned="$(printf '%s\n' "$cleaned" | sed -e '/./,$!d' | tac | sed -e '/./,$!d' | tac)"
+
```

> `read_message` uses `tac` to trim leading/trailing blank lines. `tac` is not available by default on macOS/BSD, so the hook will fail in common contributor environments even if Bash is available.

**angel-penchev** · 2026-09-07 19:59:20 UTC

> Fixed in 6e48310. Correct - `tac` is GNU-only, and BSD would need `tail -r`.
>
> Rather than swap one external for another, `read_message` now reads the file with a bash `while IFS= read -r` loop: it strips the trailing `\r`, breaks at the verbose-diff scissors line, skips comment lines, and trims blank lines from both ends by walking two indices inward. The `sed` calls went with it, so the hook now shells out to nothing but `git` and behaves identically on Linux, macOS and BSD.
>
> Verified behaviour-preserving: a 31-case battery (valid subjects, breaking-change footers, multi-paragraph bodies, merge/fixup/revert subjects, every subject-shape failure, CRLF input, a scissors block, fenced code, empty and comments-only messages) produces byte-identical output and exit codes before and after the rewrite.

### 3. `.githooks/commit-msg` line 468 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 19:51:37 UTC

```diff
@@ …
+      --fix 'e.g. (auth), (api/routes), (legal.terms)'
+
+  elif [[ $SUBJECT_SCOPE =~ (ing|ed)$ || $SUBJECT_SCOPE =~ ^(add|fix|update|remove|refactor) ]]; then
+    warning subject "scope \"${SUBJECT_SCOPE}\" reads like a verb" \
+      --at 1 "$col" "${#SUBJECT_SCOPE}" \
+      --why 'a scope names a section of the codebase, not the action performed on it' \
+      --fix 'e.g. "feat(auth):" rather than "feat(adding-auth):"'
+  fi
```

> The caret positioning for the empty-scope error is off by one: for `feat(): ...` the `--at` column starts after `(`, so the underline points at `):` instead of `()`. This makes the report less actionable.

**angel-penchev** · 2026-09-07 19:59:21 UTC

> Fixed in 6e48310. Confirmed off by one: the column was computed as `${#SUBJECT_TYPE} + 2`, which is right when the caret points at scope *text* (`feat(auth)` → the `a`), but this particular finding underlines the parentheses themselves, so it has to start one column earlier.
>
> Now `--at 1 $((col - 1)) 2`, which gives:
>
> ```
>   ✗ subject · empty scope "()"
>      │ feat(): x
>      │     ^^
> ```
>
> That was the only diff in the regression battery output, which is how I confirmed the change is scoped to this one finding and did not shift any other caret.

### 4. `.githooks/commit-msg` line 227 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:34:42 UTC

```diff
@@ …
+  done <"$msg_file"
+
+  marker="$(resolve_comment_char ${raw[@]+"${raw[@]}"})"
+
+  for line in ${raw[@]+"${raw[@]}"}; do
+    # Everything from the scissors line down is the verbose diff, not message.
+    [[ $line == "$marker"* && $line == *'>8'* && $line == *--* ]] && break
+    [[ $line == "$marker"* ]] && continue
```

> Comments are removed unconditionally even when Git will preserve them. With `--cleanup=verbatim` (and the default `whitespace` cleanup used for non-edited `-m` messages), a message such as `# note\nfeat: add hook` is stored with `# note` as its subject, while this hook drops that line and accepts `feat: add hook`. Likewise, a comment immediately after a valid subject can hide the missing blank line. The validator must not discard content that the selected Git cleanup mode keeps, or must conservatively reject structures whose validity depends on stripping it.

**angel-penchev** · 2026-09-07 22:50:12 UTC

> Fixed in 84987be. Confirmed, and the second half of your comment was the sharper case: `feat: add hook` + `# note` was *accepted* by the hook while git stored both lines, so the stripping hid a real "no blank line after the subject" violation. Verified against the stored object, not the hook's own view.
>
> Two changes. `commit.cleanup` is now honoured: only `strip` removes comments, while `whitespace` (what a `-m` message gets), `verbatim` and `scissors` keep them, so a `#` line under those modes is content and stays in the message the hook validates.
>
> With `commit.cleanup` unset git decides by whether it opened an editor, which a hook has no way to observe — the file is post-cleanup for `-m` and raw for the editor, and the two are indistinguishable on disk. Stripping stays the default because the editor path is the common one, but the ambiguous case is now reported rather than silently resolved: a comment standing where the subject belongs raises "a comment line stands where the subject belongs", explaining that git keeps it for `-m` and drops it for an edited message.
>
> One case I deliberately did not take the conservative route on: a comment on the line *directly after* the subject. That is exactly what git's own editor template looks like (`# Please enter the commit message…` lands on line 2), so rejecting it would fail nearly every default editor commit. Under `-m` it stays a hidden violation, and setting `commit.cleanup = whitespace` makes the hook exact for anyone who cares.

### 5. `.githooks/commit-msg` line 817 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:34:43 UTC

```diff
@@ …
+    # sentence, so it goes unreported rather than taking every sentence with it.
+    ((block_is_real)) || is_known_footer_token "${token// /-}" || continue
+
+    error footer "footer token \"${token}\" contains spaces" \
+      --at $((idx + 1)) 1 "${#token}" \
+      --why 'a footer token MUST use - in place of whitespace, e.g. Acked-by — that is what separates a footer from a multi-paragraph body' \
+      --fix "write \"${token// /-}: ...\""
+  done
```

> Starting this scan at `footer_start` misses known malformed tokens in earlier body paragraphs. For example, a `Reviewed by: Alice` paragraph followed by a separate `Refs: #1` footer sets `footer_start` to the `Refs` line, so the required spaced-token error is never reported. Scan the whole post-subject message, while limiting pre-footer matches to known normalized tokens so prose such as `Enable locally with:` remains ignored.

**angel-penchev** · 2026-09-07 22:50:14 UTC

> Fixed in 84987be. Reproduced exactly as described — `Reviewed by: Alice`, a blank line, then `Refs: #1` passed cleanly, because `footer_start` had moved to the `Refs` line and the scan began there.
>
> `check_footer_tokens` now walks every line after the subject. The tier logic moved with it rather than being dropped: inside a real footer block any spaced token is an error, and before that block, or in a paragraph with no well-formed footer in it, only a known token normalised through its dashed form is reported. So `Reviewed by: Alice` is caught wherever it sits, while `Enable locally with: git config …` in an earlier paragraph stays ignored — both covered by tests.

### 6. `.githooks/commit-msg` line 871 — resolved by Copilot, outdated

**Copilot** · 2026-09-07 22:34:43 UTC

```diff
@@ …
+    lowercase="${line,,}"
+
+    # A trailer, or the robot marker these tools sign off with. Prose that
+    # happens to name a tool is just prose.
+    looks_like_footer "$line" || [[ $line == 🤖* ]] || continue
+
+    if [[ $lowercase =~ ^co-authored-by:.*$agents ]] ||
+       [[ $lowercase =~ (generated[[:space:]]with|created[[:space:]]by).*$agents ]] ||
```

> Dashed attribution trailers are not rejected. For example, `Generated-with: Copilot` passes `looks_like_footer`, but this regex only matches whitespace between `generated` and `with`, so the hook exits successfully despite the stated repository policy. Accept a hyphen in these attribution phrases as well.

**angel-penchev** · 2026-09-07 22:50:15 UTC

> Fixed in 84987be. Correct — `Generated-with: Copilot` passed `looks_like_footer`, then missed the attribution pattern because it only allowed whitespace between the words. Both phrases now accept a hyphen or whitespace (`generated[[:space:]-]with`, `created[[:space:]-]by`), and the dashed form is in the test set.

### 7. `.github/workflows/commit-conventions.yml` line 74 — resolved by angel-penchev

**Copilot** · 2026-09-07 22:34:43 UTC

```diff
@@ …
+
+          # Validate the message in $1, labelled $2 for the log and summary.
+          check() {
+            local label="$2"
+            if "$hook" "$1" >"$output" 2>&1; then
+              printf '::notice::%s — ok\n' "$label"
+              return 0
+            fi
```

> Successful hook runs can still contain warnings, but this branch discards `$output` and emits only `ok`. Consequently all warning-only findings (unknown types, long subjects, trailing whitespace, etc.) disappear in CI instead of being printed as described. Emit the captured output before returning success.

**angel-penchev** · 2026-09-07 22:50:16 UTC

> Fixed in 84987be — the success branch now prints the captured output when it is non-empty, so nothing a passing run has to say is swallowed.
>
> Worth noting it is belt-and-braces as of this commit: the hook no longer emits warnings at all. Every finding is an error now, precisely because of the problem your comment points at — a warning passes the CI check and therefore says nothing about a commit that has already been written. Rather than have the workflow comment on finished work, anything worth reporting blocks at commit time. Two heuristics that were not certain enough to block on (a scope ending in `-ed` calling itself a verb, which fails `feat(shared)`, and a first word ending in `-ing` calling itself past tense, which fails `feat: string handling for names`) were deleted rather than promoted.

### 8. `.githooks/commit-msg` line 269 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:45 UTC

```diff
@@ …
+  ((first <= last)) && LINES=("${kept[@]:first:last - first + 1}")
+
+  return 0
+}
+
+# core.commentChar=auto makes git pick the first candidate character that no
+# line already starts with, so mirror that choice instead of assuming "#".
+# Takes the message lines as arguments.
```

> With `core.commentChar=auto`, this recomputes the marker from the post-editor buffer. Git's generated template lines already begin with the marker Git selected, so `resolve_comment_char` treats the real marker as unavailable and chooses the next character. Editor comments (and verbose diffs) are then validated as message content, which can reject otherwise valid commits. Detect the marker Git already used in the template/scissors block rather than rerunning the pre-editor selection algorithm.

**angel-penchev** · 2026-09-07 23:18:19 UTC

> Fixed in bc50ec2, and reproduced first: with `core.commentChar=auto` a normal editor commit was **rejected** with "missing the `: ` separator" and "no blank line after the subject", both invented from the template git had written.
>
> You identified the cause exactly — the marker git picked is not recoverable by rerunning the selection over a buffer that already contains the template. Rather than detect it from the template block, which would mean matching git's own wording in whatever locale it was written, the hook now stops imitating git's cleanup and runs the message through `git stripspace`, which resolves `auto` itself. That deleted the whole marker-selection routine.

### 9. `.githooks/commit-msg` line 295 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:46 UTC

```diff
@@ …
+}
+
+# Autosquash markers are written by git. So is a merge subject — but only
+# during an actual merge; "Merge the two config files" typed by hand is an
+# ordinary commit and gets checked like any other.
+is_generated_by_git() {
+  case "$1" in
+    fixup!*|squash!*|amend!*) return 0 ;;
```

> These patterns exempt any string beginning with an autosquash keyword, not just Git's `<marker> <subject>` form. For example, an invalid commit or PR title such as `fixup!not-a-generated-message` bypasses every validation rule. Require the literal space that Git emits after each marker.

**angel-penchev** · 2026-09-07 23:18:21 UTC

> Fixed in bc50ec2. Confirmed — `fixup!not-a-generated-message` bypassed every rule. The patterns now require the space git emits (`'fixup! '*`), so a marker is a marker and `fixup!nonsense` is just somebody's bad subject. A genuine `fixup! feat: …` is still exempt; both are in the test set.

### 10. `.github/workflows/commit-conventions.yml` line 79 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:46 UTC

```diff
@@ …
+          }
+
+          if [ "$EVENT_NAME" = pull_request ]; then
+            range="$(git merge-base "$BASE_SHA" "$HEAD_SHA")..${HEAD_SHA}"
+          elif [ -n "${PUSH_BEFORE#0000000000000000000000000000000000000000}" ]; then
+            range="${PUSH_BEFORE}..${PUSH_AFTER}"
+          else
+            range="${PUSH_AFTER}~1..${PUSH_AFTER}"
```

> When `before` is all zeros (a newly created `main`), this range contains only the tip commit, so earlier commits delivered by the same push are never validated. Use the full history reachable from `PUSH_AFTER` for this case so the workflow's “every commit” guarantee holds.

**angel-penchev** · 2026-09-07 23:18:22 UTC

> Addressed in e0686bb, though not the way you suggest, and the reason is worth recording.
>
> Checking everything reachable from `PUSH_AFTER` means the whole history on a branch that this push created. This repository's history contains three commits that predate the convention — `Launch QO.AX Community nonprofit archive`, `Update GitHub Actions runtime`, `Redesign QOAX Community site` — so that guarantee would fail the job permanently on history nobody can rewrite.
>
> The real defect was the silence, so that is what changed: the job still checks the tip, and now prints `::notice::branch created by this push — only its tip commit is checked`. The guarantee is stated accurately instead of being quietly overstated. Pull requests, where the range is well defined, remain fully covered.

### 11. `.github/workflows/commit-conventions.yml` line 85 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:46 UTC

```diff
@@ …
+          else
+            range="${PUSH_AFTER}~1..${PUSH_AFTER}"
+          fi
+
+          commits="$(git rev-list --no-merges --reverse "$range" 2>/dev/null || true)"
+          if [ -z "$commits" ]; then
+            commits="$(git rev-list --no-merges -1 "$PUSH_AFTER")"
+          fi
```

> A failed range enumeration is converted to an empty result and then silently replaced with only the latest non-merge commit. On a force-push where `PUSH_BEFORE` is no longer available locally, this lets all earlier commits in the rewritten history go unchecked. Distinguish a valid empty range from `rev-list` failure and fail the job (or explicitly fetch/enumerate the missing range) instead of degrading to one commit.

**angel-penchev** · 2026-09-07 23:18:24 UTC

> Fixed in e0686bb. Correct, and it was the more dangerous half of the two: `rev-list` failing was indistinguishable from an empty range, so after a force-push — when the old tip is genuinely gone from the checkout — every rewritten commit went unchecked and the job still reported success.
>
> Failure and emptiness are now separate. An unusable range prints `::error::cannot enumerate <range> …` and exits 1; a genuinely empty range says so and checks nothing, which is correct. Simulated both.

### 12. `.githooks/commit-msg` line 259 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:46 UTC

```diff
@@ …
+      [[ $line == "$marker"* ]] && SUBJECT_MAY_BE_COMMENT=1
+      break
+    done
+  fi
+
+  local first=0 last=$((${#kept[@]} - 1))
+  while ((first <= last)) && is_blank "${kept[first]}"; do first=$((first + 1)); done
+  while ((last >= first)) && is_blank "${kept[last]}"; do last=$((last - 1)); done
```

> Blank-line trimming is unconditional, but `commit.cleanup=verbatim` preserves leading and trailing blank lines. A verbatim message beginning with a blank line followed by `feat: add hook` is therefore accepted even though the stored message does not begin with a Conventional Commit subject. Preserve edge blank lines in verbatim mode while retaining trimming for cleanup modes that perform it.

**angel-penchev** · 2026-09-07 23:18:25 UTC

> Fixed in bc50ec2. Verified against the stored object first: with `commit.cleanup=verbatim`, a message opening with a blank line was accepted by the hook while git stored a commit whose subject is empty.
>
> Cleanup mode now decides what the hook validates, because git decides it: `verbatim` keeps the blank lines at both edges (that message is now rejected), `whitespace` and `scissors` keep comments, and the default runs `git stripspace --strip-comments`. The hook no longer trims anything itself.
>
> One deliberate consequence: trailing whitespace is now reported only under `verbatim`. Everywhere else git removes it before the hook is reached, so there is nothing left to reject.

### 13. `.githooks/commit-msg` line 533 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:47 UTC

```diff
@@ …
+  elif [[ $remainder != " "* ]]; then
+    SUBJECT_DESC="$remainder"
+    error subject 'missing space after the colon' \
+      --at 1 "$separator_col" 1 \
+      --why 'the separator is exactly ": " — colon followed by one space' \
+      --fix "write \"${prefix}: ${remainder}\""
+
+  elif [[ $remainder == "  "* ]]; then
```

> A tab after the required space is accepted here: `feat: \tadd parser` reaches the final branch and validates even though the separator contains extra whitespace. Check whether the remainder after the first space starts with any whitespace, not only a second literal space.

**angel-penchev** · 2026-09-07 23:18:26 UTC

> Fixed in bc50ec2. `feat: \tadd parser` did validate. The check compared against a second literal space; it now tests for any whitespace after the first one, so a tab is caught the same as a space. Renamed to "extra whitespace after the colon", since "more than one space" was not what it was looking at.

### 14. `.githooks/commit-msg` line 862 — resolved by angel-penchev

**Copilot** · 2026-09-07 22:58:47 UTC

```diff
@@ …
+    ((idx >= 1)) || break
+
+    # ...then rewind to where that paragraph starts.
+    while ((idx > 1)) && ! is_blank "${LINES[idx - 1]}"; do idx=$((idx - 1)); done
+    candidate=$idx
+
+    looks_like_footer "${LINES[candidate]}" || break
+    start=$candidate
```

> The rewind treats an earlier footer-looking paragraph as the footer block even when the actual final paragraph is ordinary body prose. Consequently `BREAKING CHANGE: remove v1`, followed by a blank line and `Further implementation details.`, exits successfully although the breaking-change footer is stranded before body content. Only extend backward when the final paragraph is itself a footer block.

**angel-penchev** · 2026-09-07 23:18:28 UTC

> Fixed in 37eb2c3. Reproduced exactly as written: `BREAKING CHANGE: remove v1`, a blank line, then `Further implementation details.` exited zero.
>
> The rewind existed so that `BREAKING CHANGE: …` above a blank line and `Refs: #1` reads as one footer section rather than a body and a footer. It had no business running when the message ends in prose, which is your point. It is now gated on the last paragraph being a footer block itself, so a message ending in body text has no footer block for anything to be rewound into, and the stranded breaking change is reported.

### 15. `.githooks/commit-msg` line 808 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:47 UTC

```diff
@@ …
+        --at "$line_no" 1 "${#line}" \
+        --why 'the token MUST be followed by a colon, a space and a description' \
+        --fix 'write "BREAKING CHANGE: environment variables now take precedence over config files"'
+    fi
+
+    # Footers stack inside one block, so only a breaking change stranded in
+    # the body is misplaced — "Refs: #42" directly above it is perfectly legal.
+    if ((idx < footer_start)); then
```

> This footer is considered correctly placed whenever it occurs after `footer_start`, even if that paragraph starts with body prose. Thus `Some prose` immediately followed by `BREAKING CHANGE: ...` is accepted without the required blank line. Also reject a later breaking-change line when the current paragraph did not start with a footer token.

**angel-penchev** · 2026-09-07 23:18:29 UTC

> Fixed in 37eb2c3. `Some prose` immediately followed by `BREAKING CHANGE: …` was accepted, since the line sat after `footer_start` and nothing looked at what opened the paragraph.
>
> A breaking change is now reported unless the paragraph it belongs to opens with a footer token, which covers this and the stranded case in one rule. A `BREAKING CHANGE:` whose value continues onto following lines is untouched — that is §10, and it is the shape most breaking changes are written in.

### 16. `.githooks/commit-msg` line 858 — **unresolved**, outdated

**Copilot** · 2026-09-07 22:58:47 UTC

```diff
@@ …
+# A footer-looking line glued to the body is read as body text by parsers.
+check_footers_in_body() {
+  local footer_start="$1" idx line token scan_end="$1"
+
+  # When the last paragraph does not open with a footer token it is body text,
+  # so trailers glued to the end of it are misplaced too — the commonest shape
+  # of this mistake, and the one a boundary-only scan misses.
+  looks_like_footer "${LINES[footer_start]}" || scan_end=${#LINES[@]}
```

> When the final paragraph starts with a trailer and then continues with ordinary prose (`Refs: #1` followed by `more details`), this condition leaves `scan_end` at `footer_start`, so the loop inspects neither line and accepts a footer block that Git's trailer parser discards. Validate the remainder of a footer-starting paragraph and reject non-footer, non-continuation lines.

**angel-penchev** · 2026-09-07 23:18:31 UTC

> Not taking this one, and I want to show the evidence rather than just disagree.
>
> The premise is that git's trailer parser discards the block. It does — but git discards far more than that:
>
> ```
> $ printf 'feat: x\n\nBREAKING CHANGE: removed v1\n' | git interpret-trailers --parse
>                        (nothing)
> $ printf 'feat: x\n\nBREAKING-CHANGE: removed v1\n' | git interpret-trailers --parse
> BREAKING-CHANGE: removed v1
> ```
>
> Git does not accept `BREAKING CHANGE` as a trailer at all, because its token contains a space. That is precisely the token the spec singles out in §9 and requires in §12, so git's parser cannot be the arbiter of what a valid footer block is here — following it would mean rejecting the spec's own canonical example.
>
> On the spec's terms, §10 says a footer's value MAY contain spaces and newlines and that parsing terminates at the next valid token. `Refs: #1` followed by `more details` is therefore one footer whose value spans two lines, which is legal, and the same reading is what lets a multi-line `BREAKING CHANGE:` description work — the commonest shape there is. Rejecting unindented continuation lines would fail both.
>
> Leaving this open rather than resolving it, in case you or a reviewer wants to argue the other side: git *does* fold an indented continuation (`  more details` parses as part of the value), so a rule requiring indentation would be defensible for dashed tokens. It would still fail every `BREAKING CHANGE:` written across two lines, which is why I have not written it.

### 17. `.githooks/commit-msg` line 570 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-07 22:58:48 UTC

```diff
@@ …
+
+  if ! is_known_type "$lowercase"; then
+    local suggestion
+    suggestion="$(suggest_type "$lowercase")"
+    error subject "unknown type \"${SUBJECT_TYPE}\"" \
+      --at 1 1 "${#SUBJECT_TYPE}" \
+      --why "the spec allows any noun (§1, §14); this repo keeps to a list so changelog tooling stays predictable: $(list_types)" \
+      --fix "${suggestion:+did you mean \"${suggestion}\"? — }an unlisted type still commits, but changelog tooling ignores it"
```

> Unknown types are added as errors and `report` exits with status 1, so the fix text claiming that an unlisted type “still commits” is incorrect and contradicts the hook's all-errors policy.

**angel-penchev** · 2026-09-07 23:18:32 UTC

> Fixed in bc50ec2. Correct — that fix text was left over from when an unlisted type was a warning. It now reads "add it to commitMsg.types if this repo should accept it", which is what the reader can actually do about it.

### 18. `.githooks/commit-msg` line 616 — resolved by angel-penchev

**Copilot** · 2026-09-07 23:35:02 UTC

```diff
@@ …
+    error subject 'extra whitespace after the colon' \
+      --at 1 "$separator_col" 3 \
+      --why 'the separator is exactly ": " — one colon, one space, then the description' \
+      --fix "write \"${prefix}: ${SUBJECT_DESC}\""
+
+  else
+    SUBJECT_DESC="${remainder# }"
+  fi
```

> A nonempty but whitespace-only remainder (for example `feat: ` under `commit.cleanup=verbatim`) never enters the empty-remainder branch, and trimming leaves `SUBJECT_DESC` empty, so the required “missing description” finding is omitted. Check the trimmed remainder as well so the report includes every violated rule as promised.

**angel-penchev** · 2026-09-08 09:54:58 UTC

> This one does not reproduce — `feat: ` reports the missing description today. Tested all three shapes under `commit.cleanup=verbatim`, where nothing is trimmed on the way in:
>
> ```
> [feat: ]    -> subject · missing description; subject · trailing whitespace
> [feat:  ]   -> subject · missing description; subject · trailing whitespace
> [feat: <TAB>] -> subject · missing description; subject · trailing whitespace
> ```
>
> The reason is a step above `parse_description`: `check_subject` trims the raw subject before splitting it, so a remainder of nothing but whitespace never survives to reach that function — the subject becomes `feat:`, the remainder is genuinely empty, and the first branch fires. Reading `parse_description` on its own does suggest the gap you describe; it is closed by the caller.
>
> Resolving as no change needed. Happy to reopen if you can produce an input where the finding is actually missing.

### 19. `.githooks/commit-msg` line 734 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 09:05:01 UTC

```diff
@@ …
+    is_blank "${LINES[idx]}" && start=$((idx + 1))
+  done
+
+  # verbatim keeps trailing blank lines, so the last paragraph can be empty.
+  if ((start >= ${#LINES[@]})); then
+    printf '%s' "$start"
+    return 0
+  fi
```

> When `commit.cleanup=verbatim` preserves a trailing blank line, this returns an index past the message. `check_no_ai_attribution` then scans nothing, so an AI trailer such as `Co-authored-by: Copilot <...>` is accepted simply by appending a blank line. Locate the final nonblank paragraph instead; this also keeps valid footer placement independent of trailing blank lines.

**angel-penchev** · 2026-09-08 09:54:55 UTC

> Fixed in the commit above. Reproduced first, and the bypass is as bad as you describe: under `commit.cleanup=verbatim`, appending one blank line to
>
> ```
> feat: x
>
> Co-authored-by: Copilot <bot@github.com>
> ```
>
> was enough for the attribution trailer to pass, because `find_footer_start` returned an index past the message and every check that begins there scanned nothing. The mirror-image failure was real too — a breaking change in a genuine footer was reported as body text.
>
> The block is now located from the last line that has something on it, then walked back to that paragraph's start, exactly as you suggest. Both directions are covered by tests: the trailer with a trailing blank line is rejected, and a valid `BREAKING CHANGE:` with a trailing blank line is still accepted.
>
> This one was mine — the guard it replaces was added two commits ago to stop an unbound-variable crash from the same trailing blank line, and it stopped the crash by returning early instead of by finding the right paragraph.

### 20. `.githooks/commit-msg` line 773 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 09:05:01 UTC

```diff
@@ …
+  printf '%s' "$idx"
+}
+
+# Does this line open a footer — "Token: value", "Token #value", or the one
+# token the spec spells with a space?
+looks_like_footer() {
+  [[ $1 =~ ^[A-Za-z][A-Za-z0-9-]*(:[[:space:]]|[[:space:]]#) ]] ||
+    [[ $1 == 'BREAKING CHANGE'* || $1 == 'BREAKING-CHANGE'* ]]
```

> This prefix glob treats any uppercase text beginning with `BREAKING CHANGE` as a footer, including body prose such as `BREAKING CHANGES are documented below`. That can rewind `footer_start` past this prose and let an earlier, now-stranded `BREAKING CHANGE:` footer pass placement validation. Match only the two exact tokens followed by their delimiter or end of line.

**angel-penchev** · 2026-09-08 09:54:56 UTC

> Fixed in the commit above. Confirmed: `BREAKING CHANGES are documented below` as the final paragraph counted as a footer opener, the rewind ran past it, and the genuine `BREAKING CHANGE: remove v1` above it passed placement validation. Exit 0 on a message that strands a breaking change in the body.
>
> `looks_like_footer` now requires the token and its delimiter — `^BREAKING[[:space:]-]CHANGE([[:space:]]*:|$)` — so both spellings and the bare token still match, while a sentence that merely starts with those letters does not. The stranded footer in that message is now reported.

### 21. `.githooks/commit-msg` line 229 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 10:05:33 UTC

```diff
@@ …
+  done <"$msg_file"
+
+  # Everything below the scissors line is the verbose diff, whatever marker
+  # git wrote it with.
+  for line in ${raw[@]+"${raw[@]}"}; do
+    [[ $line =~ ^[^[:alnum:][:space:]][[:space:]]*-{2,}[[:space:]]*\>8[[:space:]]*-{2,} ]] && break
+    body+=("$line")
+  done
```

> This truncates scissors-looking content even in `commit.cleanup=verbatim`, although Git preserves that content in the commit. A verbatim message containing a valid subject, the scissors marker, and invalid following text therefore passes this hook while Git stores the unchecked text. Preserve the full buffer in verbatim mode and only apply this truncation in modes where Git removes the scissors section.

**angel-penchev** · 2026-09-08 10:12:49 UTC

> Fixed in b31a66b, though the reasoning needed one correction, which changed the shape of the fix.
>
> Git does **not** preserve the scissors section under verbatim when the section is its own. Tested with `git commit --verbose --cleanup=verbatim`: the stored object contains zero scissors markers and zero diff lines. Git removes the diff it appended regardless of cleanup mode, so cutting there is right in every mode.
>
> What is real is the narrower case — a scissors line somebody typed themselves. That is message content everywhere except the scissors mode, and `git commit --cleanup=verbatim -F` stores it verbatim while the hook dropped it:
>
> ```
> feat: valid subject
>
> # ------------------------ >8 ------------------------
> Reviewed by: Z
> ```
>
> The hook now tells the two apart by whether a diff follows the marker (`diff --git`, `index`, `---`, `+++`, `@@`), and cuts unconditionally only in scissors mode, where git truncates whatever follows. The `Reviewed by: Z` above is now reported, in verbatim and in the default mode, while a real `--verbose` diff is still ignored.

### 22. `.githooks/commit-msg` line 915 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 10:05:33 UTC

```diff
@@ …
+# block, where trailers live: body prose that merely mentions a tool by name is
+# not an attribution.
+check_no_ai_attribution() {
+  local footer_start="$1"
+  local agents='(claude|anthropic|copilot|chatgpt|gpt-|cursor|codex|bot@)'
+  local idx line lowercase
+
+  for ((idx = footer_start; idx < ${#LINES[@]}; idx++)); do
```

> Starting at `footer_start` lets an explicit AI attribution evade the rule when later body prose follows it. For example, `Co-authored-by: Copilot <...>` followed by a blank line and `More details.` is outside the computed final footer block and is never scanned. Scan all post-subject lines; the existing trailer-shape checks already avoid rejecting ordinary body prose that merely mentions an AI tool.

**angel-penchev** · 2026-09-08 10:12:51 UTC

> Fixed in b31a66b. Confirmed: `Co-authored-by: Copilot <…>`, a blank line, then `More details.` was accepted, because the attribution scan started at the closing block and body text after the trailer moved the block past it.
>
> The scan now covers every line after the subject, as you suggest. The shape test added earlier is what keeps prose out, and it still does — `remove text generated with Copilot from the footer` passes, since it is not trailer-shaped, while `Generated with: Copilot` and `Generated-with: Copilot` are both caught wherever they sit.

### 23. `.githooks/commit-msg` line 227 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 10:19:03 UTC

```diff
@@ …
+  while IFS= read -r line || [[ -n $line ]]; do
+    raw+=("${line%$'\r'}")
+  done <"$msg_file"
+
+  # A scissors line is git's own when it introduces the diff --verbose appends,
+  # and git removes that itself in every cleanup mode. One somebody typed is
+  # message content that only the scissors mode removes, so verbatim keeps it
+  # and so must the hook. Tell them apart by whether a diff follows.
```

> `COMMIT_MSG_REPORT_ONLY` is used for already-written commits in CI, but this path still applies the checkout's cleanup config (normally `stripspace --strip-comments`). As a result, a stored message such as `feat: add hook` followed immediately by `# body` is reduced to its subject and passes CI, even though the stored message has no required blank separator. In report-only mode, preserve the supplied file exactly rather than reapplying editor cleanup.

**angel-penchev** · 2026-09-08 10:24:28 UTC

> Confirmed and fixed in f9773b4. `feat: add hook` + `# body` passed report-only because the checkout's cleanup ran a second time over a message git had already cleaned. `read_message` now treats a report-only message as verbatim — no `stripspace`, no comment stripping — and skips the scissors scan entirely, since git removed its own verbose diff before the commit was written. Regression cases added; all 14 commits on this branch still pass the CI simulation.

### 24. `.githooks/commit-msg` line 240 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 10:19:03 UTC

```diff
@@ …
+    fi
+  done
+  if ((marker >= 0)); then
+    if [[ $CLEANUP_MODE == scissors ]]; then
+      cut=$marker
+    else
+      for ((idx = marker + 1; idx < ${#raw[@]}; idx++)); do
+        if [[ ${raw[idx]} =~ ^(diff\ --git\ |index\ |---\ |\+\+\+\ |@@\ ) ]]; then
```

> This treats any later `index `, `--- `, `+++ `, or `@@ ` line as proof that the scissors marker introduced a verbose diff. An authored message containing the marker and prose such as `--- old behavior` is therefore truncated before validation; a following malformed `Reviewed by: Alice` footer exits successfully. Require an actual diff-opening header before discarding the remainder.

**angel-penchev** · 2026-09-08 10:24:30 UTC

> Confirmed and fixed in f9773b4. The test is now `diff --git ` alone, which is the only header git actually emits to open the diff it appends. `--- old behaviour` under a hand-typed scissors line is prose again, and the malformed `Reviewed by: Alice` beneath it is now reported.

### 25. `.githooks/commit-msg` line 727 — resolved by angel-penchev

**Copilot** · 2026-09-08 10:19:04 UTC

```diff
@@ …
+
+check_imperative_mood() {
+  local desc="$1" col="$2"
+  local first_word="${desc%%[ ,:;]*}"
+  local rest="${desc#"$first_word"}"
+  local lowercase="${first_word,,}"
+
+  if [[ -n ${IMPERATIVE_FORM[$lowercase]-} ]]; then
```

> A description beginning with one of the delimiters used above makes `first_word`/`lowercase` empty. Expanding an associative array with an empty subscript raises `bad array subscript`, so malformed inputs such as `feat:: add hook` terminate the hook before it can print the findings already collected. Return early for an empty first word before indexing the map.

**angel-penchev** · 2026-09-08 10:24:31 UTC

> Real defect, with one correction: it does not terminate the hook. The script runs under `set -uo pipefail`, so `feat:: add hook` printed `commit-msg: line 653: IMPERATIVE_FORM: bad array subscript` to stderr and then carried on to report the findings and exit 1. The diagnostic still had no business being there — `check_imperative_mood` now returns early on an empty first word (f9773b4), and the suite fails any case whose output contains a shell diagnostic.

### 26. `.githooks/commit-msg` line 958 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 10:19:04 UTC

```diff
@@ …
+    # attribution, however malformed. Prose that names a tool is just prose.
+    looks_like_footer "$line" ||
+      [[ $line == 🤖* ]] ||
+      [[ $line =~ ^[A-Za-z][A-Za-z0-9]*([[:space:]]+[A-Za-z0-9]+)*:[[:space:]] ]] ||
+      continue
+
+    if [[ $lowercase =~ ^co-authored-by:.*$agents ]] ||
+       [[ $lowercase =~ (generated[[:space:]-]with|created[[:space:]-]by).*$agents ]] ||
```

> The attribution check only recognizes “generated with” and “created by”. A trailer such as `Generated-by: Copilot` is footer-shaped but matches neither phrase, so it is accepted despite the stated no-AI-attribution rule. Include the other generated/created phrase forms in this condition.

**angel-penchev** · 2026-09-08 10:24:33 UTC

> Confirmed and fixed in f9773b4. The alternation is now `(generated|created|authored|written)[[:space:]-](with|by)`, so `Generated-by:`, `Created-with:`, `Authored by:` and `Written by:` are all caught. The footer/robot/spaced-token gate above it still keeps ordinary prose that happens to name a tool out of this check.

### 27. `.githooks/commit-msg` line 838 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 10:58:08 UTC

```diff
@@ …
+
+# Does this line open a footer — "Token: value", "Token #value", or the one
+# token the spec spells with a space?
+looks_like_footer() {
+  # The token and its delimiter, not a line that merely starts with the same
+  # letters: "BREAKING CHANGES are documented below" is a sentence.
+  [[ $1 =~ ^[A-Za-z][A-Za-z0-9-]*(:[[:space:]]|[[:space:]]#) ]] ||
+    [[ $1 =~ ^BREAKING[[:space:]-]CHANGE([[:space:]]*:|$) ]]
```

> `[[:space:]]` is broader than the Conventional Commits footer separators, which require a literal `: ` or ` #`. For example, `Refs:\t#42` is classified as a well-formed footer and passes every later check. Detect and reject these malformed separators rather than accepting tabs as valid.

**angel-penchev** · 2026-09-08 11:05:59 UTC

> Confirmed and fixed in a478366. `looks_like_footer` now takes the separator literally — `: ` or ` #`, per §9 — so `Refs:<tab>#42` is no longer a footer to the hook, matching what git's trailer parser does with it.
>
> Demoting it to prose on its own would have been a silent fix, so there is a new `check_footer_separators` that says what is wrong: for a line nobody could mistake for prose (the breaking-change token, a dashed token, or one in `KNOWN_FOOTER_TOKENS`) it reports `footer "Refs" is not followed by ": "`. It also catches the no-whitespace form, `BREAKING CHANGE:remove v1`, which the old `[[:space:]]` test let through as well.
>
> One report per line: `has_malformed_separator` is shared, and the placement checks skip a line it already covers, so you get the separator finding instead of that plus a spurious "shares a paragraph with body text".

### 28. `.githooks/commit-msg` line 883 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 10:58:08 UTC

```diff
@@ …
+
+    elif [[ ! $line =~ ^BREAKING[[:space:]-]CHANGE ]]; then
+      error footer "\"${token}\" is not the BREAKING CHANGE token" \
+        --at "$line_no" 1 "${#token}" \
+        --why 'the token is exactly "BREAKING CHANGE" or "BREAKING-CHANGE" — one space or one hyphen, and no parser matches anything else' \
+        --fix 'write "BREAKING CHANGE: <description>"'
+
+    elif [[ ! $line =~ ^BREAKING[[:space:]-]CHANGE:[[:space:]].+ ]]; then
```

> This accepts any whitespace after the colon, so `BREAKING CHANGE:\tdescription` passes even though both the diagnostic below and the spec require a colon followed by a literal space. Require the two exact token prefixes and a nonempty description.

**angel-penchev** · 2026-09-08 11:06:01 UTC

> Confirmed and fixed in a478366, though the shape of the fix moved. Requiring a literal space in this branch would have produced "BREAKING CHANGE footer has no description" for `BREAKING CHANGE:<tab>remove v1`, which has a description — the separator is the defect. So this branch now asks only whether a description exists (`:[[:space:]]*[^[:space:]]`), and the new `check_footer_separators` reports the separator. `BREAKING CHANGE:` alone still gets "has no description"; `BREAKING CHANGE:<tab>x` and `BREAKING CHANGE:x` each get exactly one finding, naming the separator.

### 29. `.githooks/commit-msg` line 528 — resolved by angel-penchev

**Copilot** · 2026-09-08 11:12:56 UTC

```diff
@@ …
+
+  if [[ $prefix =~ [[:space:]] ]]; then
+    local before_space="${prefix%%[[:space:]]*}"
+    error subject 'whitespace inside the type/scope prefix' \
+      --at 1 $((${#before_space} + 1)) 1 \
+      --why 'nothing may sit between the type, the scope, the "!" and the colon' \
+      --fix 'write "type(scope)!: description" with no spaces before the colon'
+    prefix="${prefix//[[:space:]]/}"
```

> Removing prefix whitespace before parsing loses its source position, so later findings no longer underline the offending text precisely. For example, `feat (Auth): add x` reports the whitespace correctly, but the uppercase-scope finding computes column 6 from the normalized prefix and underlines `(Aut` rather than `Auth`. Preserve a normalized-to-raw offset when calculating scope columns, or stop emitting secondary prefix findings once whitespace makes those offsets unreliable.

**angel-penchev** · 2026-09-08 11:17:41 UTC

> Confirmed and fixed in b89316d. `feat (Auth): add x` underlined `(Aut`; it now underlines `Auth`.
>
> I took the first of your two options — keeping the finding and fixing the offset — because suppressing it would cost the contributor the reason their scope is wrong. The column and width come from `SUBJECT_PREFIX`, the subject as written: past the opening paren, then past any space left after it. `feat( Auth ): add x` also lands on `Auth` now, and the empty-scope caret still covers `()`.
>
> Worth noting the neighbouring findings in `parse_prefix` and `split_type_and_scope` were already anchored against the raw prefix — `before_bang`, `through_paren`, `before_paren`, `before_close` all read `SUBJECT_PREFIX`. `check_scope` was the one computing from the normalised copy.

### 30. `.githooks/commit-msg` line 1153 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 11:12:57 UTC

```diff
@@ …
+
+    # A trailer, the robot marker these tools sign off with, or a trailer
+    # written with spaces in the token — "Generated with: Copilot" is still an
+    # attribution, however malformed. Prose that names a tool is just prose.
+    looks_like_footer "$line" ||
+      [[ $line == 🤖* ]] ||
+      [[ $line =~ ^[A-Za-z][A-Za-z0-9]*([[:space:]]+[A-Za-z0-9]+)*:[[:space:]] ]] ||
+      continue
```

> Malformed AI trailers without a space after the colon are excluded by this gate. For example, `Generated-by:Copilot` or `Co-authored-by:Copilot` receives only the separator error; after applying that fix, the contributor hits the AI-attribution error on a second attempt, contrary to the single-pass/all-findings behavior. Include recognized malformed attribution prefixes in the gate.

**angel-penchev** · 2026-09-08 11:17:43 UTC

> Confirmed and fixed in b89316d. The gate now also accepts a line that `has_malformed_separator` recognises, which is exactly the `Generated-by:Copilot` / `Co-authored-by:Copilot` shape — a footer token whose colon is followed by something other than a space.
>
> Your reasoning about the cost is the part I want to confirm: the whole point of this hook is one pass with every finding, so a defect that only surfaces after fixing another defect is a real bug even though nothing invalid is accepted. `Generated-by:Copilot` now reports both the separator and the attribution together.

### 31. `.githooks/commit-msg` line 1089 — resolved by Copilot, outdated

**Copilot** · 2026-09-08 11:12:57 UTC

```diff
@@ …
+      [[ $line =~ ^[A-Za-z][A-Za-z0-9]*([[:space:]]+[A-Za-z0-9]+)*:[[:space:]] ]] ||
+      continue
+
+    # A co-author is judged on its own terms — the phrase test below would
+    # match every "co-authored-by" line whose person shares a name with a tool.
+    if [[ $lowercase == co-authored-by:* ]]; then
+      is_agent_coauthor "$line" || continue
+    elif [[ ! $lowercase =~ (generated|created|authored|written|assisted)[[:space:]-](with|by).*$agents ]] &&
```

> Repeated separators let explicit AI attribution trailers bypass this rule. For example, `Generated  by: Copilot` is trailer-shaped at line 1082, but this regex requires exactly one space or hyphen, so the hook exits successfully; `Generated--by: Copilot` has the same gap. Accept one or more separators so these malformed variants still enforce the stated no-attribution policy.

**angel-penchev** · 2026-09-08 11:17:44 UTC

> Confirmed and fixed in b89316d: the phrase test takes `[[:space:]-]+` now, so `Generated  by: Copilot` and `Generated--by: Copilot` are both caught, along with `Generated---by:Copilot` and the same shapes for created/authored/written/assisted.
>
> The gate above was never the obstacle for these two — `Generated  by: Copilot` already matched the spaced-token alternative and `Generated--by: Copilot` already matched `looks_like_footer`. Only the phrase itself was too strict.

### 32. `.githooks/commit-msg` line 875 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 11:23:23 UTC

```diff
@@ …
+# meant as a footer is told, rather than quietly demoted to prose.
+# True when $1 is plainly meant as a footer but the colon is followed by
+# something other than a space. Sets MALFORMED_TOKEN and MALFORMED_VALUE.
+# Every other footer check skips such a line, so it is reported once.
+has_malformed_separator() {
+  local line="$1" rest
+
+  [[ $line =~ ^(BREAKING[[:space:]-]CHANGE|[A-Za-z][A-Za-z0-9-]*): ]] || return 1
```

> Malformed hash-style separators are never examined because this helper only matches a colon. For example, `Refs  #42` is neither recognized as a footer nor rejected, so the hook exits successfully even though §9 permits exactly one ` #` separator. Detect known/dashed tokens followed by malformed whitespace before `#` and report them like malformed colon separators.

**angel-penchev** · 2026-09-08 11:28:03 UTC

> Confirmed and fixed in e2a7d41. `has_malformed_separator` now recognises the `" #"` form as well as `": "`, so `Refs  #42` and `Refs<TAB>#42` are reported with the same message and the same one-finding-per-line handling. `Refs #42` still passes.
>
> The finding text and the suggested rewrite name both separators now — `footer "Refs" is not followed by ": " or " #"` — since either is a valid destination, and the fix line reproduces the original value with the separator corrected.

### 33. `.githooks/commit-msg` line 928 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 11:23:23 UTC

```diff
@@ …
+  for ((idx = 1; idx < ${#LINES[@]}; idx++)); do
+    line="${LINES[idx]}"
+    lowercase="${line,,}"
+    # The token proper, followed by its colon or ending the line — so that body
+    # prose such as "Breaking changes are listed below." is left alone.
+    # One or more separators, so that "BREAKING  CHANGE:" is caught here and
+    # reported rather than falling past every footer check as prose.
+    [[ $lowercase =~ ^breaking[[:space:]-]+change[[:space:]]*(:|$) ]] || continue
```

> The `BREAKING CHANGE` scanner ignores the spec's alternate ` #` footer separator. As a result, `breaking change #remove v1` exits successfully, bypassing the required uppercase-token check. This parser and the description validation below should recognize both `: ` and ` #` forms.

**angel-penchev** · 2026-09-08 11:28:05 UTC

> Confirmed and fixed in e2a7d41, and the fix reached three places rather than the two you named.
>
> The candidate regex and the description test both take `(:|[[:space:]]+#)` now, so `breaking change #remove v1` gets the uppercase finding instead of exiting 0, and `BREAKING CHANGE #` gets "has no description".
>
> The third was a regression the first two would have introduced on their own: `check_footer_tokens` skips breaking-change lines by matching its own copy of that pattern, and with the scanner extended but the skip not, the spec-valid `BREAKING CHANGE #remove v1` started being reported as a token containing spaces. Both patterns are extended, and that message is now a passing case in the suite so the two cannot drift apart again.

### 34. `.githooks/commit-msg` line 266 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 11:34:00 UTC

```diff
@@ …
+      for ((idx = marker + 1; idx < ${#raw[@]}; idx++)); do
+        if [[ ${raw[idx]} == 'diff --git '* ]]; then
+          cut=$marker
+          break
+        fi
+      done
+    fi
+  fi
```

> This stops at the first scissors-looking line and treats any later `diff --git` header as proof that this first marker was Git-generated. With `commit.cleanup=verbatim`, an authored marker in the body followed by the real verbose marker/diff causes everything after the authored marker to be skipped; a malformed `Reviewed by: Alice` there is accepted. Keep the first marker only for `scissors` cleanup, but otherwise pair the diff with the nearest preceding marker.

**angel-penchev** · 2026-09-08 11:39:12 UTC

> Confirmed and fixed in 4382c0f, taking your suggestion exactly: the first marker only for `scissors` cleanup, otherwise the diff pairs with the nearest marker above it.
>
> Verified across a matrix rather than one case, since this has now been wrong in three different ways over the review: authored marker then git marker plus diff (the `Reviewed by: Alice` is checked again), git marker plus diff alone (still cut), authored marker with no diff under verbatim and under strip (checked), scissors mode (cuts at the first, whoever wrote it), a diff pasted with no marker above it (nothing cut), two authored markers and no diff (nothing cut), and an alphanumeric `core.commentChar` marker. That matrix is now part of the suite.

### 35. `.githooks/commit-msg` line 880 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 11:34:00 UTC

```diff
@@ …
+
+  if [[ $line =~ ^(BREAKING[[:space:]-]CHANGE|[A-Za-z][A-Za-z0-9-]*): ]]; then
+    MALFORMED_TOKEN="${BASH_REMATCH[1]}"
+    is_footer_token "$MALFORMED_TOKEN" || return 1
+
+    rest="${line#*:}"
+    # A bare token line is check_breaking_change's business, not this one.
+    [[ -z $rest || $rest == ' '* ]] && return 1
```

> `$rest == ' '*` accepts any value beginning with a space, so doubled colon separators are never rejected. For example, `Refs:  #42` exits 0 in report-only mode even though the diagnostic below explicitly says doubled spaces violate §9. Measure the complete leading whitespace run and accept it only when it is exactly one literal space.

**angel-penchev** · 2026-09-08 11:39:14 UTC

> Confirmed and fixed in 4382c0f — both forms want exactly one space now, so `Refs:  #42` is rejected like `Refs  #42`. The inconsistency was mine: I added the `" #"` strictness last round without matching the colon branch to it.
>
> Your comment also sent me to check the diagnostic itself, and it was making a false claim. It said git stops reading a trailer block at anything else, "tabs and doubled spaces included". It does not: `git interpret-trailers --parse` accepts both `Refs:  #42` and `Refs:<TAB>#42` and normalises them to `Refs: #42`. Rejecting them is this repo being stricter than git because §9 spells the separator out — which is a fine thing to do, but not while blaming a parser that does not mind. The `--why` says that now.

### 36. `.githooks/commit-msg` line 225 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 11:45:42 UTC

```diff
@@ …
+# run the message through git's own: that is what decides whether a "#" line is
+# a comment (core.commentChar, including "auto", which a hook cannot resolve by
+# itself) and whether blank lines and trailing whitespace survive.
+# The line git writes above the diff it appends. core.commentChar may be any
+# single ASCII character, letters and digits included, so the marker is judged
+# by its shape rather than by what opens it.
+is_scissors_marker() {
+  [[ $1 =~ ^[^[:space:]][[:space:]]*-{2,}[[:space:]]*\>8[[:space:]]*-{2,} ]]
```

> This marker test is much looser than Git's actual scissors line: an authored line such as `x-- >8 --` matches. With `commit.cleanup=scissors`, `read_message` then drops that line and everything after it even though Git preserves it, so invalid trailing content can be committed without validation. Match the exact Git marker suffix while still allowing any non-whitespace comment character.

**angel-penchev** · 2026-09-08 11:50:40 UTC

> Confirmed and fixed in 3a1b0a1, and going to git for the answer rather than tightening by eye turned up more than the report.
>
> Committing each shape through a real editor under `--cleanup=scissors`:
>
> - `x-- >8 --` — kept
> - `# --- >8 ---` — kept
> - `#------------------------ >8 ------------------------` (no space) — kept
> - `# ------------------------ >8 ------------------------ x` (trailing text) — kept
> - `# ------------------------ >8 ------------------------` — **cut**
> - `; ------------------------ >8 ------------------------` with `core.commentChar=;` — **cut**
> - the same semicolon line with `core.commentChar=#` — kept
>
> So the rule is exact: the comment character, twenty-four dashes, `" >8 "`, twenty-four more, and nothing after but whitespace, which git strips before comparing. `is_scissors_marker` matches that and reads `core.commentChar` to decide the opener, falling back to any non-whitespace character only under `auto`, which a hook cannot resolve. Three new suite cases cover the loose marker, the short rule, and the rule with text after it.
>
> Also worth recording, since it bounds the blast radius: `--cleanup=scissors` truncates **only when git opens an editor**. With `-F` or `-m` git keeps the scissors section whatever the mode, which I had not verified before.

### 37. `.githooks/commit-msg` line 901 — resolved by angel-penchev

**Copilot** · 2026-09-08 11:45:43 UTC

```diff
@@ …
+
+  if [[ $line =~ ^(BREAKING[[:space:]-]CHANGE|[A-Za-z][A-Za-z0-9-]*): ]]; then
+    MALFORMED_TOKEN="${BASH_REMATCH[1]}"
+    is_footer_token "$MALFORMED_TOKEN" || return 1
+
+    rest="${line#*:}"
+    # A bare token line is check_breaking_change's business, not this one.
+    [[ -z $rest ]] && return 1
```

> This early return assumes every bare token is handled by `check_breaking_change`, but that function only handles BREAKING CHANGE. A recognized footer such as `Refs:` therefore produces no finding and passes both the local hook and CI despite lacking the required `: ` or ` #` separator/value. Report bare non-breaking footer tokens here.

**angel-penchev** · 2026-09-08 11:50:41 UTC

> Confirmed and fixed in 3a1b0a1. `Refs:` and `Reviewed-by:` now report `footer "Refs" has no value`, with §9 as the reason — a footer is a token, a separator and a value, and with nothing after the colon there is no trailer to read. `BREAKING CHANGE:` keeps its own finding, which says more about what belongs there.
>
> You are right that the early return was reasoning from a false premise. It read as "a bare token line is somebody else's business", and the only somebody else was `check_breaking_change`.

### 38. `.githooks/commit-msg` line 202 — resolved by angel-penchev, outdated

**Copilot** · 2026-09-08 11:56:12 UTC

```diff
@@ …
+  configured="$(git config --get commitMsg.bodyMax || true)"
+  [[ $configured =~ ^[0-9]+$ ]] && BODY_MAX=$((10#$configured))
+
+  # Which character opens a comment, and so which line is git's scissors line.
+  # "auto" leaves this empty: git resolves it against the message, and a hook
+  # cannot repeat that reliably.
+  configured="$(git config --get core.commentChar || true)"
+  [[ ${#configured} == 1 ]] && COMMENT_CHAR="$configured"
```

> When `core.commentChar` is unset, Git uses `#`, but this leaves `COMMENT_CHAR` empty. `is_scissors_marker` then treats any non-whitespace opener as valid (the fallback intended only for `auto`), so with `commit.cleanup=scissors` a line such as `x ------------------------ >8 ------------------------` makes the hook discard everything below it even though Git keeps it. Preserve `#` for the unset case and reserve the empty sentinel for `auto`.

**angel-penchev** · 2026-09-08 11:58:57 UTC

> Confirmed and fixed in 5f21c75, and this one is mine from last round — I taught the hook to match against `core.commentChar` and then read "unset" as "unknown", when unset is simply `#`. The fallback meant for `auto` was therefore active on every checkout that had never configured anything, which is every checkout.
>
> Now: `auto` leaves it empty and gets the any-opener fallback; a single configured character is used as-is; anything else, including unset, is `#`.
>
> Four cases added to the scissors matrix so the distinction is held: an `x` opener under `#` (kept, and the bad trailer below it reported), under `x` (cut), under `auto` (cut), and a `#` opener under `commentChar=x` (kept).

---

## Review summaries

### copilot-pull-request-reviewer[bot] · 2026-09-07 19:51:37 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> The new hook currently depends on non-portable tooling/features (Bash 4+ and `tac`) and contains a confirmed caret-positioning bug for empty scopes.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Pull request overview</summary>
>
> This PR adds a local `commit-msg` git hook under `.githooks/` to validate commit messages against Conventional Commits v1.0.0, producing multi-finding, caret-anchored diagnostics and blocking commits on errors.
>
> **Changes:**
> - Introduces a Bash-based Conventional Commits validator hook (`.githooks/commit-msg`) with configurable allowed types and length limits via `git config`.
> - Implements subject/body/footer parsing with detailed error/warning reporting, including footer and BREAKING CHANGE rules.
> - Adds handling for common git-generated messages (merge, fixup/squash/amend markers) and cleans commit message input before validating.
> </details>
>
> <details>
> <summary>File summaries</summary>
>
> | File | Description |
> | ---- | ----------- |
> | `.githooks/commit-msg` | Adds a comprehensive Conventional Commits `commit-msg` validator hook with detailed diagnostics and configurable rules. |
> </details>
>
> <details>
> <summary>Review details</summary>
>
> - **Files reviewed:** 1/1 changed files
> - **Comments generated:** 3
> - **Review effort level:** Lite
> </details>
>
> ---
>
> 💡 <a href="/qoax-community/qoax-community-website/new/main?filename=.github/skills/code-review/SKILL.md" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Add a `code-review` agent skill</a> or configure MCP servers for context-aware, tailored reviews. <a href="https://docs.github.com/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review?tool=webui#mcp-servers-and-agent-skills" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Learn more in the docs.</a>

### copilot-pull-request-reviewer[bot] · 2026-09-07 20:11:46 UTC · COMMENTED

> ### 🔵 Needs a closer look
>
> Numeric length overrides with leading zeros must be normalized to base 10 to prevent arithmetic errors or unintended limits.
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (11)
>
> **Previously missed (1)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:173**
> * Numeric overrides with a leading zero are interpreted as octal in Bash arithmetic. For example, `commitMsg.subjectMax=08` passes validation but later produces a “value too great for base” error, while `010` silently enforces 8 rather than 10. Normalize both validated values as base-10 when loading them.
>
> This issue also appears in the following locations of the same file:
> - line 197
> - line 213
> - line 360
> - line 401
> - line 538
> - ...and 5 more
>
> **.githooks/commit-msg:198**
> * The comment marker is configurable through Git's `core.commentChar`, but this cleanup hard-codes `#`. With a different marker, Git-generated template comments remain in `LINES` and can make otherwise valid commits fail, while literal `#` lines that Git would retain are discarded. Read and honor the active Git cleanup/comment configuration rather than assuming the default marker.
> ```
>     [[ $line =~ ^#[[:space:]]*-{2,}[[:space:]]*\>8[[:space:]]*-{2,} ]] && break
>     [[ $line == '#'* ]] && continue
> ```
> **.githooks/commit-msg:361**
> * This advances the description column by at most one space. For `feat:  Added`, `parse_description` trims both spaces and checks `Added`, but the capitalization and imperative findings underline column 7 instead of the actual column 8. Count the full leading-whitespace run when computing the column.
> ```
>   SUBJECT_DESC_COL=$((${#SUBJECT_PREFIX} + 2))
>   [[ $SUBJECT_REMAINDER == " "* ]] && SUBJECT_DESC_COL=$((SUBJECT_DESC_COL + 1))
> ```
> **.githooks/commit-msg:628**
> * This prefix match also treats ordinary body prose such as `Breaking changes are documented below.` as a malformed footer and aborts the commit. Require the exact `BREAKING CHANGE`/`BREAKING-CHANGE` token followed by `:` or end-of-line so plural prose is not classified as a trailer.
> ```
>     [[ $lowercase == 'breaking change'* || $lowercase == 'breaking-change'* ]] || continue
> ```
> **.githooks/commit-msg:650**
> * A `BREAKING CHANGE` trailer need only belong to a footer block that is separated from the body; it does not need a blank line immediately before every trailer. A valid block such as `Refs: #42` followed by `BREAKING CHANGE: ...` is rejected here because the preceding trailer is nonblank. Pass `footer_start` into this function and report only when the breaking-change line appears before that boundary.
> ```
>     if ((idx > 1)) && ! is_blank "${LINES[idx - 1]}"; then
>       error footer 'BREAKING CHANGE footer is not preceded by a blank line' \
>         --at "$line_no" 1 "${#token}" \
>         --why 'footers MUST start one blank line after the body' \
>         --fix 'insert an empty line before the footer block'
> ```
> **.githooks/commit-msg:703**
> * This scans every body line rather than attribution trailers. Consequently, legitimate body text such as `remove text generated with Copilot`—or any line containing 🤖—aborts the commit as an attribution, even when it is ordinary explanatory content. Restrict the scan to the computed footer block and attribution-shaped trailer lines.
> ```
>     if [[ $lowercase =~ ^co-authored-by:.*$agents ]] ||
>        [[ $lowercase =~ (generated[[:space:]]with|created[[:space:]]by).*$agents ]] ||
>        [[ $line == *🤖* ]]; then
> ```
> **.githooks/commit-msg:401**
> * Using `##` removes everything through the last closing parenthesis, so malformed prefixes such as `feat(api)(ui): add page` and `feat(api)): add page` leave `trailing` empty and are accepted. Remove only through the first `)` so any extra prefix content is reported.
> ```
>     local trailing="${prefix##*)}"
> ```
> **.githooks/commit-msg:680**
> * The final body paragraph is never inspected because `footer_start` is its first line and this loop stops before that index. Consequently the common glued-footer case (`body text` immediately followed by `Closes #1` at the end of the message) produces no promised warning; distinguish whether the final paragraph begins with a footer token, then scan later lines when it does not.
> ```
>   for ((idx = 2; idx < footer_start; idx++)); do
>     line="${LINES[idx]}"
>     is_blank "${LINES[idx - 1]}" && continue
>     [[ $line =~ ^([A-Za-z][A-Za-z0-9-]*)(:[[:space:]]|[[:space:]]#) ]] || continue
> ```
> **.githooks/commit-msg:217**
> * A subject beginning with `Merge ` bypasses every check even when the repository is not in a merge operation, so an ordinary commit such as `Merge invalid message.` is silently accepted. Verify actual merge state (for example via Git's merge metadata) and reserve the text-only checks for autosquash markers.
> ```
> is_generated_by_git() {
>   case "$1" in
>     Merge\ *|fixup!*|squash!*|amend!*) return 0 ;;
>     *) return 1 ;;
>   esac
> ```
> **.githooks/commit-msg:538**
> * The issue-closing keyword check is case-sensitive, so common references such as `Closes #42` or `Fixes #42` in the subject do not produce the documented warning. Apply the regex to the lowercased description.
> ```
>   if [[ $desc =~ (^|[^a-z])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#[0-9]+ ]]; then
> ```
> **.githooks/commit-msg:595**
> * The `*http*` condition exempts any long prose line containing a URL, not just the “lone URL” described above it, so many wrappable lines over `BODY_MAX` receive no warning. Only skip a line when the whole trimmed line is a URL.
> ```
>     # Unbreakable lines (a lone URL, a table row) are left alone.
>     ((${#line} > BODY_MAX)) || continue
>     [[ $line == *' '* && $line != *http* ]] || continue
> ```
>
> - **Files reviewed:** 1/1 changed files
> - **Comments generated:** 0 new
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-07 22:34:43 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> The unresolved critical cleanup-mode flaw and moderate validation/reporting defects must be addressed before approval.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 4
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-07 22:58:48 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> Critical and moderate validation gaps can bypass checks or reject valid commits.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (8)
>
> **Previously missed (2)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:474**
> * This finding omits `--at`, so a misplaced `!` is reported without the promised offending line and exact caret span. Anchor the finding to the `!` in the original, unnormalized subject prefix.
>
> This issue also appears in the following locations of the same file:
> - line 493
> - line 500
> - line 506
> **.githooks/commit-msg:623**
> * The advertised rule rejects issue references in subjects, but this pattern only catches references preceded by a closing keyword. For example, `feat: handle #42` passes. Match `#[0-9]+` directly, or narrow the documented rule to closing directives.
>
> **.githooks/commit-msg:899**
> * The gate makes the whitespace alternatives in the attribution regex unreachable. `Generated with: Copilot` and `Created by: Claude` do not satisfy `looks_like_footer`, are not known footer tokens, and therefore pass despite the no-AI-attribution rule. Let these malformed spaced attribution tokens reach the existing detector.
> ```
>     # A trailer, or the robot marker these tools sign off with. Prose that
>     # happens to name a tool is just prose.
>     looks_like_footer "$line" || [[ $line == 🤖* ]] || continue
> ```
> **.githooks/commit-msg:495**
> * This malformed-scope finding has no `--at` arguments, so cases such as `feat(api)(ui): add thing` produce no offending-line excerpt or caret for their only error, contrary to the reported output contract.
> ```
>       error subject "unexpected \"${trailing}\" after the scope" \
>         --why 'the prefix ends with the scope, an optional "!", then the colon' \
>         --fix 'write "type(scope)!: description"'
> ```
> **.githooks/commit-msg:502**
> * The unclosed-scope finding omits `--at`, so it does not show the offending text or caret promised for every violation. Anchor it to the unmatched opening parenthesis in the original subject.
> ```
>     error subject 'unclosed scope parenthesis' \
>       --why 'a scope MUST be surrounded by parentheses, e.g. fix(parser):' \
>       --fix "write \"${SUBJECT_TYPE}(${prefix#*(}): ...\""
> ```
> **.githooks/commit-msg:508**
> * The unmatched closing-parenthesis finding omits `--at`, so it is printed without the promised offending text and exact caret. Anchor it to the first unmatched `)` in the original subject prefix.
> ```
>     error subject 'scope closing parenthesis without an opening one' \
>       --why 'a scope MUST be surrounded by parentheses, e.g. fix(parser):' \
>       --fix "write \"${SUBJECT_TYPE}(scope): ...\""
> ```
> **.githooks/commit-msg:397**
> * This comment still says trailing whitespace is only a warning, but the check now calls `error` and aborts the commit. Update it to match the all-errors behavior.
> ```
> # Leading whitespace is an error because git keeps it: its message cleanup
> # strips trailing whitespace and blank lines, never indentation, so an indented
> # type reaches the stored commit and defeats every parser reading it. Trailing
> # whitespace is only a warning — see check_trailing_whitespace.
> ```
> **.githooks/commit-msg:688**
> * This comment says trailing whitespace is not worth refusing, but the function records an error and `report` aborts. The stale explanation obscures the deliberate all-errors policy.
> ```
> # Trailing whitespace persists only when a message is committed with
> # --cleanup=verbatim; git's default cleanup strips it from every line, and does
> # so after this hook has run. Worth pointing out, not worth refusing a commit
> # that git was about to tidy up by itself.
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 10
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-07 23:35:03 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> Two moderate validator defects must be fixed before approval.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (1)
>
> **.githooks/commit-msg:733**
> * With `commit.cleanup=verbatim`, a trailing blank line advances `start` past the array and returns before locating the preceding footer paragraph. As a result, `check_no_ai_attribution` scans no lines, so a message ending with `Co-authored-by: Copilot` plus a blank line is accepted; `BREAKING CHANGE` is also incorrectly reported as body text. Locate the final nonblank line first, then derive its paragraph start.
> ```
>   # verbatim keeps trailing blank lines, so the last paragraph can be empty.
>   if ((start >= ${#LINES[@]})); then
>     printf '%s' "$start"
>     return 0
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 1
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 09:05:01 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> The two unresolved moderate validator defects must be addressed before approval.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 2
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 10:05:33 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> Unresolved validation gaps include unchecked verbatim content, autosquash PR titles, and several rule and diagnostic mismatches.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (5)
>
> **Previously missed (4)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:524**
> * The fixed width starts at the required first space and, for `feat:  x`, underlines both spaces plus `x` rather than the extra whitespace alone. Compute the offending run from the normalized description so the promised exact-span caret lands only under whitespace beyond the first separator space.
> **.githooks/commit-msg:558**
> * This fix is ineffective for repository-wide acceptance: `commitMsg.types` is local Git config, while the fresh CI checkout uses `DEFAULT_TYPES`, so following this advice still produces a failing PR. Point contributors to the tracked default for a repository rule and clarify that the config only changes their local hook.
> **.githooks/commit-msg:616**
> * The PR description says issue references are forbidden in subjects, but this condition only rejects closing-keyword forms; `feat: address #42` currently exits successfully. Either narrow the stated rule or reject plain references too; the replacement below implements the documented rule.
> **.github/workflows/commit-conventions.yml:110**
> * The autosquash exemption also applies to the pull request title here. A title such as `fixup! feat: add hook` is accepted, but squash merging then puts that non-Conventional-Commit subject on `main`, defeating the reason the title is checked. Reject autosquash markers for titles, while retaining the exemption for actual commits.
>
> **README.md:21**
> * The installer deliberately leaves an existing `core.hooksPath` unchanged, so `npm install` does not always point Git at `.githooks` and local messages are not always checked as this states. Document that exception so contributors understand the warning emitted by the installer.
> ```
> `npm install` also points git at `.githooks`, so every commit message is checked against [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) before the commit is created. The same check runs in CI on every pull request, over both the commits and the pull request title.
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 2
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 10:19:04 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> Unresolved validator defects can incorrectly accept messages, truncate content, or terminate before reporting findings.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (1)
>
> **.github/workflows/commit-conventions.yml:116**
> * This aggregate error is inaccurate for failures caused only by repository house rules: Conventional Commits v1.0.0 explicitly permits types outside the local allowlist and mixed casing, while this hook rejects them. Describe the failure as violating the repository's commit conventions rather than the specification.
> ```
>             printf '\n%s message(s) do not follow Conventional Commits v1.0.0.\n' "$failures" >&2
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 4
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 10:31:18 UTC · COMMENTED

> ### 🔵 Needs a closer look
>
> Malformed breaking-change footer tokens can bypass validation.
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (5)
>
> **Previously missed (1)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:865**
> * The candidate regex requires exactly one separator character, so a malformed footer such as `BREAKING  CHANGE: remove v1` is ignored by every footer check and the hook accepts it. Broaden candidate detection to repeated whitespace/hyphens, then report noncanonical spellings as invalid tokens.
>
> This issue also appears in the following locations of the same file:
> - line 930
> - line 975
>
> **.githooks/commit-msg:977**
> * An explicit AI attribution such as `Assisted-by: Copilot` passes with exit code 0 because only co-author and generated/created/authored/written phrases are matched. This bypasses the stated no-AI-attribution rule; include `assisted` among the recognized attribution verbs.
> ```
>     if [[ $lowercase =~ ^co-authored-by:.*$agents ]] ||
>        [[ $lowercase =~ (generated|created|authored|written)[[:space:]-](with|by).*$agents ]] ||
>        [[ $line == *🤖* ]]; then
> ```
> **.githooks/commit-msg:395**
> * Trimming the subject before parsing loses its leading-column offset. For ` feat: Added hook`, the capital-letter and imperative findings calculate column 7 and point at the separator instead of the description at column 8, contradicting the exact-span reporting guarantee. Preserve the leading offset and apply it to positions computed from the normalized subject.
> ```
>   local subject
>   subject="$(trim "$raw")"
> ```
> **.githooks/commit-msg:930**
> * A known footer that starts its own paragraph is skipped unconditionally here. For example, `feat: add hook\n\nRefs: #1\n\nMore details.` exits 0, even though the footer is stranded before later body text and Conventional Commits requires footers at the end. Removing this skip lets the existing `idx < footer_start` branch report the misplaced footer; valid stacked footer paragraphs are still excluded because `scan_end` is their earliest start.
> ```
>     is_blank "${LINES[idx - 1]}" && continue
> ```
> **.github/workflows/commit-conventions.yml:70**
> * The hook prints the original message verbatim and explicitly supports fenced code blocks, so a rejected message containing a ` ``` ` line closes this fixed Markdown fence early. The job still fails, but its step summary no longer reliably contains the diagnostic as a code block. Indenting each output line avoids collisions with arbitrary message content.
> ```
>               printf '### %s\n\n```\n' "$label"
>               cat "$output"
>               printf '```\n\n'
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 0 new
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 10:58:09 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> The hook has unresolved moderate correctness issues that can accept invalid messages or reject valid ones.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (8)
>
> **Previously missed (6)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:198**
> * Per-invocation `git commit --cleanup=...` overrides this config but is not exposed by `git config`. With the config unset, `git commit --cleanup=verbatim -F <file>` still takes the `default` branch here, so a glued `# body` line can be stripped before validation and then stored verbatim by Git. This allows a message that violates the blank-line rule to pass. Either pass the effective mode through a supported invocation path or explicitly handle/document command-line cleanup overrides instead of treating the configured mode as authoritative.
> **.githooks/commit-msg:239**
> * Git permits an alphanumeric single-byte `core.commentChar`, but this regex only recognizes punctuation. With `core.commentChar=a`, Git's generated `a ----- >8 -----` marker is missed and the appended verbose diff is validated as message content, which can reject a valid commit. Match any non-whitespace marker character.
> **.githooks/commit-msg:667**
> * This detects only local `#42` references. Standard closing forms such as `fixes owner/repo#42` (and URL issue references) still pass in the subject, despite the stated rule forbidding issue-closing keywords there. Extend the matcher to the supported GitHub/GitLab reference forms.
> **.githooks/commit-msg:723**
> * This only treats a literal space as evidence that a long line is wrappable. A body line over `BODY_MAX` whose words are separated by tabs is therefore mistaken for one long token and accepted. Treat all shell whitespace as separators here.
> **.githooks/commit-msg:920**
> * Requiring whitespace after the colon prevents this rule from seeing a known malformed token when the separator is also wrong. `Reviewed by:Alice` is consequently accepted without reporting the spaces in `Reviewed by`. Match the colon itself so this rule can still produce the intended dashed-token fix.
> **.githooks/commit-msg:982**
> * This searches the entire `Co-authored-by` value for bare tool names, so it also rejects legitimate humans whose names contain one—for example, `Co-authored-by: Claude Shannon <claude@example.com>` is reported as AI attribution. Restrict coauthor detection to unambiguous bot identities/addresses; broad tool-name matching is only safe in explicit `Generated/Assisted ...` trailers.
>
> **.githooks/commit-msg:1096**
> * Caret indentation uses Bash character counts as terminal display columns. Tabs and wide Unicode characters before a finding occupy a different visual width, so a message such as `feat: add 😀 thing.` places the period caret one column early, contradicting the exact-span reporting guarantee. Use display-width-aware positioning or explicitly reject/expand characters whose width is not one column.
> ```
>   local indent='' carets=''
>   ((col > 1)) && printf -v indent '%*s' $((col - 1)) ''
>   printf -v carets '%*s' "$width" ''
> ```
> **README.md:21**
> * The workflow enumerates commits with `--no-merges`, and the hook intentionally exempts generated merge messages, so saying CI checks every commit is inaccurate. Document that CI validates every non-merge commit instead.
> ```
> `npm install` also points git at `.githooks`, so every commit message is checked against [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) before the commit is created. The same check runs in CI on every pull request, over both the commits and the pull request title.
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 2
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 11:12:57 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> Moderate hook validation and installer configuration issues remain unresolved.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (3)
>
> **Previously missed (1)** — in code that hasn't changed since the last review.
>
> **scripts/install-git-hooks.mjs:38**
> * An explicitly set empty `core.hooksPath` returns `''` successfully, but this truthiness check treats it like the unset/failure `null` case and overwrites the contributor's setting. Distinguish `null` explicitly so the documented promise to preserve an existing hooks path also covers empty values.
>
> **.githooks/commit-msg:923**
> * A tab between `BREAKING` and `CHANGE` is classified as a casing error because `[[:space:]-]` accepts the tab here. Thus `BREAKING<TAB>CHANGE: remove v1` says the already-uppercase token “must be uppercase” instead of reporting that the token must contain exactly one literal space or hyphen. Restrict the casing branch to the two exact separators and let other whitespace reach the malformed-token branch.
> ```
>     if [[ ${line^^} =~ ^BREAKING[[:space:]-]CHANGE && \
>           $line != 'BREAKING CHANGE'* && $line != 'BREAKING-CHANGE'* ]]; then
> ```
> **.githooks/commit-msg:1236**
> * The common 🚀 character (U+1F680) is East Asian Width `W` but falls outside both emoji ranges here, so `blank_out` emits one space for its two display cells and every later caret is shifted left. Include the Transport and Map Symbols emoji block in the wide ranges.
> ```
>     ((code >= 0x1F300 && code <= 0x1F64F)) ||
>     ((code >= 0x1F900 && code <= 0x1F9FF)) ||
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 3
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 11:23:23 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> The hook still accepts invalid footer forms and punctuated non-imperative descriptions.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (3)
>
> **Previously missed (1)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:699**
> * A description consisting of a mapped non-imperative word followed by punctuation bypasses this check. For example, `feat: added!` leaves `first_word` as `added!`, so the associative-array lookup misses and the invalid message is accepted. Treat terminal punctuation as a word delimiter so the existing confident mapping still applies.
>
> **.githooks/commit-msg:1222**
> * Summing widths per code point does not preserve alignment for emoji grapheme clusters. For example, the four emoji in `👨‍👩‍👧‍👦` each add two spaces while terminals render the joined sequence in two cells, shifting any later caret by six cells; skin-tone modifiers are similarly classified as wide before the zero-width check. Use grapheme-aware display-width handling (including modifiers and joined sequences) or avoid claiming exact alignment for these inputs.
> ```
>     if is_wide "$code"; then
>       out+='  '
>     elif is_zero_width "$code"; then
> ```
> **.githooks/commit-msg:1205**
> * When the offending span itself is a tab, `blank_out` preserves that tab and this substitution only turns literal spaces into carets. The resulting diagnostic for `feat: <TAB>add parser` contains no visible caret, contradicting the hook's exact-span reporting. Prefix tabs in the caret span with a caret while retaining the tab to preserve subsequent tab-stop alignment.
> ```
>   carets="$(blank_out "${text:col - 1:width}")"
>
>   printf '     %s│%s %s%s%s%s\n' \
>     "$DIM" "$OFF" "$indent" "$RED" "${carets// /^}" "$OFF" >&2
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 2
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 11:34:00 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> Three moderate validation and installation defects remain unresolved.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (1)
>
> **Previously missed (1)** — in code that hasn't changed since the last review.
>
> **scripts/install-git-hooks.mjs:20**
> * `trim()` also removes whitespace that is part of a configured hooks path. For example, `core.hooksPath='.githooks '` is read as `.githooks`, so line 32 exits silently even though Git points at a different directory and validation is disabled. Remove only Git's terminating newline so non-matching configured values still reach the warning branch.
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 2
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 11:45:43 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> The unresolved critical and moderate validation gaps can allow invalid commit content to bypass enforcement.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (4)
>
> **Previously missed (2)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:1096**
> * The explicit agent list omits the generic label `AI`, so an unambiguous attribution trailer such as `Generated-by: AI` exits successfully (confirmed in report-only mode), contrary to the stated no-AI-attribution rule. Add a word-bounded `ai` alternative so names containing those letters, such as “maintainer,” remain unaffected.
> **.github/workflows/commit-conventions.yml:85**
> * `~1..` is not a reliable single-tip selector: it cannot resolve for a root tip, and for a merge tip it also includes commits reachable from the second parent. Use Git's single-commit revision suffix so this branch consistently implements the documented “only its tip” behavior (with `--no-merges` still skipping a merge tip).
>
> **.githooks/commit-msg:1112**
> * Malformed spaced-token attribution trailers do not pass this gate when the colon has no following whitespace. For example, `Generated by:Copilot` exits successfully, so a separator typo bypasses the stated no-AI-attribution rule instead of producing all findings in one pass. Admit colon-terminated spaced tokens here; the phrase check below still filters ordinary prose.
> ```
>       [[ $line =~ ^[A-Za-z][A-Za-z0-9]*([[:space:]]+[A-Za-z0-9]+)*:[[:space:]] ]] ||
> ```
> **.githooks/commit-msg:1220**
> * A missing description is anchored one column past the end of `feat:`, so this slice is empty and the diagnostic prints no caret at all. Preserve a visible caret for empty spans so the missing-description report has the promised insertion-point underline.
> ```
>   carets="$(blank_out "${text:col - 1:width}")"
> ```
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 2
> - **Review effort level:** Balanced
> </details>

### copilot-pull-request-reviewer[bot] · 2026-09-08 11:56:13 UTC · COMMENTED

> ### 🟡 Changes recommended
>
> Three moderate validation and CI concurrency issues must be resolved before approval.
>
> *Once you've addressed the issues Copilot identified, you can request another Copilot review.*
>
> <details>
> <summary>Review details</summary>
>
> ### Suppressed comments (2)
>
> **Previously missed (2)** — in code that hasn't changed since the last review.
>
> **.githooks/commit-msg:1033**
> * This token regex only permits alphanumerics within each whitespace-separated word, so mixed dashed/spaced tokens such as `Signed-off by: Alice` never reach the whitespace-token check and are accepted. Since normalizing this example yields the known `signed-off-by` token, it should be reported just like `Reviewed by`; allow hyphens within each token segment.
> **.github/workflows/commit-conventions.yml:14**
> * This shared concurrency group is unsafe for `push` runs. If push B arrives while push A is still running, A is cancelled, but B validates only `A..B`; commits introduced by A are therefore never checked. Keep cancellation for PR runs, whose next run rechecks the complete PR range, but give push runs a SHA-specific group.
>
> - **Files reviewed:** 5/5 changed files
> - **Comments generated:** 1
> - **Review effort level:** Balanced
> </details>

### claude[bot] · 2026-09-08 12:23:48 UTC · COMMENTED

> ⚠️ **Code review skipped** — your organization's overage spend limit has been reached.
>
> Code review is billed via overage credits. To resume reviews, an organization admin can raise the monthly limit at [claude.ai/admin-settings/claude-code](https://claude.ai/admin-settings/claude-code).
>
> Once credits are available, comment `@claude review` on this pull request, or push a new commit, to trigger a review.

---

## Conversation

### angel-penchev · 2026-09-07 22:03:38 UTC

> Second Copilot review addressed in 4dd05d9. Recording it here since eleven of the twelve findings were suppressed into the review body rather than posted as threads, so there is nothing to reply to inline.
>
> All twelve were reproduced against the hook before being fixed, and each fix has a test.
>
> **Rejected messages that are valid** — the ones that would have driven people to `--no-verify`:
> - a `BREAKING CHANGE:` trailer stacked under another footer was read as body text. §10 says a footer's value runs until the next token, so `BREAKING CHANGE: …` + blank line + `Refs: #1` is one footer section; the footer boundary now extends back over earlier paragraphs that open with a footer token
> - body prose beginning "Breaking changes …" was matched as a malformed token; the token must now be followed by `:` or end-of-line
> - body prose naming an AI tool was matched as an attribution trailer; that check is now scoped to the footer block *and* to trailer-shaped lines
> - with `core.commentChar` set to anything but `#`, git's own editor template was read as body text and **every editor commit was blocked**. The hook now honours the setting, `auto` included, replicating git's candidate list
>
> **Accepted messages that are invalid**: `feat(api)(ui):` and `feat(api)):` passed with the scope silently read as `api` (stripping through the last `)` rather than the first); any subject starting with `Merge ` skipped every check, which now requires an actual merge in progress via `MERGE_HEAD`.
>
> **Warnings that never fired**: a trailer glued to the end of the final paragraph — the commonest shape of that mistake; issue keywords written with a capital; any long line merely containing a URL.
>
> **Config**: a length override written as `010` meant 8 and `08` aborted bash arithmetic (both now base 10), and the caret skipped a column when more than one space followed the colon.
>
> Beyond the review, errors are now reserved for the spec's own MUSTs. §14 allows any noun as a type and §15 forbids treating types as case-sensitive, so `security: upgrade deps` and `FEAT: add thing` no longer fail; type and scope casing, subject length, imperative mood, capitalisation, trailing periods and body width are warnings. `security` is in the default type list. The trade-off is that a typo such as `feet:` warns instead of blocking — a `commitMsg.strictTypes` toggle can restore that if we prefer strictness over strict compliance.

### angel-penchev · 2026-09-07 23:04:54 UTC

> Fourth Copilot review addressed in 1006ed5. All eight comments were suppressed into the review body again rather than posted as threads, so recording the outcome here.
>
> **Four findings printed no caret** (misplaced `!`, text trailing a scope, an unclosed parenthesis, an unmatched closing one). Real, and a contract break: every other finding quotes the offending line and underlines the exact span. They fire after the prefix has been normalised, and the normalised copy has no columns worth quoting, so each now measures against the subject as written:
>
> ```
>   ✗ subject · unexpected "(ui)" after the scope
>      │ feat(api)(ui): add page
>      │          ^^^^
> ```
>
> A check in the test suite now asserts that no finding in the file can be raised without an `--at` anchor, so this cannot regress.
>
> **The attribution gate was too tight.** `Generated with: Copilot` passed while `Generated-with: Copilot` was caught — the gate I added last round to stop prose reading as an attribution also shut out trailers whose token carries a space, making the whitespace half of the pattern unreachable. A spaced trailer shape reaches the detector again; prose without a colon still does not.
>
> **The issue-reference rule over-claimed.** It only ever matched a closing keyword, while announcing itself as catching every reference, so `feat: handle #42` passed while the rule said it should not. Narrowed the wording rather than the behaviour — a plain `#42` in a subject is legitimate, and the fix text now says so. Happy to flip it to reject all references instead if that is the preference.
>
> **Two stale comments** still described trailing whitespace as a warning not worth refusing a commit over, which stopped being true when every finding became an error.
>
> For context on that last point: this PR no longer has warnings at all. The same hook runs in CI over commits that are already written, where a warning passes the check and reports nothing, so anything worth saying blocks at commit time instead. Two rules were deleted rather than promoted, because they were not certain enough to block on: a scope ending in `-ed`/`-ing` calling itself a verb (which fails `feat(shared)`), and a first word ending the same way calling itself past tense (which fails `feat: string handling for names`).

### angel-penchev · 2026-09-08 10:13:14 UTC

> Round addressed in b31a66b. Five of this round's seven were suppressed into the review body, so recording those here.
>
> - **`commitMsg.types` advice was useless for the repo.** It told contributors to add a type to local git config, which a fresh CI checkout never reads, so following it still produced a red PR. It now points at `DEFAULT_TYPES` in the tracked hook and says outright that the config only changes your own clone.
> - **The caret for extra whitespace** underlined the separator space and the first word instead of the surplus. `feat:  x` now underlines the second space alone.
> - **An autosquash pull request title** was exempt from every rule. A commit marked `fixup!` is squashed away, but a title becomes the subject on `main`, so CI now sets `COMMIT_MSG_NO_AUTOSQUASH` for the title check while genuine `fixup!` commits stay exempt.
> - **The README overstated the installer.** It leaves an existing `core.hooksPath` alone and warns rather than overwriting someone's own hooks, so that exception is now documented.
> - **The PR description claimed issue references are forbidden** in subjects, while the rule only rejects closing keywords. Corrected the description, since a plain `#42` reference is legitimate.
>
> The two threads have their own replies. One correction worth surfacing: the scissors comment's premise — that git preserves that section under verbatim — is not what git does. `git commit --verbose --cleanup=verbatim` stores zero scissors markers and zero diff lines; git removes the diff it appended whatever the cleanup mode. The real defect was the narrower one, a scissors line written by hand, and that is what the fix addresses.

### angel-penchev · 2026-09-08 10:24:51 UTC

> Round 7 addressed in f9773b4 — 4 threads plus the suppressed comment on the workflow.
>
> | Finding | Verdict | Fix |
> | --- | --- | --- |
> | Report-only reapplies the checkout's cleanup | Confirmed | A stored message is read verbatim: no `stripspace`, no comment stripping, no scissors scan |
> | `--- ` alone accepted as proof of a diff | Confirmed | Only a real `diff --git ` header truncates a hand-typed scissors section |
> | Empty first word indexes the imperative map | Confirmed, consequence corrected | Early return; the hook never terminated, it printed a stray diagnostic and carried on |
> | `Generated-by:` evades the attribution check | Confirmed | `(generated\|created\|authored\|written)[[:space:]-](with\|by)` |
> | CI blames the spec for house-rule failures | Confirmed | CI now names the repository's conventions, spec plus house rules |
>
> Two notes on the report-only change, since it is the one with reach:
>
> - CI feeds messages through `git log --format=%B`, which appends a newline of its own. That trailing blank line is harmless — the trailing-whitespace rule matches `[[:space:]]$`, which an empty line does not.
> - All 14 commits on this branch were re-checked through the CI path under the new semantics: all pass.
>
> Regression suite is at 42 cases, including one per finding above, and it now fails any case whose output contains a shell diagnostic — that is what would have caught the bad-subscript noise. Fuzz re-run over 22 degenerate messages × 5 cleanup modes × report-only on and off: 220 runs, no crashes, no unexpected exit codes.
>
> One thread stays open by choice: the `Refs: #1` + `more details` continuation question. Following git's trailer parser there would mean rejecting every multi-line `BREAKING CHANGE:` description, which §10 explicitly allows, and `git interpret-trailers` cannot arbitrate it because it does not recognise a token with a space in it.

### angel-penchev · 2026-09-08 10:51:43 UTC

> Round 8 addressed in 905584d. No inline threads this time — all five were suppressed comments in the review body, and all five reproduced.
>
> | Finding | Fix |
> | --- | --- |
> | `BREAKING  CHANGE:` slips past every check | Repeated separators are candidates; a non-canonical spelling is reported as the token no parser matches |
> | `Assisted-by: Copilot` accepted | `assisted` added to the attribution verbs |
> | Indented subject shifts every caret | Line-1 findings carry the offset, except those whose columns already come from the raw line |
> | Footer paragraph stranded ahead of body text | The paragraph-opening exemption is gone; stacked footers are already past the scan boundary |
> | A code fence in the message closes the summary fence early | The job summary indents the output instead of fencing it |
>
> On the caret offset, the one that needed the most care: 21 of the 23 line-1 findings measure columns against the trimmed subject, and 2 measure against the raw line. Rather than touch 21 call sites, `add_finding` applies the offset to line-1 findings and the two raw-column ones opt out with `--absolute`. The leading-whitespace finding also underlines the whole indent now instead of one character.
>
> The stranded-footer fix is the one with false-positive risk, so I checked the other direction too: footer-only messages, body-plus-footers, stacked `BREAKING CHANGE:` + `Refs:` paragraphs, a multi-line `BREAKING CHANGE` description, and a body paragraph opening `Note: this is just prose.` all still pass. `Note` is not in `KNOWN_FOOTER_TOKENS`, which is what keeps ordinary prose out of it.
>
> Suite is at 47 cases, 0 failures. All 14 commits on this branch re-checked through the CI path. Fuzz: 21 degenerate messages × 5 cleanup modes × report-only on/off, 210 runs, no crashes or diagnostics.
>
> Also worth flagging: my previous round-watcher missed this review for 20 minutes because `gh api .../pulls/2/reviews` without `--paginate` returns only the first page, and the reply-reviews on this PR had pushed the newest review off it. Fixed on my side.

### angel-penchev · 2026-09-08 11:06:30 UTC

> Round 9 addressed in a478366 — 2 threads and 8 suppressed comments. Nine reproduced; the tenth was a documentation inaccuracy and is corrected.
>
> | Finding | Fix |
> | --- | --- |
> | `Refs:<tab>#42` accepted as a footer | Separator is literal `": "` / `" #"`; a new check names the defect instead of silently demoting the line to prose |
> | `BREAKING CHANGE:<tab>desc` accepted | Same check; this branch now only asks whether a description exists |
> | Caret columns are characters, not display cells | Underline is spaced out of the text itself — wide characters count two, tabs stay tabs |
> | `Co-authored-by: Claude Shannon <claude@example.com>` rejected | A co-author is a machine by address, `[bot]` marker, or a display name that is only the tool's |
> | Alphanumeric `core.commentChar` hides a scissors line | The marker is matched by shape, not by its opening character |
> | `close owner/repo#42` and issue URLs pass in the subject | Both reference forms added |
> | Tab-separated long body line read as one token | Any whitespace makes a line wrappable |
> | `Reviewed by:Alice` not reported | The spaced-token rule matches the colon alone |
> | Command-line `--cleanup=` invisible to the hook | Documented in the README and the hook header — see below |
> | README claims CI checks every commit | Corrected to every non-merge commit |
>
> Three of these deserve more than a table row.
>
> **The separator fix had to avoid trading one silent failure for another.** Making `looks_like_footer` literal fixes the accept, but on its own it just reclassifies the line as prose — still silent. So the new `check_footer_separators` reports it, restricted to lines nobody could mistake for prose. And because a bad separator is *why* the line stops looking like a footer, the placement checks skip lines it covers; otherwise `Refs:<tab>#42` collected the separator finding plus a bogus "shares a paragraph with body text".
>
> **Your fix for the `BREAKING CHANGE` tab would have produced a misleading diagnostic.** Requiring a literal space there means `BREAKING CHANGE:<tab>remove v1` reports "footer has no description" — but it has one. The description test and the separator test are now separate, so each shape gets one accurate finding.
>
> **The co-author rule is the one I most wanted to get right in both directions**, since a false positive blocks a real contributor. `Claude Shannon <claude@example.com>` and `Cursor Bell <cursor@uni.edu>` pass; `Claude <noreply@anthropic.com>`, `Copilot <175728472+Copilot@users.noreply.github.com>`, `copilot-swe-agent[bot]` and a bare `Co-authored-by: Claude` are all caught. Note that the generic phrase test had to stop applying to co-author lines at all — `co-authored-by` literally contains `authored-by`, so it was matching every such line whose person shared a name with a tool. That was the actual mechanism behind the false positive, not the co-author branch itself.
>
> On the command-line `--cleanup=` override: a hook is handed the message file and the environment, never git's argv, so there is no supported way to read it. I could sniff `/proc/$PPID/cmdline`, but that is Linux-only and guesses that the parent process is the `git commit` that invoked us — a fragile thing to put on a path that decides whether a line is a comment. The honest fix is to say so, so the README and the hook header now do, with the remedy (set `commit.cleanup`). Happy to reconsider if you see a portable way to obtain the effective mode.
>
> Suite is at 59 cases, 0 failures, including one per row above and the negative cases for the co-author rule. Fuzz: 22 messages (now with tabs, emoji, CJK and empty co-author trailers) × 5 cleanup modes × report-only on/off = 220 runs, clean. All 15 branch commits still pass through the CI path. Caret alignment verified by measuring the rendered output against Unicode east-asian-width rather than by eye.

### angel-penchev · 2026-09-08 11:18:18 UTC

> Round 10 addressed in b89316d — 3 threads and 3 suppressed comments, all six reproduced.
>
> | Finding | Fix |
> | --- | --- |
> | Scope caret computed from the normalised prefix | Column and width come from the subject as written |
> | `BREAKING<TAB>CHANGE` called a casing error | Only the two parseable spellings are a casing question; the rest is the token nobody parses |
> | `Generated-by:Copilot` never reaches the attribution check | Gate accepts a footer whose separator is already reported |
> | `Generated  by:` / `Generated--by:` bypass the phrase test | `[[:space:]-]+` |
> | 🚀 counted as one cell | Transport block and the wide BMP symbols added |
> | Empty `core.hooksPath` overwritten | Only a failed lookup counts as unset |
>
> The third one is the most interesting of the batch, and your framing of the cost is right: nothing invalid is accepted, but a contributor fixes the separator and *then* meets the attribution error on the next attempt. For a hook whose whole purpose is one pass with every finding, that is a real defect. `has_malformed_separator` turned out to be exactly the predicate the gate needed, so the two checks now share it.
>
> On the scope caret I took your first option rather than the second. Suppressing secondary findings once whitespace appears would cost the contributor the reason their scope is wrong, and the offset is recoverable: `SUBJECT_PREFIX` holds the subject as written. `feat( Auth ): add x` lands on `Auth` too, and the empty-scope caret still covers `()`. The neighbouring findings in `parse_prefix` and `split_type_and_scope` were already anchored against the raw prefix — `check_scope` was the one exception.
>
> The 🚀 report generalised, so I rebuilt `is_wide` rather than adding one range: it is now a table of bounds read two at a time, covering the emoji blocks plus the scattered wide BMP symbols (⌚ ⭐ ✅ ❌ ⛔ and the rest), and it returns early for anything below U+1100 — nearly every character in nearly every message, so the longer table costs nothing measurable. Verified by measuring rendered output against Unicode east-asian-width for 🚀 😀 ⭐ 中文 🫠 and a combining é: every caret lands on the intended character.
>
> Installer: verified all three paths against real repos — empty value preserved with a warning that says "an empty value" rather than `""`, unset installs, outside a work tree exits quietly.
>
> Suite is at 67 cases, 0 failures. Fuzz: 22 messages × 5 cleanup modes × report-only on/off = 220 runs, clean. All 16 branch commits pass through the CI path. Hook runs in ~65 ms.

### angel-penchev · 2026-09-08 11:28:25 UTC

> Round 11 addressed in e2a7d41 — 2 threads and 3 suppressed comments, all five reproduced.
>
> | Finding | Fix |
> | --- | --- |
> | `Refs  #42` neither a footer nor an error | `has_malformed_separator` reads the `" #"` form too |
> | `breaking change #remove v1` skips the uppercase check | Candidate regex and description test take both separators |
> | `feat: added!` bypasses the imperative map | Terminal punctuation ends the first word |
> | A caret span of only a tab prints no caret | Each tab in the span carries one, and keeps the tab |
> | Emoji clusters counted per code point | Joiners, tone modifiers, flags and variation selectors handled |
>
> **The `" #"` fix caused a regression on its own, which is worth naming.** `check_footer_tokens` skips breaking-change lines by matching its own copy of the candidate pattern. Extending the scanner without extending that skip made the spec-valid `BREAKING CHANGE #remove v1` start reporting as a token containing spaces. Both patterns are extended, and that message is now a *passing* case in the suite so the two cannot drift apart again.
>
> **On the grapheme-cluster comment I did the work rather than take the escape hatch**, since "avoid claiming exact alignment" would have meant walking back the guarantee. `blank_out` now treats a zero-width joiner as binding what follows to what came before, gives no cell to tone modifiers or variation selectors, counts a pair of regional indicators as one flag, and promotes any character followed by U+FE0F to the two cells its emoji presentation takes — which also fixes `⚠️` and `1️⃣`, neither of which you named but both of which were wrong for the same reason.
>
> Verified by measuring rendered output against a grapheme-aware reference: 👨‍👩‍👧‍👦, 👍🏽, 🇬🇧, 1️⃣, ⚠️, 🚀, 中, and a combining é all land the caret on the intended character. One honest caveat: terminals genuinely disagree about ZWJ sequences — the same family emoji is two cells in a terminal that ligates it and eight in one that does not — so this follows the ligating behaviour of modern terminals rather than a portable truth.
>
> Suite is at 76 cases, 0 failures. Fuzz: 23 messages × 5 cleanup modes × report-only on/off = 230 runs, clean. All 17 branch commits pass through the CI path. Hook still runs in ~70 ms.

### angel-penchev · 2026-09-08 11:39:33 UTC

> Round 12 addressed in 4382c0f — 2 threads and 1 suppressed comment, all three reproduced.
>
> | Finding | Fix |
> | --- | --- |
> | First scissors marker paired with any later diff | The diff pairs with the nearest marker above it; `scissors` mode still cuts at the first |
> | `Refs:  #42` accepted while `Refs  #42` is rejected | Both forms want exactly one space |
> | Installer trims the configured hooks path | Only git's terminating newline is removed |
>
> **The separator comment turned up a false claim in my own diagnostic.** The `--why` said git stops reading a trailer block at anything but `": "`, "tabs and doubled spaces included". It does not — `git interpret-trailers --parse` accepts `Refs:  #42` and `Refs:<TAB>#42` and normalises both to `Refs: #42`. Rejecting them is this repo being stricter than git because §9 spells the separator out. That is a defensible house rule, but not while blaming a parser that does not mind, so the message now says which it is. I introduced that wording in round 9; it should have been checked against `interpret-trailers` then.
>
> **The scissors logic has now been wrong in three different ways across this review**, so I stopped fixing the reported case and built a matrix: authored marker then git marker plus diff, git marker plus diff alone, authored marker with no diff under both verbatim and strip, scissors mode, a diff pasted with no marker above it, two authored markers and no diff, and an alphanumeric `core.commentChar` marker. Eight cases, now a tracked part of the suite.
>
> One process note: while verifying this round I found my own test harness had been passing `commit.cleanup` through an unquoted variable in a fish shell, which does not word-split — so some earlier "verified under verbatim" runs were silently running under the default mode. The scissors and fuzz checks are now bash scripts with the environment set inline. The affected claims all re-verify correctly under the fixed harness, but the earlier runs were weaker than I described them.
>
> Suite is at 78 cases plus the 8-case scissors matrix, 0 failures. Fuzz rebuilt the same way: 26 messages × 5 cleanup modes × report-only on/off = 260 runs, clean. All 18 branch commits pass through the CI path. Installer verified against real repos for unset, ours, an empty value, a foreign path, and a path with a trailing space.

### angel-penchev · 2026-09-08 11:51:04 UTC

> Round 13 addressed in 3a1b0a1 — 2 threads and 4 suppressed comments, all six reproduced.
>
> | Finding | Fix |
> | --- | --- |
> | Marker test far looser than git's scissors line | Exact rule, with `core.commentChar` deciding the opener |
> | Bare `Refs:` reported by nobody | Any recognised token with no value is reported |
> | `Generated-by: AI` accepted | The generic label counts, bounded |
> | `Generated by:Copilot` never reaches the check | Gate no longer requires a space after the colon |
> | Missing description prints no caret | An empty span shows the insertion point |
> | `~1..` as a single-tip selector | `^!` |
>
> **On the scissors marker I went to git rather than tightening by eye**, and the experiment settled more than the report asked. Committing each shape through a real editor under `--cleanup=scissors`: `x-- >8 --` kept, `# --- >8 ---` kept, the rule with no space after `#` kept, the rule with trailing text kept, the exact rule cut, a semicolon rule cut under `core.commentChar=;`, and that same semicolon rule kept under `core.commentChar=#`. So the opener is not "any character" — it is the configured one. The hook now reads `core.commentChar` and only falls back to any non-whitespace opener under `auto`, which a hook genuinely cannot resolve.
>
> That experiment also bounded the blast radius in a way I had not verified before: **`--cleanup=scissors` truncates only when git opens an editor.** With `-F` or `-m`, git keeps the scissors section whatever the mode.
>
> The `^!` change is verified in both directions: `~1..` fatals on a root commit where `^!` returns the one commit, and on a merge tip `~1..` yielded the second parent's commit while `^!` yields the tip alone (then zero after `--no-merges`, which is the documented behaviour).
>
> Two of the six were false positives waiting to happen, so this round also adds a **negatives file** to the suite — eight messages that must keep passing, including a co-author called Ai Tanaka, a `Reviewed-by: The Maintainer`, and prose containing "aircraft" and "plait". The generic-AI rule and the loosened gate both pass it.
>
> Suite is now 82 cases plus 8 negatives plus an 11-case scissors matrix, 0 failures. Fuzz 260 runs, clean. All 19 branch commits pass through the CI path.

### angel-penchev · 2026-09-08 11:59:00 UTC

> Round 14 addressed in 5f21c75 — 1 thread and 2 suppressed comments, all three reproduced.
>
> | Finding | Fix |
> | --- | --- |
> | Unset `core.commentChar` read as unknown | Unset is `#`; only `auto` gets the any-opener fallback |
> | `Signed-off by: Alice` accepted | A token segment may contain hyphens as well as spaces |
> | Shared concurrency group cancels push runs | Each push gets a group of its own |
>
> **The first one is a regression I introduced last round**, and worth being plain about: teaching the hook to match the scissors line against `core.commentChar` was right, but I treated "unset" as "cannot know" when it simply means `#`. The fallback intended for `auto` was live on every checkout that had never configured anything — which is every checkout — so the fix for over-cutting was still over-cutting in the default case. The scissors matrix now pins all four combinations rather than the two I checked last time.
>
> On the concurrency group, the asymmetry is the point: a pull request run may cancel its predecessor because the next run re-checks the entire range, but a push run is checked only over the range it pushed, so cancelling it leaves those commits unchecked by anything that follows. PR runs keep cancelling; push runs get a SHA-specific group.
>
> `Signed-off by` normalises to `Signed-off-by`, a token the repo knows, and the finding suggests exactly that.
>
> Suite is 83 cases plus 8 negatives plus a 15-case scissors matrix, 0 failures. Fuzz 260 runs, clean. All 20 branch commits pass through the CI path.
