'use strict'

const os = require('node:os')
const path = require('node:path')
const { ConfigError } = require('./config-validator.js')
const { assertResolvedConfig } = require('./config-types.js')
const { nonEmptyString, assertCandidateResolution } = require('./paseo-assert.js')

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

function materializePaseoProviders(resolved) {
  assertResolvedConfig(resolved)
  if (resolved.scope !== 'export') throw new ConfigError('materializePaseoProviders: export scope が必要である')
  const generated = generatedProviderEntries(resolved)
  const providers = {}
  for (const entry of generated.entries) providers[entry.id] = providerPatch(resolved, entry)

  const warnings = []
  for (const resolution of resolved.resolutions) {
    assertCandidateResolution(resolution)
    const candidate = resolution.candidates[0]
    const providerId = materializeProviderId(candidate.family, resolution.environment, resolved.defaultEnvironment)
    if (!generated.byId.has(providerId)) {
      throw new ConfigError(`resolution ${resolution.environment}/${resolution.duty}/${resolution.complexity}: provider が materialize されない`)
    }
    for (const warning of resolution.warnings) {
      if (!warnings.includes(warning)) warnings.push(warning)
    }
  }
  return { providers, warnings }
}

module.exports = {
  materializeProviderId,
  providerPatch,
  generatedProviderEntries,
  providerFamilyDefinition,
  runtimeConfigHome,
  materializeDirectoryPattern,
  enumerateMaterializedProviderIds,
  environmentForProviderId,
  featureAllowlistForProviderId,
  materializePaseoProviders,
}
