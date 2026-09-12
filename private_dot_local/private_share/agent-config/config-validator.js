'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { TIERS, SCHEMA_KEYWORDS } = require('./config-types.js')

class ConfigError extends Error {
  constructor(message) {
    super(message)
    this.name = 'ConfigError'
    this.exitCode = 2
  }
}

const KNOWN_SETUP_FAMILIES = ['claude', 'codex']
const SECRET_SUBSTRINGS = ['credential', 'token', 'key', 'password', 'secret', 'auth', 'session', 'cookie', 'history']
const RESERVED_ENV_NAMES = ['agent_env', 'chezmoi_agent_config_managed', 'paseo_managed', 'xdg_config_home']
const SCHEMA_PATH = path.join(__dirname, 'agent-config.schema.json')

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function matchesType(value, expected) {
  if (expected === 'null') return value === null
  if (expected === 'object') return isObject(value)
  if (expected === 'array') return Array.isArray(value)
  if (expected === 'string') return typeof value === 'string'
  if (expected === 'number') return typeof value === 'number' && Number.isFinite(value)
  if (expected === 'integer') return typeof value === 'number' && Number.isInteger(value) && Number.isFinite(value)
  if (expected === 'boolean') return typeof value === 'boolean'
  return false
}

function describe(pointer) {
  return pointer || '(root)'
}

function validateAgainstSchema(schema, data, pointer) {
  if (!schema || typeof schema !== 'object' || Array.isArray(schema)) return []
  const errors = []

  if (schema.type !== undefined) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type]
    if (!types.some((type) => matchesType(data, type))) {
      errors.push(`${describe(pointer)}: type が不正`)
      return errors
    }
  }
  if (schema.const !== undefined && data !== schema.const) {
    errors.push(`${describe(pointer)}: const が不正`)
  }
  if (schema.enum !== undefined && !schema.enum.includes(data)) {
    errors.push(`${describe(pointer)}: enum が不正`)
  }

  if (schema.oneOf !== undefined) {
    const matches = schema.oneOf.filter((branch) => validateAgainstSchema(branch, data, pointer).length === 0)
    if (matches.length !== 1) errors.push(`${describe(pointer)}: oneOf が不正`)
  }

  if (schema.required !== undefined && isObject(data)) {
    for (const key of schema.required) {
      if (!Object.prototype.hasOwnProperty.call(data, key)) {
        errors.push(`${describe(pointer)}: required field ${key} がない`)
      }
    }
  }

  if (schema.properties !== undefined && isObject(data)) {
    for (const [key, childSchema] of Object.entries(schema.properties)) {
      if (Object.prototype.hasOwnProperty.call(data, key)) {
        errors.push(...validateAgainstSchema(childSchema, data[key], `${pointer}.${key}`))
      }
    }
  }

  const patternEntries = schema.patternProperties === undefined ? [] : Object.entries(schema.patternProperties)
  if (patternEntries.length > 0 && isObject(data)) {
    for (const [key, value] of Object.entries(data)) {
      for (const [pattern, childSchema] of patternEntries) {
        if (new RegExp(pattern).test(key)) {
          errors.push(...validateAgainstSchema(childSchema, value, `${pointer}.${key}`))
        }
      }
    }
  }

  if (schema.propertyNames !== undefined && isObject(data)) {
    for (const key of Object.keys(data)) {
      errors.push(...validateAgainstSchema(schema.propertyNames, key, `${pointer}.${key}`))
    }
  }

  if (schema.additionalProperties === false && isObject(data)) {
    for (const key of Object.keys(data)) {
      const declared = schema.properties && Object.prototype.hasOwnProperty.call(schema.properties, key)
      const patterned = patternEntries.some(([pattern]) => new RegExp(pattern).test(key))
      if (!declared && !patterned) errors.push(`${describe(pointer)}: unknown field ${key}`)
    }
  } else if (isObject(data) && isObject(schema.additionalProperties)) {
    for (const key of Object.keys(data)) {
      const declared = schema.properties && Object.prototype.hasOwnProperty.call(schema.properties, key)
      const patterned = patternEntries.some(([pattern]) => new RegExp(pattern).test(key))
      if (!declared && !patterned) errors.push(...validateAgainstSchema(schema.additionalProperties, data[key], `${pointer}.${key}`))
    }
  }

  if (schema.pattern !== undefined && typeof data === 'string' && !new RegExp(schema.pattern).test(data)) {
    errors.push(`${describe(pointer)}: pattern が不正`)
  }
  if (schema.minLength !== undefined && typeof data === 'string' && data.length < schema.minLength) {
    errors.push(`${describe(pointer)}: minLength が不足`)
  }
  if (schema.minItems !== undefined && Array.isArray(data) && data.length < schema.minItems) {
    errors.push(`${describe(pointer)}: minItems が不足`)
  }
  if (schema.minProperties !== undefined && isObject(data) && Object.keys(data).length < schema.minProperties) {
    errors.push(`${describe(pointer)}: minProperties が不足`)
  }
  if (schema.uniqueItems === true && Array.isArray(data)) {
    const serialized = data.map((item) => JSON.stringify(item))
    if (new Set(serialized).size !== serialized.length) errors.push(`${describe(pointer)}: uniqueItems が不正`)
  }
  if (schema.items !== undefined && Array.isArray(data)) {
    for (let index = 0; index < data.length; index += 1) {
      errors.push(...validateAgainstSchema(schema.items, data[index], `${pointer}[${index}]`))
    }
  }

  return errors
}

