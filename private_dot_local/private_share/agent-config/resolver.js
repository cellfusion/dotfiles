'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const { assertResolvedConfig, DUTIES, COMPLEXITIES } = require('./config-types.js')
const { ConfigError } = require('./config-validator.js')

const REMOTE_UNAVAILABLE_WARNING = 'project remote unavailable; remote routing skipped'

function providerFamilies(config) {
  return Object.entries(config.providers).map(([family, definition]) => ({
    family,
    displayName: definition.displayName,
    backends: [...definition.backends],
    setup: definition.setup,
    environmentVariable: definition.environmentVariable || null,
    featureAllowlist: definition.featureAllowlist,
  }))
}

function resolvedEnvironments(config) {
  return Object.entries(config.environments).map(([name, definition]) => ({
    name,
    eligibleFamilies: [...definition.providers],
  }))
}

// notes は採用した枠の定義のものだけを使う。環境の枠が notes を持たないときに共通の枠の
// notes を借りると、説明と候補の出所がずれる。
function staticCandidates(config, environment, duty, complexity) {
  const override = config.environments[environment].selection
  const byDuty = override === undefined ? undefined : override[duty]
  const slot = byDuty === undefined ? undefined : byDuty[complexity]
  if (slot !== undefined) {
    return { candidates: slot.candidates, notes: slot.notes, warnings: [] }
  }
  const common = config.selection[duty][complexity]
  return {
    candidates: common.candidates,
    notes: common.notes,
    warnings: [`selection slot missing: ${environment}/${duty}/${complexity}; using common selection`],
  }
}

