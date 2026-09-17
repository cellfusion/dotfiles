'use strict'

const os = require('node:os')
const path = require('node:path')
const { ConfigError } = require('./config-validator.js')
const { assertResolvedConfig, TIERS } = require('./config-types.js')

const CANDIDATE_REASONS = [
  'provider_missing_from_snapshot',
  'provider_unavailable',
  'auto_mode_unavailable',
  'model_unavailable',
  'thinking_option_unavailable',
]

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function exactKeys(value, keys, label) {
  const actual = isObject(value) ? Object.keys(value).sort() : []
  const expected = [...keys].sort()
  if (!isObject(value) || actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new ConfigError(`${label}: key set が不正である`)
  }
}

function nonEmptyString(value, label) {
  if (typeof value !== 'string' || value.length === 0) throw new ConfigError(`${label}: 非空 string が必要である`)
}

function assertUniqueStrings(values, label) {
  if (!Array.isArray(values) || !values.every((value) => typeof value === 'string')) {
    throw new ConfigError(`${label}: string 配列が必要である`)
  }
  if (new Set(values).size !== values.length) throw new ConfigError(`${label}: 重複がある`)
}

function materializeProviderId(family, environment, defaultEnvironment) {
  nonEmptyString(family, 'family')
  nonEmptyString(environment, 'environment')
  nonEmptyString(defaultEnvironment, 'defaultEnvironment')
  return environment === defaultEnvironment ? family : `${family}-${environment}`
}

function generatedProviderEntries(resolvedExport) {
  assertResolvedConfig(resolvedExport)
  if (resolvedExport.scope !== 'export') throw new ConfigError('resolved config: export scope が必要である')

  const entries = []
  const byId = new Map()
  const add = (family, environment) => {
    const id = materializeProviderId(family, environment, resolvedExport.defaultEnvironment)
    const provenance = `${family}/${environment}`
    const previous = byId.get(id)
    if (previous && previous !== provenance) {
      throw new ConfigError(`generated provider id ${id}: provenance が衝突する`)
    }
    if (!previous) {
      byId.set(id, provenance)
      entries.push({ id, family, environment })
    }
  }

  for (const family of resolvedExport.providerFamilies) add(family.family, resolvedExport.defaultEnvironment)
  for (const environment of resolvedExport.environments) {
    if (environment.name === resolvedExport.defaultEnvironment) continue
    for (const family of environment.eligibleFamilies) add(family, environment.name)
  }
  return { entries, byId }
}

function providerFamilyDefinition(resolvedExport, family) {
  const definition = resolvedExport.providerFamilies.find((provider) => provider.family === family)
  if (!definition) throw new ConfigError(`provider family ${family}: 未知である`)
  return definition
}

function runtimeConfigHome() {
  const configured = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config')
  if (!path.isAbsolute(configured)) throw new ConfigError('XDG_CONFIG_HOME: 絶対 path が必要である')
  return path.normalize(configured)
}

function materializeDirectoryPattern(pattern, environment) {
  nonEmptyString(pattern, 'provider directory pattern')
  nonEmptyString(environment, 'provider environment')
  const expanded = pattern
    .replaceAll('$XDG_CONFIG_HOME', () => runtimeConfigHome())
    .replaceAll('<environment>', () => environment)
  if (!path.isAbsolute(expanded) || expanded.includes('$')) {
    throw new ConfigError('provider directory pattern: physical path へ展開できない')
  }
  return path.normalize(expanded)
}

function providerPatch(resolvedExport, entry) {
  const family = providerFamilyDefinition(resolvedExport, entry.family)
  const environment = entry.environment
  const patch = {}
  if (environment !== resolvedExport.defaultEnvironment) patch.extends = entry.family
  patch.label = environment === resolvedExport.defaultEnvironment
    ? family.displayName
    : `${family.displayName} (${environment})`
  patch.env = {
    AGENT_ENV: environment,
    CHEZMOI_AGENT_CONFIG_MANAGED: '1',
  }

  if (family.setup !== null) {
    const configEnv = Object.entries(family.setup.configDirectoryEnv)
    for (const [key] of configEnv) {
      const pattern = environment === resolvedExport.defaultEnvironment
        ? family.setup.directoryPattern.primary
        : family.setup.directoryPattern.nonPrimary
      patch.env[key] = materializeDirectoryPattern(pattern, environment)
    }
  }
  return patch
}

