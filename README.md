# qoax-githooks

The git hooks shared across the Qoax Community organization, and the checks
that keep them honest.

Today that is one hook: `commit-msg`, a [Conventional Commits
v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) validator. It collects
*every* violation in a single pass and prints each one with the offending text,
the rule it breaks, and a concrete fix.

```
✗ Conventional Commits check (v1.0.0)

  commit message
      1 │ feat(API): Added a new endpoint.
      2 │ See the docs.

 5 error(s)

  ✗ subject · unusual scope "API"
     │ feat(API): Added a new endpoint.
     │      ^^^
     why  the spec only asks for a noun in parentheses (§4); this repo requires lowercase scopes
     fix  e.g. (auth), (api/routes), (legal.terms)

  ✗ subject · description starts with a capital letter
     │ feat(API): Added a new endpoint.
     │            ^
     why  the spec is case-insensitive here (§15); this repo keeps descriptions lowercase for uniform changelogs
     fix  write "added a new endpoint."

  ✗ subject · description ends with a period
     │ feat(API): Added a new endpoint.
     │                                ^
     why  not a spec rule; the subject is a title, and a full stop reads oddly in a changelog list
     fix  write "Added a new endpoint"

  ✗ subject · "added" is not imperative mood
     │ feat(API): Added a new endpoint.
     │            ^^^^^
     why  not a spec rule; git convention is an instruction: "add", not "added" or "adds"
     fix  write "add a new endpoint."

  ✗ body · no blank line after the subject
     │ See the docs.
     │ ^^^^^^^^^^^^^
     why  the body MUST begin one blank line after the description — parsers split the header there
     fix  insert an empty line between the subject and the body

  format  <type>[optional scope][!]: <description>
           <blank line> <body>   <blank line> <footers>
  types   feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, security
  spec    https://www.conventionalcommits.org/en/v1.0.0/

message rejected. rewrite it to follow the format above
```

## Layout

| Path | What it is |
| --- | --- |
| `commit-msg` | The hook. It is at the repository root, so `core.hooksPath` can point straight at a checkout of this repository. Each repository that uses it tracks a copy at `.githooks/commit-msg`. |
| `action.yml` | The composite action for CI. It compares the copy of a repository with `commit-msg`, then runs the hook over the new commits and the pull request title. It is at the root too, so `github.action_path` is the checkout and the hook is next to it. |
| `scripts/check-copy.sh` | The compare that the action runs. |
| `scripts/check-messages.sh` | Runs the hook over a range of commits that already exist, in CI or before you push. |
| `scripts/hook-releases.txt` | The blob of `commit-msg` in each release. With it, the compare names the release of an older copy. |
| `scripts/sync-hook.sh` | Writes the hook of the pinned release into `.githooks/commit-msg` of a repository. With `--check`, it only compares. |
| `scripts/migrate-from-submodule.sh` | Moves a repository off the old `.githooks/shared` submodule, one time. |
| `scripts/fanout.sh` | Adds a sync commit to the open Dependabot pull requests that bump the pin. You run it on your machine. |
| `scripts/merge-sync-prs.sh` | Merges the bump pull requests whose checks passed. You run it on your machine. |
| `templates/` | Files to copy into a repository: the workflow, the Dependabot entry, the setup scripts, and the lines for `.githooks/.gitignore` and `.gitattributes`. |
| `tests/` | The regression suite of the hook and the tests of the scripts. They run only here, so a repository that tracks the hook does not get them. |

## Enabling it in a repository

A repository tracks a copy of the hook at `.githooks/commit-msg`, with mode
100755. Git runs it when `core.hooksPath` is `.githooks`. CI pins this action
by commit sha and compares the copy with the hook of that pin. Thus each
clone, each worktree and CI run the same hook, and nothing has to check out a
submodule.

First, add the workflow. Fill in the template with a release tag and its
commit sha:

```sh
tag=v1.1.0 # a release tag
qg="$(mktemp -d)"
git clone -q --depth 1 --branch "$tag" https://github.com/qoax-community/qoax-githooks.git "$qg"
sha="$(git -C "$qg" rev-parse HEAD)"
mkdir -p .github/workflows
sed -e "s/@QOAX_GITHOOKS_SHA@/$sha/" -e "s/@QOAX_GITHOOKS_TAG@/$tag/" \
  "$qg/templates/.github/workflows/commit-conventions.yml" >.github/workflows/commit-conventions.yml
```

