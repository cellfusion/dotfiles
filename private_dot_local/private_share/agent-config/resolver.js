'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const { ConfigError } = require('./config-validator.js')

const REMOTE_UNAVAILABLE_WARNING = 'project remote unavailable; remote routing skipped'

function gitCommonDirectory(canonical, allowNonRepository = false) {
  const result = spawnSync(
    'git',
    ['-C', canonical, 'rev-parse', '--path-format=absolute', '--git-common-dir'],
    { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' } },
  )
  if (result.error) {
    throw new ConfigError(`project: Git を起動できない (${result.error.code || 'spawn error'})`)
  }
  if (result.status !== 0) {
    const detail = (result.stderr || '').trim().replace(/\s+/g, ' ')
    if (allowNonRepository && result.status === 128 && detail.startsWith('fatal: not a git repository')) {
      return null
    }
    throw new ConfigError(`project: Git common directory を取得できない (${detail || `exit ${result.status}`})`)
  }
  const output = (result.stdout || '').trim()
  if (!path.isAbsolute(output)) {
    throw new ConfigError('project: Git common directory が絶対 path ではない')
  }
  try {
    return fs.realpathSync.native(output)
  } catch (error) {
    throw new ConfigError(`project: Git common directory を canonicalize できない (${error.code || 'I/O'})`)
  }
}

function requireProjectDirectory(project) {
  if (typeof project !== 'string' || !path.isAbsolute(project)) {
    throw new ConfigError('project: 絶対 path が必要である')
  }
  let stats
  try {
    stats = fs.statSync(project)
  } catch {
    throw new ConfigError('project: 存在しない')
  }
  if (!stats.isDirectory()) throw new ConfigError('project: directory ではない')
  try {
    return fs.realpathSync.native(project)
  } catch {
    throw new ConfigError('project: realpath を取得できない')
  }
}

function canonicalHost(authority, scheme) {
  try {
    const parsed = new URL(`${scheme}://${authority}/`)
    if (parsed.protocol !== `${scheme}:` || parsed.hostname.length === 0) return null
    return parsed.hostname.toLowerCase()
  } catch {
    return null
  }
}

function canonicalPath(rawPath) {
  if (rawPath.length === 0) return null
  let remotePath = rawPath.startsWith('/') ? rawPath.slice(1) : rawPath
  if (remotePath.endsWith('/')) remotePath = remotePath.slice(0, -1)
  const segments = remotePath.split('/')
  if (segments.some((segment) => segment.length === 0 || segment === '.' || segment === '..')) return null
  remotePath = remotePath.endsWith('.git') ? remotePath.slice(0, -4) : remotePath
  return remotePath.length === 0 ? null : remotePath
}

function canonicalRemoteKey(originFetchUrl) {
  if (typeof originFetchUrl !== 'string' || originFetchUrl.length === 0 || /[?#]/.test(originFetchUrl)) {
    return null
  }

  const urlMatch = /^(ssh|https):\/\/([^/?#]+)(\/[^?#]*)?$/i.exec(originFetchUrl)
  if (urlMatch) {
    const scheme = urlMatch[1].toLowerCase()
    const host = canonicalHost(urlMatch[2], scheme)
    const remotePath = canonicalPath(urlMatch[3] || '')
    return host && remotePath ? `${host}/${remotePath}` : null
  }

  const scpMatch = /^(?:[^@\s/:]+@)?([^@\s/:]+):(.+)$/.exec(originFetchUrl)
  if (!scpMatch) return null
  const host = canonicalHost(scpMatch[1], 'ssh')
  const remotePath = canonicalPath(scpMatch[2])
  return host && remotePath ? `${host}/${remotePath}` : null
}

function projectRemote(project) {
  const result = spawnSync('git', ['-C', project, 'config', '--get-all', 'remote.origin.url'], { encoding: 'utf8' })
  if (result.error || result.status !== 0) return null
  const output = result.stdout || ''
  const urls = (output.endsWith('\n') ? output.slice(0, -1) : output).split('\n')
  if (urls.length !== 1 || urls[0].length === 0) return null
  return canonicalRemoteKey(urls[0])
}

function pathMatches(project, rulePath) {
  if (typeof rulePath !== 'string' || !path.isAbsolute(rulePath)) return false
  try {
    if (!fs.statSync(rulePath).isDirectory()) return false
    return fs.realpathSync.native(rulePath) === project
  } catch {
    return false
  }
}

// 親の環境名は --environment の次に強い。正本に無い名前は、--environment の有無に
// かかわらず設定の不正として扱う。
function selectEnvironmentFromCanonicalProject(config, project, explicitEnvironment, parentEnvironment) {
  const parent = typeof parentEnvironment === 'string' && parentEnvironment.length > 0
    ? parentEnvironment
    : undefined
  if (parent !== undefined && !Object.prototype.hasOwnProperty.call(config.environments, parent)) {
    throw new ConfigError('parent environment: 正本に無い')
  }
  if (explicitEnvironment !== undefined) {
    if (!Object.prototype.hasOwnProperty.call(config.environments, explicitEnvironment)) {
      throw new ConfigError('environment: 正本に無い')
    }
    return { environment: explicitEnvironment, warnings: [] }
  }
  if (parent !== undefined) return { environment: parent, warnings: [] }

  const warnings = []
  let projectRemoteKey
  let projectGitCommonDirectory
  for (const rule of config.projectRouting.rules) {
    const matchesPath = rule.match.path === undefined || pathMatches(project, rule.match.path)
    let matchesGitRepository = true
    if (rule.match.gitRepository !== undefined) {
      if (projectGitCommonDirectory === undefined) {
        projectGitCommonDirectory = gitCommonDirectory(project, true)
      }
      const ruleGitCommonDirectory = gitCommonDirectory(rule.match.gitRepository)
      matchesGitRepository = projectGitCommonDirectory !== null &&
        ruleGitCommonDirectory !== null &&
        projectGitCommonDirectory === ruleGitCommonDirectory
    }
    let matchesRemote = true
    if (rule.match.remote !== undefined || rule.match.remoteNamespace !== undefined) {
      if (projectRemoteKey === undefined) {
        projectRemoteKey = projectRemote(project)
        if (projectRemoteKey === null) warnings.push(REMOTE_UNAVAILABLE_WARNING)
      }
      matchesRemote = projectRemoteKey !== null &&
        (rule.match.remote === undefined || projectRemoteKey === rule.match.remote) &&
        (rule.match.remoteNamespace === undefined ||
          projectRemoteKey.startsWith(`${rule.match.remoteNamespace}/`))
    }
    if (matchesPath && matchesGitRepository && matchesRemote) {
      return { environment: rule.environment, warnings }
    }
  }
  return { environment: config.defaults.environment, warnings }
}

function selectEnvironment(config, project, explicitEnvironment, parentEnvironment) {
  return selectEnvironmentFromCanonicalProject(
    config,
    requireProjectDirectory(project),
    explicitEnvironment,
    parentEnvironment,
  )
}

module.exports = { selectEnvironment, canonicalRemoteKey }
