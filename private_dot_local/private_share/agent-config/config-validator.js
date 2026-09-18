'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { DUTIES, COMPLEXITIES, SCHEMA_KEYWORDS } = require('./config-types.js')

class ConfigError extends Error {
  constructor(message) {
    super(message)
    this.name = 'ConfigError'
    this.exitCode = 2
  }
}

const SETUP_TABLE = {
  claude: {
    configDirectoryEnv: { CLAUDE_CONFIG_DIR: 'claude' },
    symlinks: ['agents', 'commands', 'skills', 'hooks', 'CLAUDE.md', 'settings.json'],
    preservedMutable: ['.claude.json'],
  },
  codex: {
    configDirectoryEnv: { CODEX_HOME: 'codex' },
    symlinks: ['agents', 'AGENTS.md', 'rules'],
    preservedMutable: ['config.toml'],
  },
}
const KNOWN_SETUP_FAMILIES = Object.keys(SETUP_TABLE)
// v1 で宣言してよい feature key と scalar 型を family ごとに固定する。
// 表にない family は空の allowlist だけを持てる。
const FEATURE_ALLOWLIST_TABLE = {
  claude: { fast_mode: 'boolean' },
  codex: { fast_mode: 'boolean' },
}
const SECRET_SUBSTRINGS = ['credential', 'token', 'key', 'password', 'secret', 'auth', 'session', 'cookie', 'history']
const RESERVED_ENV_NAMES = ['agent_env', 'chezmoi_agent_config_managed', 'paseo_managed', 'xdg_config_home', 'home']
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
  if (KNOWN_SETUP_FAMILIES.includes(family) && definition.setup === null) {
    throw new ConfigError(`provider family ${family}: setup table が必要である`)
  }
  if (definition.setup !== null && !KNOWN_SETUP_FAMILIES.includes(family)) {
    throw new ConfigError(`provider family ${family}: setup を持てるのは ${KNOWN_SETUP_FAMILIES.join(', ')} だけである`)
  }
  if (definition.setup !== null) {
    const expected = SETUP_TABLE[family]
    if (JSON.stringify(definition.setup.configDirectoryEnv) !== JSON.stringify(expected.configDirectoryEnv) ||
        JSON.stringify(definition.setup.symlinks) !== JSON.stringify(expected.symlinks) ||
        JSON.stringify(definition.setup.preservedMutable) !== JSON.stringify(expected.preservedMutable)) {
      throw new ConfigError(`provider family ${family}: setup table と一致しない`)
    }
  }
  const allowed = Object.prototype.hasOwnProperty.call(FEATURE_ALLOWLIST_TABLE, family)
    ? FEATURE_ALLOWLIST_TABLE[family]
    : {}
  for (const [key, scalar] of Object.entries(definition.featureAllowlist)) {
    assertFeatureKey(key)
    if (!Object.prototype.hasOwnProperty.call(allowed, key)) {
      throw new ConfigError(`provider family ${family}: featureAllowlist の key ${key} は v1 で許可されない`)
    }
    if (allowed[key] !== scalar) {
      throw new ConfigError(`provider family ${family}: featureAllowlist の ${key} は ${allowed[key]} でなければならない`)
    }
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
  for (const duty of DUTIES) {
    for (const complexity of COMPLEXITIES) {
      lists.push({
        location: `selection.${duty}.${complexity}`,
        environment: null,
        duty,
        complexity,
        candidates: config.selection[duty][complexity].candidates,
      })
    }
  }
  for (const [environment, definition] of Object.entries(config.environments)) {
    for (const [duty, byComplexity] of Object.entries(definition.selection)) {
      for (const [complexity, slot] of Object.entries(byComplexity)) {
        lists.push({
          location: `environments.${environment}.selection.${duty}.${complexity}`,
          environment,
          duty,
          complexity,
          candidates: slot.candidates,
        })
      }
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

  for (const [family, definition] of Object.entries(config.providers)) {
    if (!Array.isArray(definition.backends) || definition.backends.length === 0) {
      throw new ConfigError(`providers.${family}: backends が空である`)
    }
    if (new Set(definition.backends).size !== definition.backends.length) {
      throw new ConfigError(`providers.${family}: backends が重複する`)
    }
  }

  for (const [environment, definition] of Object.entries(config.environments)) {
    for (const provider of definition.providers) {
      if (!Object.prototype.hasOwnProperty.call(config.providers, provider)) {
        throw new ConfigError(`environment ${environment}: 未知の provider ${provider} である`)
      }
    }
    for (const [duty, byComplexity] of Object.entries(definition.selection)) {
      for (const [complexity, slot] of Object.entries(byComplexity)) {
        for (const candidate of slot.candidates) {
          if (!definition.providers.includes(candidate.provider)) {
            throw new ConfigError(`environment ${environment}/${duty}/${complexity}: candidate provider が eligibility にない`)
          }
        }
      }
    }
  }

  for (const list of candidateLists(config)) {
    const providers = new Set()
    for (const candidate of list.candidates) {
      if (providers.has(candidate.provider)) throw new ConfigError(`${list.location}: provider が同じ枠に重複する`)
      providers.add(candidate.provider)
    }
  }

  for (const role of Object.values(config.agentRoles)) {
    if (role.duty !== undefined && !DUTIES.includes(role.duty)) throw new ConfigError('agentRoles: duty が不正である')
  }

  for (const list of candidateLists(config)) {
    for (const candidate of list.candidates) {
      const definition = config.providers[candidate.provider]
      for (const key of Object.keys(definition.featureAllowlist)) assertFeatureKey(key)
      for (const key of Object.keys(candidate.features)) {
        assertFeatureKey(key)
        if (!Object.prototype.hasOwnProperty.call(definition.featureAllowlist, key)) {
          throw new ConfigError(`${list.location}: features の key ${key} が allowlist にない`)
        }
        const expected = definition.featureAllowlist[key]
        const actual = candidate.features[key]
        const valid = expected === 'boolean'
          ? typeof actual === 'boolean'
          : expected === 'string'
            ? typeof actual === 'string'
            : expected === 'integer'
              ? typeof actual === 'number' && Number.isInteger(actual) && Number.isFinite(actual)
              : false
        if (!valid) throw new ConfigError(`${list.location}: features の scalar 型が allowlist と違う`)
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

  const environments = Object.keys(config.environments)
  const firstEnvironment = config.defaults.environment
  const generatedIds = new Map()
  const physicalPaths = new Map()
  const addGeneratedId = (providerId, provenance) => {
    const previousId = generatedIds.get(providerId)
    if (previousId && previousId !== provenance) {
      throw new ConfigError(`generated provider id ${providerId}: provenance が衝突する`)
    }
    generatedIds.set(providerId, provenance)
  }
  const addPhysicalPath = (physicalPath, provenance) => {
    const previousPath = physicalPaths.get(physicalPath)
    if (previousPath && previousPath !== provenance) {
      throw new ConfigError(`generated physical path ${physicalPath}: provenance が衝突する`)
    }
    physicalPaths.set(physicalPath, provenance)
  }

  for (const [family, definition] of Object.entries(config.providers)) {
    const provenance = `${family}/${firstEnvironment}`
    addGeneratedId(family, provenance)
    if (definition.setup !== null) {
      const stem = Object.values(definition.setup.configDirectoryEnv)[0]
      addPhysicalPath(`$XDG_CONFIG_HOME/${stem}`, provenance)
    }
  }

  for (const environment of environments) {
    if (environment === firstEnvironment) continue
    for (const family of config.environments[environment].providers) {
      const provenance = `${family}/${environment}`
      addGeneratedId(`${family}-${environment}`, provenance)
      const setup = config.providers[family].setup
      if (setup !== null) {
        const stem = Object.values(setup.configDirectoryEnv)[0]
        addPhysicalPath(`$XDG_CONFIG_HOME/${stem}_${environment}`, provenance)
      }
    }
  }

  for (const [family, definition] of Object.entries(config.providers)) assertFamilyRegistry(family, definition)

  for (const rule of config.projectRouting.rules) {
    if (!Object.prototype.hasOwnProperty.call(config.environments, rule.environment)) {
      throw new ConfigError(`projectRouting rule: 未知の environment である`)
    }
    const fields = Object.keys(rule.match)
    if (fields.length === 0 || fields.some((field) => !['remote', 'path'].includes(field))) {
      throw new ConfigError('projectRouting rule: match field が不正である')
    }
    if (typeof rule.match.path === 'string') {
      if (!path.isAbsolute(rule.match.path)) throw new ConfigError('projectRouting rule: path は絶対 path である')
      let canonicalPath
      try {
        if (!fs.statSync(rule.match.path).isDirectory()) throw new Error('not a directory')
        canonicalPath = fs.realpathSync.native(rule.match.path)
      } catch {
        throw new ConfigError('projectRouting rule: path が存在しない')
      }
      if (canonicalPath !== rule.match.path) throw new ConfigError('projectRouting rule: path は canonical path である')
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
