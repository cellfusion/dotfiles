'use strict'

const DUTIES = ['author', 'implement', 'review', 'synthesize']
const COMPLEXITIES = ['simple', 'routine', 'complex', 'critical']
const PASEO_FIELDS = ['provider', 'profileName', 'modeId', 'thinkingOptionId', 'featureValues',
  'extends', 'label', 'env', 'reasonCode', 'snapshot', 'providerId']
const EXPORT_KEYS = ['version', 'type', 'scope', 'defaultEnvironment', 'providerFamilies', 'environments', 'resolutions']
const DISPATCH_KEYS = [...EXPORT_KEYS, 'selection']
const SCHEMA_KEYWORDS = ['$schema', '$id', 'title', 'description', 'type', 'const', 'enum', 'required',
  'properties', 'patternProperties', 'propertyNames', 'additionalProperties', 'pattern', 'minLength',
  'minItems', 'minProperties', 'uniqueItems', 'items']

function assertExactObject(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('resolved-config: object を期待した')
  if (Object.keys(value).sort().join(' ') !== [...keys].sort().join(' ')) throw new TypeError('resolved-config: key set が違う')
}

function assertNonEmptyString(value) {
  if (typeof value !== 'string' || value.length === 0) throw new TypeError('resolved-config: 非空 string を期待した')
}

function assertNoPaseoField(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return
  for (const field of PASEO_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(value, field)) throw new TypeError(`resolved-config: Paseo 固有 field ${field}`)
  }
}

function assertFeatureValues(value) {
  assertNoPaseoField(value)
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('resolved-config: features は object')
  for (const [key, scalar] of Object.entries(value)) {
    if (!/^[a-z][a-z0-9_-]*$/.test(key)) throw new TypeError('resolved-config: features の key が不正')
    const scalarType = typeof scalar
    const ok = scalarType === 'boolean' || scalarType === 'string' || (scalarType === 'number' && Number.isFinite(scalar))
    if (!ok) throw new TypeError('resolved-config: features の値が許可した scalar でない')
  }
}

function assertSetup(value) {
  assertExactObject(value, ['configDirectoryEnv', 'directoryPattern', 'symlinks', 'preservedMutable', 'existingPathPolicy'])
  assertNoPaseoField(value)
  const entries = Object.entries(value.configDirectoryEnv || {})
  assertNoPaseoField(value.configDirectoryEnv)
  if (entries.length !== 1 || !/^[A-Z][A-Z0-9_]*$/.test(entries[0][0]) || !/^[a-z][a-z0-9-]*$/.test(entries[0][1])) {
    throw new TypeError('resolved-config: configDirectoryEnv が不正')
  }
  assertExactObject(value.directoryPattern, ['primary', 'nonPrimary'])
  assertNoPaseoField(value.directoryPattern)
  assertNonEmptyString(value.directoryPattern.primary)
  assertNonEmptyString(value.directoryPattern.nonPrimary)
  for (const list of [value.symlinks, value.preservedMutable]) {
    if (!Array.isArray(list) || !list.every((entry) => typeof entry === 'string' && entry.length > 0)) {
      throw new TypeError('resolved-config: setup の path 配列が不正')
    }
  }
  if (value.existingPathPolicy !== 'reject-real-or-wrong-symlink') throw new TypeError('resolved-config: existingPathPolicy が不正')
}

