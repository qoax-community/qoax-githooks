# qoax-githooks

The git hooks shared across the QOAX Community organization, and the checks
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
| `commit-msg` | The hook. Lives at the repository root so `core.hooksPath` can point straight at a checkout of this repository. |
| `action.yml` | The composite action CI uses. At the root too, so `github.action_path` is the checkout and the hook is beside it. |
| `scripts/check-messages.sh` | Runs the hook over a range of commits that already exist — in CI, or before you push. |
| `tests/` | The hook's regression suite. Runs here and only here; see [Why the tests stay behind](#why-the-tests-stay-behind). |
| `templates/` | Copy-paste wiring for a repository that wants the hook. |

## Enabling it in a repository

The hook comes in as a submodule, and a repo-local shim in `.githooks` execs
it. The shim is what lets a repository add hooks of its own later without
giving up the shared one, and what turns "the submodule was never checked out"
into a clear message instead of a commit that silently went unchecked.

```sh
git submodule add ../qoax-githooks.git .githooks/shared
cp .githooks/shared/templates/.githooks/commit-msg .githooks/commit-msg
chmod +x .githooks/commit-msg
git update-index --chmod=+x .githooks/commit-msg   # git skips a hook without it
git config core.hooksPath .githooks
```

Then give contributors something that runs on its own, so nobody has to
remember that last line:

- **npm** — copy `templates/npm/install-git-hooks.mjs` to
  `scripts/install-git-hooks.mjs` and add
  `"prepare": "node scripts/install-git-hooks.mjs"` to `package.json`.
  It runs on every `npm install`, checks the submodule out if it is empty, and
  leaves a `core.hooksPath` somebody else set alone.
- **anything else** — copy `templates/posix/setup-hooks.sh` to
  `scripts/setup-hooks.sh` and call it from a `make setup` target or a
  bootstrap script. Same behaviour, no package manager, POSIX `sh`.

Finally, copy `templates/.github/workflows/commit-conventions.yml` for the CI
check and `templates/.github/dependabot.yml` so the submodule pin gets bumped
without anyone watching it.

`qoax-app-template` carries all of this, so a repository created from the
template starts out wired up.

## Checking messages in CI

The workflow is not here. For the organization's private repositories it lives
in [`qoax-reusables`](https://github.com/qoax-community/qoax-reusables) as a
`workflow_call` workflow, so each repository's check is six lines and the
version of the hook they are all checked against is pinned in one place.

What runs there is the composite action at this repository's root, which calls
`scripts/check-messages.sh`: the same hook, over a pull request's commits and
its title — with squash merging the title becomes the subject on `main`, so it
is held to the same rules.

It is an action rather than an `actions/checkout` of this repository so that a
caller needs one step and no knowledge of the layout, and so that it survives
a visibility change in either repository. An organization-accessible
repository's *actions* are downloaded with a scoped read-only token Actions
issues itself, where a caller's `GITHUB_TOKEN` cannot read a second private
repository at all — so the whole arrangement never needs a PAT. That path
needs `Settings → Actions → Access` on this repository set to "Accessible from
repositories in the organization", which is set.

**A public repository has to call the action directly**, because a public
repository may not call a `workflow_call` workflow that lives in a private one
— and `qoax-reusables` is private. `qoax-community-website` is the
organization's public repository and does exactly this; it is also why this
repository is public, so that both the action and the submodule are reachable
from it. Any repository can use this form if it would rather name its own pin
than take the one `qoax-reusables` decides:

```yaml
steps:
  - uses: actions/checkout@v5
    with:
      fetch-depth: 0          # or there is no range to enumerate
  - uses: qoax-community/qoax-githooks@v1
```

The script is worth having locally too:

```sh
.githooks/shared/scripts/check-messages.sh main..HEAD
```

## Versions

Releases are tagged `vN.N.N`, and `vN` moves to the newest release in that
line. The reusable workflow follows `v1`, so a new rule reaches every
repository's CI as soon as it is released, without a pull request per
repository. The submodule pin does not move on its own — that is Dependabot's
job — so a contributor's local hook can lag behind CI for as long as it takes
to merge the bump.

That asymmetry is deliberate: CI is the gate, and the gate should not be
something a repository can weaken by pinning an old hook.

## Why the tests stay behind

A submodule brings a whole repository at a commit; there is no way to ask for
part of one. So the suite — five shell files, about 24 KB against the hook's
56 KB — does land in every consuming checkout. Nothing there runs it, nothing
imports it, and no consuming workflow references it.

Keeping it out entirely would mean publishing the hook to an orphan branch and
pointing submodules at that instead, which buys a slightly smaller checkout in
exchange for a release step between writing a fix and being able to use it.
Not worth it at this size. If the tradeoff ever changes, the branch is the
mechanism.

## Working on the hook

The hook is at the repository root and there is no `.githooks` shim here, so
point git straight at the checkout — this is the one repository where that
single line is the whole setup:

```sh
git config core.hooksPath .
```

Then the suite:

```sh
tests/run.sh                    # the whole suite against the tracked hook
tests/run.sh path/to/other-copy # against another copy
tests/cases.sh ./commit-msg     # one suite
```

`cases.sh` asserts exit codes and findings, `negatives.sh` pins messages that
must **not** be rejected, `scissors.sh` covers what git keeps below a scissors
line across cleanup modes and comment characters, and `fuzz.sh` throws
degenerate messages at every cleanup mode looking for a crash or a leaked
shell diagnostic.

Two rules about changing the hook:

- **Every finding is an error.** There are no warnings. The same hook runs in
  CI over messages that are already written, where a warning passes the check
  and surfaces nothing. A rule that cannot be stated with confidence gets
  deleted rather than softened.
- **Every finding says where it comes from** — the spec or house style —
  because this hook is deliberately stricter than Conventional Commits requires
  a parser to be, and nobody should have to guess who to argue with.

One exemption is worth knowing about, because it is not a rule so much as a
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

The hook needs bash 4+. On macOS that means `brew install bash`; without it the
hook warns instead of blocking.

## History

The hook was written in
[qoax-community-website#2](https://github.com/qoax-community/qoax-community-website/pull/2)
over 23 commits and 38 review threads. Those commits are the history of this
repository, with `.githooks/commit-msg` renamed to `commit-msg` and
`tests/commit-msg/` to `tests/`. The review that shaped it is kept in
[`docs/reviews/qoax-community-website-2.md`](docs/reviews/qoax-community-website-2.md).