function allStaticResolutions(config) {
  const resolutions = []
  for (const [environment, definition] of Object.entries(config.environments)) {
    for (const duty of DUTIES) {
      for (const complexity of COMPLEXITIES) {
        const selected = staticCandidates(config, environment, duty, complexity)
        const candidates = selected.candidates
          .filter((candidate) => definition.providers.includes(candidate.provider))
          .map((candidate) => ({
            family: candidate.provider,
            model: candidate.model,
            effort: candidate.effort,
            features: candidate.features,
          }))
        if (candidates.length === 0) {
          throw new ConfigError(`resolution ${environment}/${duty}/${complexity}: candidate がない`)
        }
        const notes = selected.notes === undefined ? null : selected.notes
        resolutions.push({ environment, duty, complexity, notes, candidates, warnings: selected.warnings })
      }
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

const ESCALATION = { simple: 'routine', routine: 'complex', complex: 'complex', critical: 'critical' }
const WORK_CLASS_COMPLEXITY = { mechanical: 'simple', routine: 'routine', integration: 'complex', architectural: 'critical' }
const REVIEW_WORK_CLASS_ROLES = new Set(['task-reviewer', 're-reviewer', 'final-reviewer'])

function selectDuty(config, role) {
  const roleDuty = config.agentRoles[role].duty
  if (roleDuty) return { duty: roleDuty, warnings: [] }
  return { duty: 'review', warnings: [`duty missing for role ${role}; using review`] }
}

// 引き上げるのは指摘を修正する実装役だけである。再レビューの子は provenance が
// mad-review なので、round が 2 以上でも据え置く。
function selectComplexity(config, duty, provenance, callerComplexity, callerRound, workClass) {
  const warnings = []
  let requested
  if (callerComplexity === undefined) {
    requested = config.defaults.complexity
    warnings.push('complexity missing; using defaults.complexity')
  } else {
    if (!COMPLEXITIES.includes(callerComplexity)) throw new ConfigError('complexity: 未知の複雑度である')
    requested = callerComplexity
  }
  if (duty === 'review' && workClass !== undefined) {
    if (!Object.prototype.hasOwnProperty.call(WORK_CLASS_COMPLEXITY, workClass)) {
      throw new ConfigError('workClass: 未知の work class である')
    }
    requested = WORK_CLASS_COMPLEXITY[workClass]
  }
  let round = 0
  if (callerRound !== undefined) {
    if (!Number.isInteger(callerRound) || callerRound < 0) throw new ConfigError('round: 0 以上の整数が必要である')
    round = callerRound
  }
  const hasAttemptPolicy = config.attemptPolicy && config.attemptPolicy[duty] &&
    config.attemptPolicy[duty][requested]
  if (provenance === 'mad-fix' && round >= 2 && !hasAttemptPolicy) {
    const escalated = ESCALATION[requested]
    if (escalated !== requested) {
      warnings.push(`complexity escalated: ${requested} -> ${escalated} (round ${round})`)
    }
    return { complexity: escalated, requestedComplexity: requested, warnings }
  }
  return { complexity: requested, requestedComplexity: requested, warnings }
}

function selectSingleCandidates(config, environment, duty, complexity, backend) {
  if (backend !== 'paseo-cli') return null
  const slot = duty === 'implement'
    ? config.singleSelection && config.singleSelection.implement[complexity]
    : duty === 'review'
      ? config.selection && config.selection.review && config.selection.review[complexity]
      : null
  if (!slot) throw new ConfigError(`paseo-cli backend: ${duty} selection is unavailable`)
  const eligible = config.environments[environment].providers
  const candidates = slot.candidates
    .filter((candidate) => eligible.includes(candidate.provider))
    .map((candidate) => ({
      family: candidate.provider,
      model: candidate.model,
      effort: candidate.effort,
      features: candidate.features,
    }))
  if (candidates.length === 0) throw new ConfigError(`paseo-cli ${duty} ${environment}/${complexity}: candidate がない`)
  if (candidates.some((candidate) => Object.keys(candidate.features).length > 0)) {
    throw new ConfigError('paseo-cli backend: provider feature は未対応である')
  }
  return { candidates, warnings: ['backend policy: paseo-cli'] }
}

function selectRoutingCandidates(config, environment, role) {
  const roleConfig = config.agentRoles[role]
  if (!roleConfig || !['routing', 'escalation'].includes(roleConfig.launchPolicy)) return null
  const selectionName = roleConfig.launchPolicy === 'routing' ? 'routingSelection' : 'escalationSelection'
  const selection = config[selectionName]
  if (!selection) throw new ConfigError(`${selectionName}: ${role} に必要である`)
  const eligible = config.environments[environment].providers
  const candidates = selection.candidates
    .filter((candidate) => eligible.includes(candidate.provider))
    .map((candidate) => ({
      family: candidate.provider,
      model: candidate.model,
      effort: candidate.effort,
      features: candidate.features,
    }))
  if (candidates.length === 0) throw new ConfigError(`routingSelection ${environment}: candidate がない`)
  return { candidates, warnings: [`launch policy: ${roleConfig.launchPolicy}`] }
}

function selectAttemptCandidates(config, environment, duty, complexity, provenance, round, attemptLevel) {
  const isInitialDispatch = provenance === 'mad-dispatch' && round === 0
  const isFixAttempt = provenance === 'mad-fix' && round >= 1
  if (!isInitialDispatch && !isFixAttempt) return null
  const policy = config.attemptPolicy && config.attemptPolicy[duty] && config.attemptPolicy[duty][complexity]
  if (!policy) return null

  if (attemptLevel !== undefined && (!Number.isInteger(attemptLevel) || attemptLevel < 0)) {
    throw new ConfigError('attemptLevel: 0 以上の整数が必要である')
  }
  const levelIndex = attemptLevel === undefined
    ? (isInitialDispatch ? 0 : Math.min(round, policy.levels.length - 1))
    : Math.min(attemptLevel, policy.levels.length - 1)
  const level = policy.levels[levelIndex]
  const eligible = config.environments[environment].providers
  const candidates = level.candidates
    .filter((candidate) => eligible.includes(candidate.provider))
    .map((candidate) => ({
      family: candidate.provider,
      model: candidate.model,
      effort: candidate.effort,
      features: candidate.features,
    }))
  if (candidates.length === 0) {
    throw new ConfigError(`attemptPolicy ${environment}/${duty}/${complexity}/levels[${levelIndex}]: candidate がない`)
  }

  const attemptLabel = isInitialDispatch ? 'initial dispatch' : `mad-fix round ${round}`
  const warnings = [`attempt policy: ${duty}/${complexity} level ${levelIndex} for ${attemptLabel}`]
  if (isFixAttempt && round >= policy.levels.length) {
    warnings.push(`attempt policy exhausted: reusing level ${levelIndex}`)
  }
  return { candidates, warnings }
}

function resolveDispatch(config, input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new ConfigError('dispatch input: object が必要である')
  }
  const project = requireProjectDirectory(input.project)
  if (!config.agentRoles || !Object.prototype.hasOwnProperty.call(config.agentRoles, input.role)) {
    throw new ConfigError('role: 正本に無い')
  }
  if (typeof input.provenance !== 'string' || input.provenance.length === 0) {
    throw new ConfigError('provenance: 非空 string が必要である')
  }
  const environmentSelection = selectEnvironmentFromCanonicalProject(
    config,
    project,
    input.environment,
    input.parentEnvironment,
  )
  const dutySelection = selectDuty(config, input.role)
  if (dutySelection.duty === 'review' && REVIEW_WORK_CLASS_ROLES.has(input.role) && input.workClass === undefined) {
    throw new ConfigError(`workClass: ${input.role} には work class が必要である`)
  }
  const complexitySelection = selectComplexity(config, dutySelection.duty, input.provenance, input.complexity, input.round, input.workClass)
  const warnings = [...dutySelection.warnings, ...complexitySelection.warnings]
  const exported = resolveExport(config)
  const resolution = exported.resolutions.find(
    (entry) => entry.environment === environmentSelection.environment &&
      entry.duty === dutySelection.duty && entry.complexity === complexitySelection.complexity)
  if (!resolution) throw new ConfigError('dispatch resolution: environment と duty と complexity の組が無い')
  const attemptSelection = selectAttemptCandidates(
    config,
    environmentSelection.environment,
    dutySelection.duty,
    complexitySelection.complexity,
    input.provenance,
    input.round === undefined ? 0 : input.round,
    input.attemptLevel,
  )
  const singleSelection = selectSingleCandidates(
    config,
    environmentSelection.environment,
    dutySelection.duty,
    complexitySelection.complexity,
    input.backend,
  )
  const routingSelection = selectRoutingCandidates(config, environmentSelection.environment, input.role)
  const selectedResolution = routingSelection !== null
    ? { ...resolution, candidates: routingSelection.candidates }
    : attemptSelection !== null
      ? { ...resolution, candidates: attemptSelection.candidates }
      : singleSelection !== null
        ? { ...resolution, candidates: singleSelection.candidates }
        : resolution
  return assertResolvedConfig({
    ...exported,
    scope: 'dispatch',
    selection: {
      environment: environmentSelection.environment,
      duty: dutySelection.duty,
      complexity: complexitySelection.complexity,
      requestedComplexity: complexitySelection.requestedComplexity,
    },
    resolutions: [{
      ...selectedResolution,
      warnings: [
        ...selectedResolution.warnings,
        ...environmentSelection.warnings,
        ...warnings,
        ...(routingSelection === null ? [] : routingSelection.warnings),
        ...(singleSelection === null ? [] : singleSelection.warnings),
        ...(attemptSelection === null ? [] : attemptSelection.warnings),
      ],
    }],
  })
}

module.exports = { resolveExport, resolveDispatch, selectEnvironment, canonicalRemoteKey }
