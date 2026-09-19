'use strict'

const { ConfigError } = require('./config-validator.js')
const { assertResolvedConfig } = require('./config-types.js')
const { exactKeys, isObject, nonEmptyString, assertUniqueStrings, assertCandidateResolution } = require('./paseo-assert.js')
const { materializeProviderId } = require('./paseo-providers.js')

const CANDIDATE_REASONS = [
  'backend_unsupported',
  'provider_missing_from_snapshot',
  'provider_unavailable',
  'auto_mode_unavailable',
  'model_unavailable',
  'thinking_option_unavailable',
]

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
  if (!model.thinkingOptionIds.includes(candidate.effort)) {
    return { providerId, candidate, reasonCode: 'thinking_option_unavailable' }
  }
  return { providerId, candidate, reasonCode: null }
}

function backendsForFamily(dispatch, family) {
  const definition = dispatch.providerFamilies.find((provider) => provider.family === family)
  if (!definition) throw new ConfigError(`provider family ${family}: 未知である`)
  return definition.backends
}

function resolvePaseoLaunch(dispatch, snapshot) {
  assertResolvedConfig(dispatch)
  if (dispatch.scope !== 'dispatch') throw new ConfigError('resolvePaseoLaunch: dispatch scope が必要である')
  assertAvailabilitySnapshot(snapshot)
  if (dispatch.resolutions.length === 0) throw new ConfigError('resolvePaseoLaunch: resolution がない')
  const resolution = dispatch.resolutions[0]
  assertCandidateResolution(resolution)
  const attempted = resolution.candidates.map((candidate) => {
    const providerId = materializeProviderId(candidate.family, resolution.environment, dispatch.defaultEnvironment)
    if (!backendsForFamily(dispatch, candidate.family).includes('paseo')) {
      return { providerId, candidate, reasonCode: 'backend_unsupported' }
    }
    return evaluateCandidate(providerId, candidate, snapshot)
  })
  const chosen = attempted.find((entry) => entry.reasonCode === null)
  const selection = dispatch.selection
  if (chosen) {
    return {
      version: 1,
      type: 'mad-launch-spec',
      status: 'ok',
      environment: resolution.environment,
      duty: resolution.duty,
      complexity: resolution.complexity,
      requestedComplexity: selection.requestedComplexity,
      provider: chosen.providerId,
      model: chosen.candidate.model,
      modeId: 'auto',
      thinkingOptionId: chosen.candidate.effort,
      features: { ...chosen.candidate.features },
      warnings: [...resolution.warnings],
    }
  }

  return {
    version: 1,
    type: 'mad-launch-failure',
    status: 'unresolved',
    reasonCode: 'candidates_exhausted',
    environment: resolution.environment,
    duty: resolution.duty,
    complexity: resolution.complexity,
    requestedComplexity: selection.requestedComplexity,
    candidates: attempted.map((entry) => ({
      provider: entry.providerId,
      model: entry.candidate.model,
      thinkingOptionId: entry.candidate.effort,
      reasonCode: entry.reasonCode,
    })),
    warnings: [...resolution.warnings],
  }
}

module.exports = { CANDIDATE_REASONS, assertAvailabilitySnapshot, evaluateCandidate, resolvePaseoLaunch }
