'use strict'

const { assertResolvedConfig, TIERS } = require('./config-types.js')
const { ConfigError } = require('./config-validator.js')

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

module.exports = { resolveExport }
