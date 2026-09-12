'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const { assertResolvedConfig, TIERS } = require('./config-types.js')
const { ConfigError } = require('./config-validator.js')

const PROVENANCE_ALLOWING_TIER_OVERRIDE = ['mad-fix', 'mad-escalation']
const REMOTE_UNAVAILABLE_WARNING = 'project remote unavailable; remote routing skipped'

function providerFamilies(config) {
  return Object.entries(config.providers).map(([family, definition]) => ({
    family,
    displayName: definition.displayName,
    setup: definition.setup,
    featureAllowlist: definition.featureAllowlist,
  }))
}

function resolvedEnvironments(config) {
  return Object.entries(config.environments).map(([name, definition]) => ({
    name,
    eligibleFamilies: [...definition.providers],
  }))
}

function staticCandidates(config, environment, tier) {
  const environmentTier = config.environments[environment].tiers[tier]
  if (environmentTier !== undefined) return { candidates: environmentTier.candidates, warnings: [] }
  return {
    candidates: config.tiers[tier].candidates,
    warnings: [`environment tier missing: ${environment}/${tier}; using common tier`],
  }
}

function allStaticResolutions(config) {
  const resolutions = []
  for (const [environment, definition] of Object.entries(config.environments)) {
    for (const tier of TIERS) {
      const selected = staticCandidates(config, environment, tier)
      const candidates = selected.candidates
        .filter((candidate) => definition.providers.includes(candidate.provider))
        .map((candidate) => ({
          family: candidate.provider,
          model: candidate.model,
          thinkingOptionId: candidate.thinkingOptionId,
          featureValues: candidate.featureValues,
        }))
      if (candidates.length === 0) throw new ConfigError(`resolution ${environment}/${tier}: candidate がない`)
      resolutions.push({ environment, tier, candidates, warnings: selected.warnings })
    }
  }
  return resolutions
}

function resolveExport(config) {
  return assertResolvedConfig({
    version: 1,
    type: 'resolved-config',
    scope: 'export',
    defaultEnvironment: config.defaults.environment,
    providerFamilies: providerFamilies(config),
    environments: resolvedEnvironments(config),
    resolutions: allStaticResolutions(config),
  })
}

function gitToplevel(canonical) {
  const result = spawnSync('git', ['-C', canonical, 'rev-parse', '--show-toplevel'], { encoding: 'utf8' })
  if (result.error || result.status !== 0) return null
  const output = (result.stdout || '').trim()
  if (output.length === 0) return null
  try {
    return fs.realpathSync.native(output)
  } catch {
    return null
  }
}

function requireProjectRoot(project) {
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
  let canonical
  try {
    canonical = fs.realpathSync.native(project)
  } catch {
    throw new ConfigError('project: realpath を取得できない')
  }
  const toplevel = gitToplevel(canonical)
  if (toplevel !== null && toplevel !== canonical) {
    throw new ConfigError('project: Git worktree の subdirectory である')
  }
  return canonical
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
  if (segments.some((segment) => segment.length === 0)) return null
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

function selectEnvironment(config, project, explicitEnvironment) {
  if (explicitEnvironment !== undefined) {
    if (!Object.prototype.hasOwnProperty.call(config.environments, explicitEnvironment)) {
      throw new ConfigError('environment: 正本に無い')
    }
    return { environment: explicitEnvironment, warnings: [] }
  }

  const warnings = []
  let remote
  let remoteLoaded = false
  for (const rule of config.projectRouting.rules) {
    const matchesPath = rule.match.path === undefined || pathMatches(project, rule.match.path)
    let matchesRemote = true
    if (rule.match.remote !== undefined) {
      if (!remoteLoaded) {
        remote = projectRemote(project)
        remoteLoaded = true
        if (remote === null) warnings.push(REMOTE_UNAVAILABLE_WARNING)
      }
      matchesRemote = remote !== null && remote === rule.match.remote
    }
    if (matchesPath && matchesRemote) return { environment: rule.environment, warnings }
  }
  return { environment: config.defaults.environment, warnings }
}

function selectTier(config, role, provenance, callerTier) {
  const warnings = []
  let requested = callerTier
  if (requested === 'fast') {
    requested = 'light'
    warnings.push('compatibility: tier alias normalized to light')
  }
  if (requested !== undefined) {
    if (!PROVENANCE_ALLOWING_TIER_OVERRIDE.includes(provenance)) {
      throw new ConfigError('tier: caller override は mad-fix と mad-escalation だけである')
    }
    if (!TIERS.includes(requested)) throw new ConfigError('tier: 未知の tier である')
    return { tier: requested, warnings }
  }
  const roleTier = config.agentRoles[role].tier
  if (roleTier) return { tier: roleTier, warnings }
  warnings.push(`tier missing for role ${role}; using work`)
  return { tier: 'work', warnings }
}

function resolveDispatch(config, input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new ConfigError('dispatch input: object が必要である')
  }
  const project = requireProjectRoot(input.project)
  if (!config.agentRoles || !Object.prototype.hasOwnProperty.call(config.agentRoles, input.role)) {
    throw new ConfigError('role: 正本に無い')
  }
  if (typeof input.provenance !== 'string' || input.provenance.length === 0) {
    throw new ConfigError('provenance: 非空 string が必要である')
  }
  const environmentSelection = selectEnvironment(config, project, input.environment)
  const { tier, warnings } = selectTier(config, input.role, input.provenance, input.tier)
  const exported = resolveExport(config)
  const resolution = exported.resolutions.find(
    (entry) => entry.environment === environmentSelection.environment && entry.tier === tier)
  if (!resolution) throw new ConfigError('dispatch resolution: environment と tier の組が無い')
  return assertResolvedConfig({
    ...exported,
    scope: 'dispatch',
    selection: { environment: environmentSelection.environment, tier },
    resolutions: [{
      ...resolution,
      warnings: [...resolution.warnings, ...environmentSelection.warnings, ...warnings],
    }],
  })
}

module.exports = { resolveExport, resolveDispatch, canonicalRemoteKey }
