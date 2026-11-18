import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseGitStatus, thinkingIcon, sessionCosts, contextBar, worktreeName } from '../private_dot_pi/agent/extensions/omp-footer/helpers.mjs';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

test('shows a name only for a linked worktree', () => {
  const dir = mkdtempSync(join(tmpdir(), 'pi-worktree-'));
  const repo = join(dir, 'main');
  const linked = join(dir, 'feature');
  const git = (cwd, ...args) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    git(dir, 'init', repo);
    git(repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '--allow-empty', '-m', 'init');
    git(repo, 'worktree', 'add', '-b', 'feature', linked);
    const dirs = (cwd) => git(cwd, 'rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir');
    assert.equal(worktreeName(repo, dirs(repo)), '');
    assert.equal(worktreeName(linked, dirs(linked)), 'feature');
    assert.equal(worktreeName(linked, ''), '');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('counts changed and untracked files, including renames', () => {
  assert.deepEqual(parseGitStatus(' M one\0?? two\0R  new\0old\0'), { changed: 2, untracked: 1 });
});
test('maps thinking levels without conflating unsupported levels', () => {
  assert.equal(thinkingIcon('xhigh'), '󰪥');
  assert.equal(thinkingIcon('off'), '');
  assert.equal(thinkingIcon('max'), '');
  assert.equal(thinkingIcon('unknown'), '');
});
test('sums assistant and tool usage and reports latest request cost', () => {
  const entries = [
    { type: 'message', message: { role: 'assistant', usage: { cost: { total: 2 } } } },
    { type: 'message', message: { role: 'toolResult', usage: { cost: { total: 0.3 } } } },
    { type: 'message', message: { role: 'assistant', usage: { cost: { total: 0.15 } } } },
  ];
  assert.deepEqual(sessionCosts(entries), { total: 2.4499999999999997, latest: 0.15 });
  assert.deepEqual(sessionCosts([]), { total: 0, latest: undefined });
});
test('context meter is bounded and handles unknown usage', () => {
  assert.equal(contextBar(42, 10), '━━━42%────');
  assert.equal(contextBar(null, 8), ' ? ─────');
  assert.equal(contextBar(180, 8), '━━━━100%');
});