Then write the copy. `sync-hook.sh` reads the pin from `.github/workflows`,
fetches the hook of that release, and stages it with mode 100755:

```sh
sh "$qg/scripts/sync-hook.sh"
```

Git cannot run the hook with CRLF line ends. Keep it at LF in every checkout
with the line of `templates/gitattributes` in `.gitattributes`:

```
/.githooks/** text eol=lf
```

Copy `templates/.github/dependabot.yml` to `.github/dependabot.yml`.
Dependabot then moves the pin when a release comes out (see
[Versions](#versions)). If your file already has a `github-actions` entry for
`/`, do not add a second one. Dependabot rejects two entries with the same
ecosystem, directory and target branch. Add the `allow` item of the template
to the entry you have. With that item, the entry bumps no other action. Leave
the item out if the entry must keep bumping the others. No `ignore` of the
entry may name `qoax-community/qoax-githooks`.

Last, turn the hook on and commit. The hook checks this commit too:

```sh
git config core.hooksPath .githooks
git add .github/workflows/commit-conventions.yml .github/dependabot.yml .gitattributes
git commit -m 'build: track a copy of the commit-msg hook'
```

Then give contributors a step that sets `core.hooksPath` on its own, so
nobody has to remember the `git config` line:

- **npm**: copy `templates/npm/install-git-hooks.mjs` to
  `scripts/install-git-hooks.mjs`, and add
  `"prepare": "node scripts/install-git-hooks.mjs"` to `package.json`. It runs
  on each `npm install`. It leaves a `core.hooksPath` that somebody else set
  alone.
- **Anything else**: copy `templates/posix/setup-hooks.sh` to
  `scripts/setup-hooks.sh`, and call it from a `make setup` target or a
  bootstrap script. It does the same in POSIX `sh`, with no package manager.

With the POSIX script, also add the line of `templates/posix/gitattributes`
to `.gitattributes`. Git for Windows sets `core.autocrlf=true`, and with no
rule a checkout writes the script with CRLF. Then `sh` cannot run it. A clone
made before the rule keeps the CRLF script, because git does not write it
again. In such a clone, delete `scripts/setup-hooks.sh`, then run
`git checkout -- scripts/setup-hooks.sh`.

A repository made from `qoax-app-template` has all of this from the start.

## Moving a repository off the submodule

Older repositories have the hook as a submodule at `.githooks/shared`. A shim
at `.githooks/commit-msg` runs it. In CI, most of them call the reusable
workflow of `qoax-reusables`. Some call this action directly, at `@v1` or
pinned to v1.0.7. `scripts/migrate-from-submodule.sh` moves such a repository
to the tracked copy.

Run it in a fresh temporary clone, on a new branch. Never run it in a
checkout that you work in:

```sh
work="$(mktemp -d)"
git clone -q --depth 1 https://github.com/qoax-community/qoax-githooks.git "$work/qg"
GIT_LFS_SKIP_SMUDGE=1 git clone -q <repository url> "$work/repo"
cd "$work/repo"
git switch -c build/commit-msg-copy
hooks="$(mktemp -d)"
ln -s "$(git rev-parse --show-toplevel)/.githooks/commit-msg" "$hooks/commit-msg"
git config core.hooksPath "$hooks"
sh "$work/qg/scripts/migrate-from-submodule.sh" --ref v1.1.0
```

`--ref` takes a release tag, v1.1.0 or newer, or the commit sha of one.
`GIT_LFS_SKIP_SMUDGE=1` stops the clone from downloading Git LFS files, which
the move does not need. The folder in `core.hooksPath` holds only a link to
the copy. So the new hook checks each commit of the script, and no other
tracked hook runs. A tracked `pre-commit` can stop the commits, and the Git
LFS hooks stop a push when git-lfs is not installed. The script refuses to
run without this folder.

The script makes up to three commits:

- `build: track a copy of the commit-msg hook` removes the submodule and
  `.gitmodules`, and writes the hook over the shim. It adds
  `.githooks/.gitignore` with the line `/shared/`, and the LF rule if the hook
  has none. It also replaces the setup scripts with the templates, and drops
  the submodule line of `setup.cmd`. It does not add the line of
  `templates/posix/gitattributes`. If the repository has
  `scripts/setup-hooks.sh`, add that line to `.gitattributes` by hand.
- `ci: pin the qoax-githooks commit check` writes the workflow with the sha
  pin.
- `ci: let Dependabot bump the qoax-githooks pin` replaces the Dependabot
  entry for the submodule with one for the pin.

It replaces a file only when it knows the blob. On any other blob it stops
and prints the edit to make by hand. Commit the edit, then run the script
again with the same `--ref`. It goes on from where it stopped.

- Commit an edit before the move with `git commit --no-verify`. These are
  edits of the shim, a setup script, `setup.cmd` or `.githooks/.gitattributes`.
  Until the move, the shim cannot find the hook, so a plain `git commit` fails.
- Commit an edit after the move, of the workflow or `.github/dependabot.yml`,
  with a plain `git commit`. The new hook checks it.

A setup script that the script does not know stays as it is, if it runs no
`git submodule` command. Check by hand that it needs nothing from
`.githooks/shared`. On a repository that has moved, the script changes
nothing. Last, it runs a self-test, prints the diff, and lists the lines that
still name the submodule, the shim or `qoax-reusables`. The list includes the
lines of a setup script that it kept. Fix the docs among them by hand. The
script never pushes.

The script moves only a repository whose one submodule is `.githooks/shared`.
Move a repository with other submodules fully by hand.

After the move, an existing clone needs nothing:

- `git pull`, `switch`, `merge` and `rebase` work, and the hook runs after
  each one. `core.hooksPath` stays `.githooks`, so nobody has to run a setup
  script again.
- A clone that had the submodule checked out keeps it as a folder at
  `.githooks/shared`. On main, and on each branch that merged main, nothing
  runs it. `.githooks/.gitignore` hides it, so `git status` stays empty. The
  setup scripts print the clean-up below when they find it.

The clean-up is optional. It frees the space of the old checkout.

Before the clean-up, merge main into each branch that you still commit on.
A branch from before the move has the shim at `.githooks/commit-msg`, and the
shim runs the hook in `.githooks/shared`. After the clean-up, each commit on
such a branch fails with `commit message validation is not installed`. The
setup scripts print the clean-up with no such warning.

Run the clean-up after the pull, in the main checkout and in each worktree
that checked out the submodule:

```sh
rm -rf .githooks/shared "$(git rev-parse --git-dir)/modules/.githooks"
rmdir "$(git rev-parse --git-dir)/modules" 2>/dev/null || true
git config --remove-section submodule..githooks/shared 2>/dev/null || true
```

If a commit on an old branch fails after the clean-up, run
`git submodule update --init .githooks/shared`, as the error says. This works
with staged changes. Or merge main into the branch. The merge brings the
copy, and the hook lets the merge message of git through. A merge that makes
a merge commit stops when changes are staged. So run `git stash` before the
merge and `git stash pop --index` after it.

**Caution:** with `submodule.recurse=true`, do not delete `.githooks/shared`
before the pull. The pull then fails with `fatal: cannot chdir`. To recover,
run `git submodule deinit -f .githooks/shared`, then pull again.

With `submodule.recurse=true`, a clone made with
`git clone --recurse-submodules` needs one more line in the clean-up:

```sh
git config --unset-all submodule.active '^\.$' 2>/dev/null || true
```

Without it, `git switch` to a branch from before the move fails with
`could not reset submodule index`. The work tree then stays half switched.
`git reset --hard` is part of the recovery, and it discards the changes that
are not committed. Save them first. Then run
`rm -rf .gitmodules .githooks/shared`, `git reset --hard` and the line above,
and switch again.

`git worktree remove` fails on a worktree that checked out the submodule. Run
the clean-up in it first, or use `--force`.

A branch from before the move still has the submodule, and it can merge as it
is. To update it, merge main into it. Do not rebase a branch that you pushed.

## Checking messages in CI

Each repository runs this action in a job of its own, from
`templates/.github/workflows/commit-conventions.yml`:

```yaml
jobs:
  commit-conventions:
    name: Conventional Commits
    runs-on: ubuntu-latest
    steps:
      - name: Check out source
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0 # or there is no range to read
      - name: Validate commit messages, the PR title and the hook copy
        uses: qoax-community/qoax-githooks@<commit sha of vX.Y.Z> # vX.Y.Z
```

The pin is a commit sha, so a tag that moves cannot change the check. The
release is the last token of the comment, because Dependabot updates the
comment only in that form. Rulesets require the check by the job name
`Conventional Commits`, so keep that name.

The action runs two scripts in one step, and fails if either one fails:

1. `scripts/check-copy.sh` compares the copy with the hook of the pin. It
   reads the tree of HEAD, so only committed bytes count. For a pull request,
   HEAD is the merge commit.
2. `scripts/check-messages.sh` runs the hook over the commits of the pull
   request or the push, and over the pull request title. With squash merging,
   the title becomes the subject on `main`, so the same rules apply to it.

The inputs:

| Input | Default | Use |
| --- | --- | --- |
| `copy` | `.githooks/commit-msg` | The path of the copy. An empty string turns the compare off. |
| `stale-copy` | `error` | The level for a copy of an older release: `error` or `warning`. |
| `range` | empty | A range to check, such as `main..HEAD`. Leave it empty in CI, and the range comes from the event. |
| `check-pull-request-title` | `true` | Whether to check the pull request title too. |

The compare goes through these cases in order:

| The tree of HEAD has | Result |
| --- | --- |
| nothing to compare, because `copy` is empty | Pass, with a notice. |
| a submodule under `.githooks` | The old layout passes, with the notice "not migrated yet". That layout is one submodule at `.githooks/shared`, a `.gitmodules` file and the shim at the copy path. Any other submodule there fails. |
| no file at the copy path | Fail, with the sync command. In qoax-githooks itself, pass with a notice, because its own `commit-msg` is the hook. |
| the shim, but no submodule | Fail. |
| a mode other than 100755 | Fail, with the fix. |
| the hook of the pin | Pass. The log names the release. |
| the hook of an older release | Fail, or warn with `stale-copy: warning`. The log names the release from `scripts/hook-releases.txt`. |
| any other content: an edit, or a release newer than the pin | Fail. |

A failure prints the fix, mostly the sync command. `sync-hook.sh` writes only
`.githooks/commit-msg`, so a `copy` at another path gets no sync command. The
error says instead to write the `commit-msg` file of the pin to that path with
mode 100755, or to use the default path.

The rule behind the levels: a state that only a commit can cause always
fails. A copy of an older release is the one state that a release alone can
cause, when Dependabot moves the pin and the copy stays. So only that case
follows `stale-copy`.

A repository with no copy sets `copy: ''`. That is the only opt-out:

```yaml
      - uses: qoax-community/qoax-githooks@<commit sha of vX.Y.Z> # vX.Y.Z
        with:
          copy: ''
```

CI reads blobs, so it cannot see a copy that a checkout wrote with CRLF line
ends. The LF rule in `.gitattributes` and `sync-hook.sh --check` cover that
case.

Most repositories that still use the submodule call the reusable workflow
`commit-conventions.yml` of `qoax-reusables`. Some call this action directly,
at `@v1` or pinned to v1.0.7. The migrate script replaces the workflows that it
knows with the job above. For any other workflow, it stops and asks for a hand
edit.

The same checks work locally. Run them in the repository, with a clone of
qoax-githooks:

```sh
# the messages of your branch, with the copy of the repository
COMMIT_MSG_HOOK=.githooks/commit-msg <qoax-githooks clone>/scripts/check-messages.sh main..HEAD
# the copy against the pin, the work tree too
sh <qoax-githooks clone>/scripts/sync-hook.sh --check
```

## Versions

Releases have tags `vX.Y.Z`. Each repository pins one release by commit sha,
so a new release reaches a repository only through a pull request there. The
pin and the copy move in the same pull request. Thus the hook that runs
locally is the hook that CI checks with.

`v1` stays at v1.0.7, for the callers that have not moved off it. New
releases do not move it.

How a release reaches each repository:

1. Dependabot looks for a new release once a week. It opens a pull request in
   each repository that changes `@<old sha> # vA` to `@<new sha> # vB`. The
   `allow` list in `templates/.github/dependabot.yml` keeps it to this action.
2. If the release kept `commit-msg`, the compare passes. Merge the pull
   requests by hand, or with `scripts/merge-sync-prs.sh`.
3. If the release changed `commit-msg`, the compare fails and prints the sync
   command. Run `scripts/fanout.sh`. It adds one sync commit to each pull
   request. Then merge them.
4. After a sync commit, Dependabot stops rebasing that pull request. If a
   newer release replaces the pull request, Dependabot opens a new one, and
   the sync must run again.

## Releasing

A tag starts a bump pull request in every repository that pins the action.
So push a tag only for a real release.

1. Each release has one line in `scripts/hook-releases.txt`: the tag and the
   blob of `commit-msg`. If the release changes the hook, the pull request of
   that change added the line (see
   [Working on the hook](#working-on-the-hook)). For a release that keeps the
   hook, the release pull request adds the line, with the blob of the release
   before it. This prints the blob:

   ```sh
   git hash-object --no-filters commit-msg
   ```

   `tests/releases.sh` fails when the last line is not the current
   `commit-msg`, or when a tag has no line.

2. After the merge, tag the merge commit and push the tag:

   ```sh
   git tag -a vX.Y.Z -m 'vX.Y.Z: <what changed>' <merge sha>
   git push origin vX.Y.Z
   ```

   Do not move `v1`. Optionally, run `gh release create vX.Y.Z --verify-tag`,
   so that the Dependabot pull requests show release notes.

3. Handle the bump pull requests (see [Versions](#versions)) with the
   helpers. They need git, and `gh` with a login that can push and merge.
   Without `--apply`, each one does a dry run:

   ```sh
   sh scripts/fanout.sh                     # a dry run: commit in clones, push nothing
   sh scripts/fanout.sh --apply             # push, after one OK at the terminal
   sh scripts/fanout.sh --apply --batch 5   # one OK for each 5 branches
   sh scripts/fanout.sh --ref vX.Y.Z        # a branch of its own, when Dependabot opened no pull request
   sh scripts/merge-sync-prs.sh             # a dry run: list the pull requests and their checks
   sh scripts/merge-sync-prs.sh --apply     # merge the green ones, after one OK
   ```

   `sh scripts/fanout.sh --list` prints the repositories that both helpers
   work on. Give `owner/name` arguments to work on some of them only.

`fanout.sh` clones each repository into a temporary folder. On the head
branch of the Dependabot pull request, it commits
`chore: sync the commit-msg hook to vX.Y.Z`. A head branch that is behind its
base gets a merge of the base first. It never rebases and never force-pushes.

With `--ref`, `fanout.sh` works on the branch `chore/qoax-githooks-sync`
instead, from the default branch. One commit there moves the pin and the
copy, with the subject
`chore: bump qoax-githooks to vX.Y.Z and sync the commit-msg hook`. When
only one of them changes, the subject names only that one. With `--apply`, it
pushes the branch, but it opens no pull request. Open it yourself.

`merge-sync-prs.sh` lists the Dependabot pull requests that bump the pin, and
the pull requests from `chore/qoax-githooks-sync`. It merges only the ones
whose checks all passed. It stops a merge when the head moved after the list.

## Working on the hook

The hook is at the repository root and there is no `.githooks` shim here, so
point git straight at the checkout — this is the one repository where that
single line is the whole setup:

```sh
git config core.hooksPath "$(git rev-parse --show-toplevel)"
```

The path has to be absolute. Set to `.`, git looks the hook up as a bare
`commit-msg` on `PATH` instead of in the checkout, and every commit fails with
`cannot run commit-msg: No such file or directory` (git 2.56). The
`.githooks` that consuming repositories use is fine, because the hook's path
still has a directory in it. Run the line again if the checkout moves.

Then the suite:

```sh
tests/run.sh                     # the whole suite against the tracked hook
tests/run.sh path/to/other-copy  # against another copy
bash tests/cases.sh ./commit-msg # one suite
tests/tools.sh                   # the tests of the scripts
```

`cases.sh` asserts exit codes and findings, `negatives.sh` pins messages that
must **not** be rejected, `scissors.sh` covers what git keeps below a scissors
line across cleanup modes and comment characters, and `fuzz.sh` throws
degenerate messages at every cleanup mode looking for a crash or a leaked
shell diagnostic.

`tests/tools.sh` runs the tests of `scripts/`. A POSIX script must work under
dash, the `/bin/sh` of ubuntu-latest, so each of its tests runs under dash and
under bash. The tests need no network. Bare repositories and `file://` URLs
stand in for GitHub, through `QOAX_GITHOOKS_URL` and a fake `gh` that refuses
every write. `tests/releases.sh` also compares `scripts/hook-releases.txt`
with the release tags. Outside Actions, a clone with no tags skips that part,
so run `git fetch --tags` first. In Actions, a clone with no tags fails it, so
the CI job checks out with `fetch-depth: 0`. CI runs `tests/run.sh` and
`tests/tools.sh` on every pull request.

A pull request that changes `commit-msg` must also add the line of the next
release to `scripts/hook-releases.txt`, with the new blob. If that line is
there already, update its blob. `tests/releases.sh` fails until the last line
names the current hook. With that line, the compare in CI can name the
release of a copy.

Two rules about changing the hook:

- **Every finding is an error.** There are no warnings. The same hook runs in
  CI over messages that are already written, where a warning passes the check
  and surfaces nothing. A rule that cannot be stated with confidence gets
  deleted rather than softened.
- **Every finding says where it comes from** — the spec or house style —
  because this hook is deliberately stricter than Conventional Commits requires
  a parser to be, and nobody should have to guess who to argue with.

Two exemptions are worth knowing about. The first is not a rule so much as a
hole the rules would otherwise leave. A **YAML document in the body** — a line
that is exactly `---`, its lines, and a line that is exactly `...` — is not
read for footers:

```
ci: bump actions/checkout from 5 to 7

---
updated-dependencies:
- dependency-name: actions/checkout
  dependency-version: '7'
...

Signed-off-by: dependabot[bot] <support@github.com>
```

That block is what Dependabot writes into every commit it makes.
`updated-dependencies:` is a mapping key whose value is on the lines below it,
not a trailer with nothing after the colon — and without the exemption every
bot commit in every repository using this hook fails the check, which is how
it was found. The document must be opened *and* closed, and must not straddle
a blank line, so a lone `---` stays what somebody typed: a rule of dashes.

The other is **Dependabot's own messages**, which are held to every rule except
three. `commit-message.prefix` (and `include: scope`) in `dependabot.yml` give
it a type and a scope; nothing there gives it a width or a case. It never wraps
the `Bumps [x](url) from a to b.` line or the links under it, a grouped update's
subject is past 72 characters on its own (`chore(deps-dev): bump the dev-tooling
group across 1 directory with 9 updates`), and whether it writes `bump` or
`Bump` depends on the repository's recent history, whatever the prefix. So for
a message Dependabot wrote, subject length, a capital first letter and body
width are waived. So is the `Co-authored-by: dependabot[bot] <…>` trailer
GitHub appends when somebody else squash-merges its pull request: it names the
bot whose message this is, not an agent that helped write it. A missing or
unknown type is still an error, because the config can fix that, which is why
`templates/.github/dependabot.yml` sets a prefix.

A message counts as Dependabot's when its footer block has the sign-off
Dependabot ends every commit with,
`Signed-off-by: dependabot[bot] <support@github.com>`. A pull request title has
no footer, so the action passes the pull request's author along and a title
Dependabot wrote gets the same three waivers.

The hook needs bash 4+. On macOS that means `brew install bash`; without it the
hook warns instead of blocking.

## History

The hook was written in
[qoax-community-website#2](https://github.com/qoax-community/qoax-community-website/pull/2)
over 23 commits and 38 review threads. Those commits are the history of this
repository, with `.githooks/commit-msg` renamed to `commit-msg` and
`tests/commit-msg/` to `tests/`. The review that shaped it is kept in
[`docs/reviews/qoax-community-website-2.md`](docs/reviews/qoax-community-website-2.md).
