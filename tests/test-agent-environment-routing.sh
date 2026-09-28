#!/usr/bin/env bash
# Git identity と remote namespace が project を正しい AI 環境へ解決することを検証する。
set -u

source "$(dirname "$0")/lib/assert.sh"

if node - "$CHEZMOI_SOURCE" <<'NODE'
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const source = process.argv[2]
const share = path.join(source, 'private_dot_local/private_share/agent-config')
const { validateConfig, ConfigError } = require(path.join(share, 'config-validator.js'))
const { resolveDispatch, selectEnvironment } = require(path.join(share, 'resolver.js'))
const samplePath = path.join(share, 'agent-config.sample.json')
const sample = JSON.parse(fs.readFileSync(samplePath, 'utf8'))
const temporary = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'agent-environment-routing-')))

function git(directory, ...args) {
  const result = spawnSync('git', ['-C', directory, ...args], { encoding: 'utf8' })
  if (result.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed: ${result.stderr}`)
  }
  return result.stdout.trim()
}

function initRepository(directory, remote) {
  fs.mkdirSync(directory, { recursive: true })
  git(directory, 'init', '-q')
  git(directory, 'config', 'user.name', 'Routing Test')
  git(directory, 'config', 'user.email', 'routing@example.test')
  fs.writeFileSync(path.join(directory, 'README.md'), 'fixture\n')
  git(directory, 'add', 'README.md')
  git(directory, 'commit', '-qm', 'fixture')
  if (remote) git(directory, 'remote', 'add', 'origin', remote)
}

function selection(config, project, explicitEnvironment, parentEnvironment) {
  return selectEnvironment(config, project, explicitEnvironment, parentEnvironment).environment
}

try {
  const main = path.join(temporary, 'main')
  const linked = path.join(temporary, 'linked')
  const unrelated = path.join(temporary, 'unrelated')
  const sameRemoteClone = path.join(temporary, 'same-remote-clone')
  const nonGit = path.join(temporary, 'non-git')
  const namespacePrefixCollision = path.join(temporary, 'namespace-prefix-collision')
  const nestedNamespace = path.join(temporary, 'nested-namespace')
  const nestedSibling = path.join(temporary, 'nested-sibling')
  const noOrigin = path.join(temporary, 'no-origin')
  const malformedDotRemote = path.join(temporary, 'malformed-dot-remote')
  const malformedDotDotRemote = path.join(temporary, 'malformed-dot-dot-remote')
  const remote = 'git@example.test:Org/Repo.git'
  initRepository(main, remote)
  git(main, 'worktree', 'add', '-qb', 'linked-test', linked)
  initRepository(unrelated, 'git@example.test:Org/Other.git')
  initRepository(sameRemoteClone, remote)
  initRepository(namespacePrefixCollision, 'git@example.test:Org-Other/Repo.git')
  initRepository(nestedNamespace, 'git@gitlab.example.test:Group/Subgroup/Repo.git')
  initRepository(nestedSibling, 'git@gitlab.example.test:Group/Other/Repo.git')
  initRepository(noOrigin)
  initRepository(malformedDotRemote, 'git@example.test:Org/./Repo.git')
  initRepository(malformedDotDotRemote, 'git@example.test:Org/../Other/Repo.git')
  fs.mkdirSync(nonGit)
  fs.mkdirSync(path.join(main, 'nested'))
  fs.mkdirSync(path.join(linked, 'nested'))
  const symlink = path.join(temporary, 'main-link')
  fs.symlinkSync(main, symlink)

  const value = structuredClone(sample)
  value.projectRouting.rules = [{
    name: 'same-git-repository',
    environment: 'lab',
    match: { gitRepository: main },
  }]
  const config = validateConfig(JSON.stringify(value)).config

  if (selection(config, main) !== 'lab') throw new Error('main checkout did not select lab')
  if (selection(config, path.join(main, 'nested')) !== 'lab') throw new Error('main subdirectory did not select lab')
  if (selection(config, linked) !== 'lab') throw new Error('linked worktree did not select lab')
  if (selection(config, path.join(linked, 'nested')) !== 'lab') throw new Error('linked subdirectory did not select lab')
  if (selection(config, symlink) !== 'lab') throw new Error('symlink cwd did not canonicalize to lab')
  if (selection(config, unrelated) !== 'primary') throw new Error('unrelated repo did not select default')
  if (selection(config, sameRemoteClone) !== 'primary') throw new Error('same-remote clone matched gitRepository')
  if (selection(config, nonGit) !== 'primary') throw new Error('non-Git directory did not select default')

  if (selection(config, main, 'primary', 'lab') !== 'primary') {
    throw new Error('explicit environment did not override parent')
  }
  if (selection(config, main, undefined, 'primary') !== 'primary') {
    throw new Error('parent environment did not override project rule')
  }

  const dispatch = resolveDispatch(config, {
    project: path.join(linked, 'nested'),
    role: 'implementer',
    provenance: 'routing-test',
    complexity: 'routine',
    round: 0,
  })
  if (dispatch.selection.environment !== 'lab') throw new Error('dispatch rejected or misrouted a worktree subdirectory')

  const originalPath = process.env.PATH
  process.env.PATH = ''
  let rejectedGitFailure = false
  try {
    selection(config, main)
  } catch (error) {
    rejectedGitFailure = error instanceof Error && error.message.includes('Git')
  } finally {
    process.env.PATH = originalPath
  }
  if (!rejectedGitFailure) throw new Error('Git invocation failure silently selected another environment')

  const exactValue = structuredClone(sample)
  exactValue.projectRouting.rules = [{ name: 'exact-only', environment: 'lab', match: { path: main } }]
  const exactConfig = validateConfig(JSON.stringify(exactValue)).config
  if (selection(exactConfig, main) !== 'lab' || selection(exactConfig, path.join(main, 'nested')) !== 'primary') {
    throw new Error('existing path matcher no longer uses exact canonical directory semantics')
  }

  const remoteValue = structuredClone(sample)
  remoteValue.projectRouting.rules = [{ name: 'same-remote', environment: 'lab', match: { remote: 'example.test/Org/Repo' } }]
  const remoteConfig = validateConfig(JSON.stringify(remoteValue)).config
  if (selection(remoteConfig, main) !== 'lab' || selection(remoteConfig, sameRemoteClone) !== 'lab') {
    throw new Error('remote matcher did not retain cross-clone semantics')
  }

  const namespaceValue = structuredClone(sample)
  namespaceValue.projectRouting.rules = [{
    name: 'same-organization',
    environment: 'lab',
    match: { remoteNamespace: 'example.test/Org' },
  }]
  const namespaceConfig = validateConfig(JSON.stringify(namespaceValue)).config
  if (selection(namespaceConfig, main) !== 'lab' ||
      selection(namespaceConfig, unrelated) !== 'lab' ||
      selection(namespaceConfig, sameRemoteClone) !== 'lab') {
    throw new Error('remoteNamespace did not match repositories in the same organization')
  }
  if (selection(namespaceConfig, namespacePrefixCollision) !== 'primary' ||
      selection(namespaceConfig, nestedNamespace) !== 'primary') {
    throw new Error('remoteNamespace matched a prefix collision or a different host')
  }

  for (const repository of [noOrigin, malformedDotRemote, malformedDotDotRemote]) {
    const result = selectEnvironment(namespaceConfig, repository)
    if (result.environment !== 'primary' ||
        result.warnings.length !== 1 ||
        result.warnings[0] !== 'project remote unavailable; remote routing skipped') {
      throw new Error(`unavailable remote did not warn and remain unmatched: ${repository}`)
    }
  }

  const combinedValue = structuredClone(sample)
  combinedValue.projectRouting.rules = [{
    name: 'namespace-and-path',
    environment: 'lab',
    match: { path: main, remoteNamespace: 'example.test/Other' },
  }]
  const combinedConfig = validateConfig(JSON.stringify(combinedValue)).config
  if (selection(combinedConfig, main) !== 'primary') {
    throw new Error('remoteNamespace was ORed with another matcher instead of ANDed')
  }

  const orderedValue = structuredClone(sample)
  orderedValue.projectRouting.rules = [
    { name: 'first', environment: 'lab', match: { remoteNamespace: 'example.test/Org' } },
    { name: 'second', environment: 'primary', match: { remoteNamespace: 'example.test/Org' } },
  ]
  const orderedConfig = validateConfig(JSON.stringify(orderedValue)).config
  if (selection(orderedConfig, main) !== 'lab') {
    throw new Error('remoteNamespace rules did not preserve first-match precedence')
  }

  const nestedNamespaceValue = structuredClone(sample)
  nestedNamespaceValue.projectRouting.rules = [{
    name: 'nested-group',
    environment: 'lab',
    match: { remoteNamespace: 'gitlab.example.test/Group/Subgroup' },
  }]
  const nestedNamespaceConfig = validateConfig(JSON.stringify(nestedNamespaceValue)).config
  if (selection(nestedNamespaceConfig, nestedNamespace) !== 'lab' ||
      selection(nestedNamespaceConfig, nestedSibling) !== 'primary') {
    throw new Error('remoteNamespace did not preserve a nested namespace boundary')
  }

  for (const remoteNamespace of [
    'example.test/Org.git',
    'example.test/Org/./Team',
    'example.test/Org/../Team',
  ]) {
    const invalidNamespace = structuredClone(sample)
    invalidNamespace.projectRouting.rules = [{
      name: 'invalid-namespace',
      environment: 'lab',
      match: { remoteNamespace },
    }]
    let validationError
    try {
      validateConfig(JSON.stringify(invalidNamespace))
    } catch (error) {
      validationError = error
    }
    if (!(validationError instanceof ConfigError) ||
        !validationError.message.includes('remoteNamespace path が不正')) {
      throw new Error(`invalid remoteNamespace was not specifically rejected: ${remoteNamespace}`)
    }
  }

  const invalidNonGit = structuredClone(sample)
  invalidNonGit.projectRouting.rules = [{ name: 'not-git', environment: 'lab', match: { gitRepository: nonGit } }]
  let rejectedNonGit = false
  try { validateConfig(JSON.stringify(invalidNonGit)) } catch { rejectedNonGit = true }
  if (!rejectedNonGit) throw new Error('non-Git gitRepository rule was accepted')

  const invalidSymlink = structuredClone(sample)
  invalidSymlink.projectRouting.rules = [{ name: 'symlink', environment: 'lab', match: { gitRepository: symlink } }]
  let rejectedSymlink = false
  try { validateConfig(JSON.stringify(invalidSymlink)) } catch { rejectedSymlink = true }
  if (!rejectedSymlink) throw new Error('non-canonical gitRepository rule was accepted')

  let rejectedParent = false
  try { selection(config, main, undefined, 'missing') } catch { rejectedParent = true }
  if (!rejectedParent) throw new Error('unknown parent environment was accepted')
} finally {
  spawnSync('git', ['-C', path.join(temporary, 'main'), 'worktree', 'remove', '--force', path.join(temporary, 'linked')])
  fs.rmSync(temporary, { recursive: true, force: true })
}
NODE
then
  pass 'Git identity and remote namespace rules preserve boundaries, ordering, and failure behavior'
else
  fail_check 'Git identity and remote namespace rules preserve boundaries, ordering, and failure behavior'
fi

assert_summary