function assertCandidateResolution(resolution) {
  if (!resolution || typeof resolution !== 'object' || Array.isArray(resolution)) {
    throw new ConfigError('resolved config: resolution が不正である')
  }
  if (!TIERS.includes(resolution.tier) || typeof resolution.environment !== 'string') {
    throw new ConfigError('resolved config: resolution の discriminator が不正である')
  }
  if (!Array.isArray(resolution.candidates) || resolution.candidates.length === 0) {
    throw new ConfigError('resolved config: resolution の candidate がない')
  }
}

function materializePaseo(resolved) {
  assertResolvedConfig(resolved)
  if (resolved.scope !== 'export') throw new ConfigError('materializePaseo: export scope が必要である')
  const generated = generatedProviderEntries(resolved)
  const providers = {}
  for (const entry of generated.entries) providers[entry.id] = providerPatch(resolved, entry)

  const profiles = []
  const profileIds = new Set()
  const warnings = []
  for (const resolution of resolved.resolutions) {
    assertCandidateResolution(resolution)
    const candidate = resolution.candidates[0]
    const providerId = materializeProviderId(candidate.family, resolution.environment, resolved.defaultEnvironment)
    if (!generated.byId.has(providerId)) {
      throw new ConfigError(`resolution ${resolution.environment}/${resolution.tier}: provider が materialize されない`)
    }
    const id = `agent_profile_managed_${resolution.tier}_${resolution.environment}`
    if (profileIds.has(id)) throw new ConfigError(`generated profile id ${id}: 重複する`)
    profileIds.add(id)
    // notes は Paseo の "When to use" 欄であり、子を作る側が profile を選ぶ根拠になる。
    profiles.push({
      id,
      name: `${resolution.tier}_${resolution.environment}`,
      provider: providerId,
      model: candidate.model,
      modeId: 'auto',
      thinkingOptionId: candidate.thinkingOptionId,
      featureValues: { ...candidate.featureValues },
      ...(resolution.notes === null ? {} : { notes: resolution.notes }),
    })
    for (const warning of resolution.warnings) {
      if (!warnings.includes(warning)) warnings.push(warning)
    }
  }

  return { profiles, providers, warnings }
}

function enumerateMaterializedProviderIds(resolvedExport) {
  return [...generatedProviderEntries(resolvedExport).byId.keys()].sort()
}

function featureAllowlistForProviderId(resolvedExport, providerId) {
  const generated = generatedProviderEntries(resolvedExport)
  const entry = generated.entries.find((candidate) => candidate.id === providerId)
  if (!entry) throw new ConfigError(`provider id ${providerId}: 未知である`)
  return { ...providerFamilyDefinition(resolvedExport, entry.family).featureAllowlist }
}

// materializeProviderId の逆を行う。family 名が `-` を含む場合に文字列の分解では
// 環境名と区別できないため、生成済みの entry を引く。
function environmentForProviderId(resolvedExport, providerId) {
  const generated = generatedProviderEntries(resolvedExport)
  const entry = generated.entries.find((candidate) => candidate.id === providerId)
  if (!entry) throw new ConfigError(`provider id ${providerId}: 未知である`)
  return entry.environment
}

