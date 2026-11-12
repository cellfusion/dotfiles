#!/usr/bin/env bash
# Project notes select a unique vault location shared by all Git worktrees.
set -u
source "$(dirname "$0")/lib/assert.sh"

if node - "$CHEZMOI_SOURCE" <<'NODE'
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const root = process.argv[2]
const script = path.join(root, 'private_dot_agents/skills/_shared/scripts/executable_agent-docs-dir')
const tmp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'vault-routing-')))
const repo = path.join(tmp, 'repo'), vault = path.join(tmp, 'vault'), projects = path.join(vault, '70_projects')
function git(cwd, ...args) {
  const result = spawnSync('git', ['-C', cwd, ...args], { encoding: 'utf8' })
  if (result.status !== 0) throw new Error(`git ${args.join(' ')}: ${result.stderr}`)
}
function resolve(cwd, ...args) {
  return spawnSync(script, args, { cwd, env: { ...process.env, OBSIDIAN_VAULT_PATH: vault }, encoding: 'utf8' })
}
try {
  fs.mkdirSync(repo); fs.mkdirSync(projects, { recursive: true })
  git(repo, 'init', '-q'); git(repo, 'config', 'user.name', 'Test'); git(repo, 'config', 'user.email', 'test@example.invalid')
  fs.writeFileSync(path.join(repo, 'file'), 'test'); git(repo, 'add', 'file'); git(repo, 'commit', '-qm', 'initial')
  git(repo, 'remote', 'add', 'origin', 'git@github.com:owner/project.git')
  fs.writeFileSync(path.join(projects, 'Note.md'), '---\ntype: project\nrepositories:\n  - "\\u00a0owner/project"\n---\n')
  const expected = path.join(projects, 'Note', 'owner', 'project', 'plans')
  let result = resolve(repo, 'plans')
  if (result.status !== 0 || result.stdout.trim() !== expected || !fs.statSync(expected).isDirectory()) throw new Error(`matched project: ${result.stderr}`)
  const wt = path.join(tmp, 'worktree'); git(repo, 'worktree', 'add', '-qb', 'work', wt)
  result = resolve(wt, 'plans')
  if (result.status !== 0 || result.stdout.trim() !== expected) throw new Error('worktree did not resolve to the same project')
  fs.writeFileSync(path.join(projects, 'Duplicate.md'), '---\ntype: project\nrepositories: [owner/project]\n---\n')
  if (resolve(repo, 'specs').status === 0) throw new Error('ambiguous mapping accepted')
  fs.unlinkSync(path.join(projects, 'Duplicate.md'))
  git(repo, 'remote', 'set-url', 'origin', 'git@example.com:owner/project.git')
  if (resolve(repo, 'specs').status === 0) throw new Error('non-GitHub remote accepted')
  git(repo, 'remote', 'set-url', 'origin', 'git@github.com:owner/unknown.git')
  if (resolve(repo, 'specs').status === 0) throw new Error('unregistered project accepted')
  if (resolve(repo, '../escape').status === 0) throw new Error('path traversal accepted')
} finally { fs.rmSync(tmp, { recursive: true, force: true }) }
NODE
then
  pass 'vault resolver routes unique projects and refuses unsafe mappings'
else
  fail_check 'vault resolver routes unique projects and refuses unsafe mappings'
fi
assert_summary
