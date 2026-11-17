#!/usr/bin/env node
//
// Points git at the repo's tracked hooks, so commit conventions apply without
// every contributor having to remember `git config core.hooksPath .githooks`.
// The hook is a tracked copy at .githooks/commit-msg, so every checkout has it.
// For a clone that still holds a checkout of the old qoax-githooks submodule,
// this prints how to delete it.
//
// Copy this file into a repository as scripts/install-git-hooks.mjs and run it
// from package.json's `prepare` script, i.e. on every `npm install`.
// It never fails the install: no git binary, or a checkout that is not a git
// work tree (npm tarball, Docker build), is a reason to skip, not an error.
//
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const HOOKS_PATH = '.githooks';

/**
 * Run git, returning stdout without the newline git terminates it with, or
 * null if the command fails. Only that newline: a configured path may end in
 * a space, and trimming it away would read someone else's setting as ours.
 */
function git(...args) {
  try {
    return execFileSync('git', args, {
      stdio: ['ignore', 'pipe', 'ignore'],
      encoding: 'utf8',
    }).replace(/\r?\n$/, '');
  } catch {
    return null;
  }
}

if (git('rev-parse', '--is-inside-work-tree') !== 'true') {
  process.exit(0);
}

// A clone that used the old submodule keeps its checkout after the pull that
// removes the submodule. Nothing runs it, and .githooks/.gitignore hides it.
// Its removal is optional, so the script only says how.
const top = git('rev-parse', '--show-toplevel');
if (
  top !== null &&
  existsSync(`${top}/.githooks/shared/.git`) &&
  git('-C', top, 'ls-files', '-s', '--', '.githooks/shared') === ''
) {
  console.warn(
    `note: .githooks/shared is a leftover checkout of the old qoax-githooks submodule.\n` +
      `  Nothing uses it now. To delete it, run these lines in ${top}:\n` +
      `    rm -rf .githooks/shared "$(git rev-parse --git-dir)/modules/.githooks"\n` +
      `    rmdir "$(git rev-parse --git-dir)/modules" 2>/dev/null || true\n` +
      `    git config --remove-section submodule..githooks/shared 2>/dev/null || true`,
  );
}

const configured = git('config', '--get', 'core.hooksPath');

if (configured === HOOKS_PATH) {
  process.exit(0);
}

// Someone with their own hooks directory made a deliberate choice. Say what
// that costs them, and do not overwrite it. Only `null` means "not set". An
// empty string is a value somebody wrote, and it turns hooks off.
if (configured !== null) {
  const shown = configured === '' ? 'an empty value' : `"${configured}"`;
  console.warn(
    `! core.hooksPath is set to ${shown}, leaving it alone.\n` +
      `  commit message validation is off. Run \`git config core.hooksPath ${HOOKS_PATH}\` to turn it on.`,
  );
  process.exit(0);
}

if (git('config', 'core.hooksPath', HOOKS_PATH) === null) {
  console.warn(`! could not set core.hooksPath, commit message validation is off`);
  process.exit(0);
}

console.log(`✓ commit message validation enabled (core.hooksPath = ${HOOKS_PATH})`);