function assertFamilyRegistry(family, definition) {
  if (definition.setup !== null && !KNOWN_SETUP_FAMILIES.includes(family)) {
    throw new ConfigError(`provider family ${family}: setup を持てるのは ${KNOWN_SETUP_FAMILIES.join(', ')} だけである`)
  }
  if (Object.keys(definition.featureAllowlist).length !== 0) {
    throw new ConfigError(`provider family ${family}: v1 の featureAllowlist は空でなければならない`)
  }
}

function assertFeatureKey(key) {
  const lowered = key.toLowerCase()
  for (const substring of SECRET_SUBSTRINGS) {
    if (lowered.includes(substring)) throw new ConfigError(`feature key ${key}: 秘密情報を示す語を含む`)
  }
}

function assertConfigEnvName(name) {
  if (RESERVED_ENV_NAMES.includes(name.toLowerCase())) throw new ConfigError(`config env ${name}: 予約名である`)
}

function candidateLists(config) {
  const lists = []
  for (const [tier, definition] of Object.entries(config.tiers)) {
    lists.push({ location: `tiers.${tier}`, environment: null, tier, candidates: definition.candidates })
  }
  for (const [environment, definition] of Object.entries(config.environments)) {
    for (const [tier, tierDefinition] of Object.entries(definition.tiers)) {
      lists.push({ location: `environments.${environment}.tiers.${tier}`, environment, tier, candidates: tierDefinition.candidates })
    }
  }
  return lists
}

function assertPathList(family, listName, values) {
  const paths = values.map((value) => {
    if (typeof value !== 'string' || value.length === 0 || path.posix.isAbsolute(value) || value.split('/').includes('..')) {
      throw new ConfigError(`provider family ${family}: ${listName} の path が不正`)
    }
    return value.split('/').filter((part) => part !== '.')
  })
  const seen = new Set()
  for (let index = 0; index < paths.length; index += 1) {
    const current = paths[index]
    const currentKey = current.join('/')
    if (seen.has(currentKey)) throw new ConfigError(`provider family ${family}: ${listName} の path が重複する`)
    seen.add(currentKey)
    for (let previous = 0; previous < index; previous += 1) {
      const other = paths[previous]
      const isParent = current.length < other.length && current.every((part, partIndex) => part === other[partIndex])
      const isChild = other.length < current.length && other.every((part, partIndex) => part === current[partIndex])
      if (isParent || isChild) throw new ConfigError(`provider family ${family}: ${listName} の path が親子で重なる`)
    }
  }
  return paths
}