function assertAvailabilitySnapshot(value) {
  exactKeys(value, ['version', 'type', 'providers', 'models'], 'snapshot')
  if (value.version !== 1 || value.type !== 'paseo-availability-snapshot') {
    throw new ConfigError('snapshot: discriminator が不正である')
  }
  if (!isObject(value.providers) || !isObject(value.models)) throw new ConfigError('snapshot: providers/models が object でない')

  const providerKeys = Object.keys(value.providers).sort()
  const modelKeys = Object.keys(value.models).sort()
  if (providerKeys.length !== modelKeys.length || providerKeys.some((key, index) => key !== modelKeys[index])) {
    throw new ConfigError('snapshot: providers と models の key set が違う')
  }

  for (const [providerId, provider] of Object.entries(value.providers)) {
    exactKeys(provider, ['available', 'modeIds'], `snapshot.providers.${providerId}`)
    if (typeof provider.available !== 'boolean') throw new ConfigError(`snapshot.providers.${providerId}: available が不正である`)
    assertUniqueStrings(provider.modeIds, `snapshot.providers.${providerId}.modeIds`)
  }

  for (const [providerId, models] of Object.entries(value.models)) {
    if (!Array.isArray(models)) throw new ConfigError(`snapshot.models.${providerId}: array が必要である`)
    for (const [index, model] of models.entries()) {
      exactKeys(model, ['id', 'thinkingOptionIds'], `snapshot.models.${providerId}[${index}]`)
      nonEmptyString(model.id, `snapshot.models.${providerId}[${index}].id`)
      assertUniqueStrings(model.thinkingOptionIds, `snapshot.models.${providerId}[${index}].thinkingOptionIds`)
    }
  }
  return value
}

function evaluateCandidate(providerId, candidate, snapshot) {
  const provider = snapshot.providers[providerId]
  if (!provider) return { providerId, candidate, reasonCode: 'provider_missing_from_snapshot' }
  if (provider.available !== true) return { providerId, candidate, reasonCode: 'provider_unavailable' }
  if (!provider.modeIds.includes('auto')) return { providerId, candidate, reasonCode: 'auto_mode_unavailable' }
  const model = snapshot.models[providerId].find((entry) => entry.id === candidate.model)
  if (!model) return { providerId, candidate, reasonCode: 'model_unavailable' }
  if (!model.thinkingOptionIds.includes(candidate.thinkingOptionId)) {
    return { providerId, candidate, reasonCode: 'thinking_option_unavailable' }
  }
  return { providerId, candidate, reasonCode: null }
}

function resolvePaseoLaunch(dispatch, snapshot) {
  assertResolvedConfig(dispatch)
  if (dispatch.scope !== 'dispatch') throw new ConfigError('resolvePaseoLaunch: dispatch scope が必要である')
  assertAvailabilitySnapshot(snapshot)
  if (dispatch.resolutions.length === 0) throw new ConfigError('resolvePaseoLaunch: resolution がない')
  const resolution = dispatch.resolutions[0]
  assertCandidateResolution(resolution)
  const attempted = resolution.candidates.map((candidate) => evaluateCandidate(
    materializeProviderId(candidate.family, resolution.environment, dispatch.defaultEnvironment),
    candidate,
    snapshot,
  ))
  const chosen = attempted.find((entry) => entry.reasonCode === null)
  const profileName = `${resolution.tier}_${resolution.environment}`
  if (chosen) {
    return {
      version: 1,
      type: 'mad-launch-spec',
      status: 'ok',
      profileName,
      environment: resolution.environment,
      tier: resolution.tier,
      provider: chosen.providerId,
      model: chosen.candidate.model,
      modeId: 'auto',
      thinkingOptionId: chosen.candidate.thinkingOptionId,
      featureValues: { ...chosen.candidate.featureValues },
      warnings: [...resolution.warnings],
    }
  }

  return {
    version: 1,
    type: 'mad-launch-failure',
    status: 'unresolved',
    reasonCode: 'candidates_exhausted',
    profileName,
    environment: resolution.environment,
    tier: resolution.tier,
    candidates: attempted.map((entry) => ({
      provider: entry.providerId,
      model: entry.candidate.model,
      thinkingOptionId: entry.candidate.thinkingOptionId,
      reasonCode: entry.reasonCode,
    })),
    warnings: [...resolution.warnings],
  }
}

module.exports = {
  CANDIDATE_REASONS,
  assertAvailabilitySnapshot,
  enumerateMaterializedProviderIds,
  environmentForProviderId,
  featureAllowlistForProviderId,
  materializePaseo,
  materializeProviderId,
  resolvePaseoLaunch,
}
