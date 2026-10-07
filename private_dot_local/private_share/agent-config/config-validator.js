'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

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
    directoryPattern: {
      primary: '$XDG_CONFIG_HOME/claude',
      nonPrimary: '$XDG_CONFIG_HOME/claude_<environment>',
    },
    symlinks: ['agents', 'commands', 'skills', 'hooks', 'CLAUDE.md', 'settings.json'],
    preservedMutable: ['.claude.json'],
  },
  codex: {
    configDirectoryEnv: { CODEX_HOME: 'codex' },
    directoryPattern: {
      primary: '$XDG_CONFIG_HOME/codex',
      nonPrimary: '$XDG_CONFIG_HOME/codex_<environment>',
    },
    symlinks: ['agents', 'AGENTS.md', 'rules'],
    preservedMutable: ['config.toml'],
  },
}
const KNOWN_SETUP_FAMILIES = Object.keys(SETUP_TABLE)
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
        JSON.stringify(definition.setup.directoryPattern) !== JSON.stringify(expected.directoryPattern) ||
        JSON.stringify(definition.setup.symlinks) !== JSON.stringify(expected.symlinks) ||
        JSON.stringify(definition.setup.preservedMutable) !== JSON.stringify(expected.preservedMutable)) {
      throw new ConfigError(`provider family ${family}: setup table と一致しない`)
    }
  }
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

function gitCommonDirectory(directory) {
  const result = spawnSync(
    'git',
    ['-C', directory, 'rev-parse', '--path-format=absolute', '--git-common-dir'],
    { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' } },
  )
  if (result.error) {
    throw new ConfigError(`projectRouting rule: Git を起動できない (${result.error.code || 'spawn error'})`)
  }
  if (result.status !== 0) {
    const detail = (result.stderr || '').trim().replace(/\s+/g, ' ')
    throw new ConfigError(`projectRouting rule: Git common directory を取得できない (${detail || `exit ${result.status}`})`)
  }
  const output = (result.stdout || '').trim()
  if (!path.isAbsolute(output)) {
    throw new ConfigError('projectRouting rule: Git common directory が絶対 path ではない')
  }
  try {
    return fs.realpathSync.native(output)
  } catch (error) {
    throw new ConfigError(`projectRouting rule: Git common directory を canonicalize できない (${error.code || 'I/O'})`)
  }
}

function assertSemantics(config) {
  if (!Object.prototype.hasOwnProperty.call(config.environments, config.defaults.environment)) {
    throw new ConfigError(`defaults.environment ${config.defaults.environment}: 未知の environment である`)
  }

  for (const [family, definition] of Object.entries(config.providers)) assertFamilyRegistry(family, definition)
  for (const [environment, definition] of Object.entries(config.environments)) {
    for (const provider of definition.providers) {
      if (!Object.prototype.hasOwnProperty.call(config.providers, provider)) {
        throw new ConfigError(`environment ${environment}: 未知の provider ${provider} である`)
      }
    }
  }

  const physicalPaths = new Set()
  for (const [family, definition] of Object.entries(config.providers)) {
    assertSetupPaths(family, definition.setup)
    for (const [environment, eligible] of Object.entries(config.environments)) {
      if (!eligible.providers.includes(family)) continue
      const pattern = environment === config.defaults.environment
        ? definition.setup.directoryPattern.primary
        : definition.setup.directoryPattern.nonPrimary.replace('<environment>', environment)
      if (physicalPaths.has(pattern)) throw new ConfigError(`generated physical path ${pattern}: provenance が衝突する`)
      physicalPaths.add(pattern)
    }
  }

  for (const rule of config.projectRouting.rules) {
    if (!Object.prototype.hasOwnProperty.call(config.environments, rule.environment)) {
      throw new ConfigError(`projectRouting rule: 未知の environment である`)
    }
    const matchFields = Object.keys(rule.match)
    const hasInvalidMatchField = matchFields.some(
      (field) => !['remote', 'remoteNamespace', 'path', 'gitRepository'].includes(field),
    )
    if (matchFields.length === 0 || hasInvalidMatchField) {
      throw new ConfigError('projectRouting rule: match field が不正である')
    }
    for (const field of ['path', 'gitRepository']) {
      if (typeof rule.match[field] !== 'string') continue
      const rulePath = rule.match[field]
      if (!path.isAbsolute(rulePath)) throw new ConfigError(`projectRouting rule: ${field} は絶対 path である`)
      let canonicalPath
      try {
        if (!fs.statSync(rulePath).isDirectory()) throw new Error('not a directory')
        canonicalPath = fs.realpathSync.native(rulePath)
      } catch {
        throw new ConfigError(`projectRouting rule: ${field} が存在しない`)
      }
      if (canonicalPath !== rulePath) throw new ConfigError(`projectRouting rule: ${field} は canonical path である`)
      if (field === 'gitRepository') gitCommonDirectory(rulePath)
    }
    for (const field of ['remote', 'remoteNamespace']) {
      if (typeof rule.match[field] !== 'string') continue
      const remoteParts = rule.match[field].split('/').slice(1)
      if (remoteParts.some((part) => part === '.' || part === '..' || part.endsWith('.git'))) {
        throw new ConfigError(`projectRouting rule: ${field} path が不正である`)
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
