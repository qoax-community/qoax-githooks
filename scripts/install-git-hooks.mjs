#!/usr/bin/env node
//
// Points git at the repo's tracked hooks, so commit conventions apply without
// every contributor having to remember `git config core.hooksPath .githooks`.
//
// Runs from package.json's `prepare` script, i.e. on every `npm install`.
// It never fails the install: no git binary, or a checkout that is not a git
// work tree (npm tarball, Docker build), is a reason to skip, not an error.
//
import { execFileSync } from 'node:child_process';

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

const configured = git('config', '--get', 'core.hooksPath');

if (configured === HOOKS_PATH) {
  process.exit(0);
}

// Someone with their own hooks directory made a deliberate choice; say what
// that costs them rather than overwriting it. `null` is the only "not set"
// answer — an empty string is a value somebody wrote, and it disables hooks.
if (configured !== null) {
  const shown = configured === '' ? 'an empty value' : `"${configured}"`;
  console.warn(
    `! core.hooksPath is set to ${shown}, leaving it alone.\n` +
      `  commit message validation is off — run \`git config core.hooksPath ${HOOKS_PATH}\` to enable it.`,
  );
  process.exit(0);
}

if (git('config', 'core.hooksPath', HOOKS_PATH) === null) {
  console.warn(`! could not set core.hooksPath, commit message validation is off`);
  process.exit(0);
}

console.log(`✓ commit message validation enabled (core.hooksPath = ${HOOKS_PATH})`);