function assertSetupPaths(family, setup) {
  const symlinks = assertPathList(family, 'symlinks', setup.symlinks)
  const preserved = assertPathList(family, 'preservedMutable', setup.preservedMutable)
  const all = [...symlinks, ...preserved]
  for (let index = 0; index < all.length; index += 1) {
    for (let previous = 0; previous < index; previous += 1) {
      const current = all[index]
      const other = all[previous]
      const isParent = current.length < other.length && current.every((part, partIndex) => part === other[partIndex])
      const isChild = other.length < current.length && other.every((part, partIndex) => part === current[partIndex])
      if (isParent || isChild || current.join('/') === other.join('/')) {
        throw new ConfigError(`provider family ${family}: setup path が symlinks と preservedMutable の間で重なる`)
      }
    }
  }
}

function assertSemantics(config) {
  if (!Object.prototype.hasOwnProperty.call(config.environments, config.defaults.environment)) {
    throw new ConfigError(`defaults.environment ${config.defaults.environment}: 未知の environment である`)
  }

  for (const list of candidateLists(config)) {
    for (const candidate of list.candidates) {
      if (!Object.prototype.hasOwnProperty.call(config.providers, candidate.provider)) {
        throw new ConfigError(`${list.location}: 未知の provider ${candidate.provider} である`)
      }
    }
  }

  for (const [environment, definition] of Object.entries(config.environments)) {
    for (const provider of definition.providers) {
      if (!Object.prototype.hasOwnProperty.call(config.providers, provider)) {
        throw new ConfigError(`environment ${environment}: 未知の provider ${provider} である`)
      }
    }
    for (const [tier, tierDefinition] of Object.entries(definition.tiers)) {
      for (const candidate of tierDefinition.candidates) {
        if (!definition.providers.includes(candidate.provider)) {
          throw new ConfigError(`environment ${environment}/${tier}: candidate provider が eligibility にない`)
        }
      }
    }
  }

  for (const list of candidateLists(config)) {
    const providers = new Set()
    for (const candidate of list.candidates) {
      if (providers.has(candidate.provider)) throw new ConfigError(`${list.location}: provider が同じ tier に重複する`)
      providers.add(candidate.provider)
    }
  }

  for (const role of Object.values(config.agentRoles)) {
    if (role.tier !== undefined && !TIERS.includes(role.tier)) throw new ConfigError('agentRoles: tier が不正である')
  }

  for (const list of candidateLists(config)) {
    for (const candidate of list.candidates) {
      const definition = config.providers[candidate.provider]
      for (const key of Object.keys(definition.featureAllowlist)) assertFeatureKey(key)
      for (const key of Object.keys(candidate.featureValues)) {
        assertFeatureKey(key)
        if (!Object.prototype.hasOwnProperty.call(definition.featureAllowlist, key)) {
          throw new ConfigError(`${list.location}: featureValues の key ${key} が allowlist にない`)
        }
        const expected = definition.featureAllowlist[key]
        const actual = candidate.featureValues[key]
        const valid = expected === 'boolean'
          ? typeof actual === 'boolean'
          : expected === 'string'
            ? typeof actual === 'string'
            : expected === 'integer'
              ? typeof actual === 'number' && Number.isInteger(actual) && Number.isFinite(actual)
              : false
        if (!valid) throw new ConfigError(`${list.location}: featureValues の scalar 型が allowlist と違う`)
      }
    }
  }

  const configEnvOwners = new Map()
  for (const [family, definition] of Object.entries(config.providers)) {
    const setup = definition.setup
    if (setup === null) continue
    const entries = Object.entries(setup.configDirectoryEnv)
    if (entries.length !== 1) throw new ConfigError(`provider family ${family}: configDirectoryEnv は一つだけ必要である`)
    for (const [name] of entries) {
      assertConfigEnvName(name)
      if (configEnvOwners.has(name)) throw new ConfigError(`config env ${name}: family 間で重複する`)
      configEnvOwners.set(name, family)
    }
    const stem = entries[0][1]
    if (setup.directoryPattern.primary !== `$XDG_CONFIG_HOME/${stem}` ||
        setup.directoryPattern.nonPrimary !== `$XDG_CONFIG_HOME/${stem}_<environment>`) {
      throw new ConfigError(`provider family ${family}: directoryPattern が config directory と一致しない`)
    }
    assertSetupPaths(family, setup)
  }

  for (const [family, definition] of Object.entries(config.providers)) assertFamilyRegistry(family, definition)

  const environments = Object.keys(config.environments)
  const firstEnvironment = config.defaults.environment
  const generatedIds = new Map()
  const physicalPaths = new Map()
  for (const environment of environments) {
    for (const family of config.environments[environment].providers) {
      const setup = config.providers[family].setup
      const providerId = environment === firstEnvironment ? family : `${family}-${environment}`
      const previousId = generatedIds.get(providerId)
      if (previousId && previousId !== `${family}/${environment}`) {
        throw new ConfigError(`generated provider id ${providerId}: provenance が衝突する`)
      }
      generatedIds.set(providerId, `${family}/${environment}`)
      if (setup === null) continue
      const stem = Object.values(setup.configDirectoryEnv)[0]
      const physicalPath = environment === firstEnvironment
        ? `$XDG_CONFIG_HOME/${stem}`
        : `$XDG_CONFIG_HOME/${stem}_${environment}`
      const previousPath = physicalPaths.get(physicalPath)
      if (previousPath && previousPath !== `${family}/${environment}`) {
        throw new ConfigError(`generated physical path ${physicalPath}: provenance が衝突する`)
      }
      physicalPaths.set(physicalPath, `${family}/${environment}`)
    }
  }

  for (const [family, definition] of Object.entries(config.providers)) {
    if (definition.setup === null) continue
    for (const environment of environments) {
      if (environment.startsWith(`${family}-`)) {
        throw new ConfigError(`generated provider id ${environment}: ${family} の provenance と衝突する`)
      }
    }
  }

  for (const rule of config.projectRouting.rules) {
    if (!Object.prototype.hasOwnProperty.call(config.environments, rule.environment)) {
      throw new ConfigError(`projectRouting rule: 未知の environment である`)
    }
    const fields = Object.keys(rule.match)
    if (fields.some((field) => !['remote', 'path'].includes(field))) {
      throw new ConfigError('projectRouting rule: match field が不正である')
    }
    if (typeof rule.match.remote === 'string') {
      const remoteParts = rule.match.remote.split('/').slice(1)
      if (remoteParts.some((part) => part === '.' || part === '..' || part.endsWith('.git'))) {
        throw new ConfigError('projectRouting rule: remote path が不正である')
      }
    }
  }
}

function parseAndSchema(rawText) {
  if (typeof rawText !== 'string') throw new ConfigError('input: 正本の raw text が必要である')
  let parsed
  try {
    parsed = JSON.parse(rawText)
  } catch {
    throw new ConfigError('input: JSON として parse できない')
  }
  const schema = JSON.parse(fs.readFileSync(SCHEMA_PATH, 'utf8'))
  const unsupported = Object.keys(schema).filter((key) => !SCHEMA_KEYWORDS.includes(key))
  if (unsupported.length > 0) throw new ConfigError('schema: 未対応 keyword がある')
  const errors = validateAgainstSchema(schema, parsed, '')
  if (errors.length > 0) throw new ConfigError(`schema: ${errors[0]}`)
  return parsed
}

function validateConfig(rawText) {
  const config = parseAndSchema(rawText)
  assertSemantics(config)
  return { config, warnings: [] }
}

module.exports = { ConfigError, KNOWN_SETUP_FAMILIES, validateConfig }