function assertProviderFamily(value) {
  assertExactObject(value, ['family', 'displayName', 'backends', 'setup', 'featureAllowlist'])
  assertNoPaseoField(value)
  assertNonEmptyString(value.family)
  assertNonEmptyString(value.displayName)
  if (!Array.isArray(value.backends) || value.backends.length === 0) throw new TypeError('resolved-config: backends が不正')
  value.backends.forEach(assertNonEmptyString)
  if (new Set(value.backends).size !== value.backends.length) throw new TypeError('resolved-config: backends が重複する')
  if (value.setup !== null) assertSetup(value.setup)
  assertNoPaseoField(value.featureAllowlist)
  if (!value.featureAllowlist || typeof value.featureAllowlist !== 'object' || Array.isArray(value.featureAllowlist)) {
    throw new TypeError('resolved-config: featureAllowlist は object')
  }
  for (const [key, scalarType] of Object.entries(value.featureAllowlist)) {
    if (!/^[a-z][a-z0-9_-]*$/.test(key) || !['boolean', 'string', 'integer'].includes(scalarType)) {
      throw new TypeError('resolved-config: featureAllowlist が不正')
    }
  }
}

function assertResolution(value) {
  assertExactObject(value, ['environment', 'duty', 'complexity', 'notes', 'candidates', 'warnings'])
  assertNoPaseoField(value)
  assertNonEmptyString(value.environment)
  if (!DUTIES.includes(value.duty)) throw new TypeError('resolved-config: duty が不正')
  if (!COMPLEXITIES.includes(value.complexity)) throw new TypeError('resolved-config: complexity が不正')
  if (value.notes !== null) assertNonEmptyString(value.notes)
  if (!Array.isArray(value.candidates) || !Array.isArray(value.warnings)) throw new TypeError('resolved-config: resolution の配列が不正')
  for (const candidate of value.candidates) {
    assertExactObject(candidate, ['family', 'model', 'effort', 'features'])
    assertNoPaseoField(candidate)
    assertNonEmptyString(candidate.family)
    assertNonEmptyString(candidate.model)
    assertNonEmptyString(candidate.effort)
    assertFeatureValues(candidate.features)
  }
  if (!value.warnings.every((warning) => typeof warning === 'string')) throw new TypeError('resolved-config: warnings が不正')
}

function assertResolvedConfig(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('resolved-config: object を期待した')
  assertNoPaseoField(value)
  assertExactObject(value, value.scope === 'dispatch' ? DISPATCH_KEYS : EXPORT_KEYS)
  if (value.version !== 1 || value.type !== 'resolved-config' || !['export', 'dispatch'].includes(value.scope)) {
    throw new TypeError('resolved-config: discriminator が不正')
  }
  assertNonEmptyString(value.defaultEnvironment)
  if (!Array.isArray(value.providerFamilies) || !Array.isArray(value.environments) || !Array.isArray(value.resolutions)) {
    throw new TypeError('resolved-config: 配列が不正')
  }
  value.providerFamilies.forEach(assertProviderFamily)
  for (const environment of value.environments) {
    assertExactObject(environment, ['name', 'eligibleFamilies'])
    assertNoPaseoField(environment)
    assertNonEmptyString(environment.name)
    if (!Array.isArray(environment.eligibleFamilies) ||
        !environment.eligibleFamilies.every((family) => typeof family === 'string' && family.length > 0)) {
      throw new TypeError('resolved-config: eligibleFamilies が不正')
    }
  }
  if (!value.environments.some((environment) => environment.name === value.defaultEnvironment)) {
    throw new TypeError('resolved-config: defaultEnvironment が environments にない')
  }
  value.resolutions.forEach(assertResolution)
  if (value.scope === 'dispatch') {
    assertExactObject(value.selection, ['environment', 'duty', 'complexity', 'requestedComplexity'])
    assertNoPaseoField(value.selection)
    assertNonEmptyString(value.selection.environment)
    if (!DUTIES.includes(value.selection.duty)) throw new TypeError('resolved-config: selection.duty が不正')
    if (!COMPLEXITIES.includes(value.selection.complexity)) throw new TypeError('resolved-config: selection.complexity が不正')
    if (!COMPLEXITIES.includes(value.selection.requestedComplexity)) {
      throw new TypeError('resolved-config: selection.requestedComplexity が不正')
    }
  }
  return value
}

module.exports = { DUTIES, COMPLEXITIES, PASEO_FIELDS, SCHEMA_KEYWORDS, assertResolvedConfig }
