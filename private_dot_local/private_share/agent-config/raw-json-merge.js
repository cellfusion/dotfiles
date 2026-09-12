'use strict'

const { ConfigError } = require('./config-validator.js')

const MANAGED_PROFILE_PREFIX = 'agent_profile_managed_'
const MANAGED_MARKER = '1'

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function parseRawJson(raw) {
  if (typeof raw !== 'string') throw new ConfigError('target: raw JSON text が必要である')
  try {
    JSON.parse(raw)
  } catch {
    throw new ConfigError('target: JSON として parse できない')
  }
  return new JsonParser(raw).parse()
}

class JsonParser {
  constructor(raw) {
    this.raw = raw
    this.index = 0
  }

  parse() {
    const node = this.parseValue()
    this.skipWhitespace()
    if (this.index !== this.raw.length) throw new ConfigError('target: JSON の末尾が不正である')
    return node
  }

  skipWhitespace() {
    while (this.index < this.raw.length && /\s/.test(this.raw[this.index])) this.index += 1
  }

  parseValue() {
    this.skipWhitespace()
    const start = this.index
    const character = this.raw[this.index]
    if (character === '{') return this.parseObject(start)
    if (character === '[') return this.parseArray(start)
    if (character === '"') return this.parseString(start)
    if (character === '-' || /[0-9]/.test(character || '')) return this.parseNumber(start)
    for (const literal of ['true', 'false', 'null']) {
      if (this.raw.startsWith(literal, this.index)) {
        this.index += literal.length
        return { type: literal === 'null' ? 'null' : 'literal', value: JSON.parse(literal), start, end: this.index }
      }
    }
    throw new ConfigError('target: JSON value が不正である')
  }

  parseString(start) {
    this.index += 1
    let escaped = false
    while (this.index < this.raw.length) {
      const character = this.raw[this.index]
      if (escaped) {
        escaped = false
        this.index += 1
        continue
      }
      if (character === '\\') {
        escaped = true
        this.index += 1
        continue
      }
      if (character === '"') {
        this.index += 1
        const text = this.raw.slice(start, this.index)
        return { type: 'string', value: JSON.parse(text), start, end: this.index }
      }
      this.index += 1
    }
    throw new ConfigError('target: JSON string が閉じていない')
  }

  parseNumber(start) {
    const rest = this.raw.slice(this.index)
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(rest)
    if (!match) throw new ConfigError('target: JSON number が不正である')
    this.index += match[0].length
    return { type: 'number', value: JSON.parse(match[0]), start, end: this.index }
  }

  parseObject(start) {
    this.index += 1
    const entries = []
    const values = Object.create(null)
    this.skipWhitespace()
    if (this.raw[this.index] === '}') {
      this.index += 1
      return { type: 'object', value: values, entries, start, end: this.index }
    }
    while (true) {
      this.skipWhitespace()
      const keyStart = this.index
      const keyNode = this.parseString(keyStart)
      if (entries.some((entry) => entry.key === keyNode.value)) {
        throw new ConfigError(`target: object key ${keyNode.value} が重複する`)
      }
      this.skipWhitespace()
      if (this.raw[this.index] !== ':') throw new ConfigError('target: object の colon がない')
      this.index += 1
      const value = this.parseValue()
      entries.push({ key: keyNode.value, keyStart, keyEnd: keyNode.end, value })
      Object.defineProperty(values, keyNode.value, {
        configurable: true,
        enumerable: true,
        value: value.value,
        writable: true,
      })
      this.skipWhitespace()
      if (this.raw[this.index] === '}') {
        this.index += 1
        return { type: 'object', value: values, entries, start, end: this.index }
      }
      if (this.raw[this.index] !== ',') throw new ConfigError('target: object の comma がない')
      this.index += 1
      this.skipWhitespace()
    }
  }

  parseArray(start) {
    this.index += 1
    const items = []
    this.skipWhitespace()
    if (this.raw[this.index] === ']') {
      this.index += 1
      return { type: 'array', value: items, items, start, end: this.index }
    }
    while (true) {
      const item = this.parseValue()
      items.push(item)
      this.skipWhitespace()
      if (this.raw[this.index] === ']') {
        this.index += 1
        return { type: 'array', value: items.map((entry) => entry.value), items, start, end: this.index }
      }
      if (this.raw[this.index] !== ',') throw new ConfigError('target: array の comma がない')
      this.index += 1
      this.skipWhitespace()
    }
  }
}

function objectEntries(node, label) {
  if (!node || node.type !== 'object') throw new ConfigError(`${label}: object が必要である`)
  return new Map(node.entries.map((entry) => [entry.key, entry]))
}

function addObjectInsertion(insertions, node, key, value) {
  if (!insertions.has(node)) insertions.set(node, [])
  insertions.get(node).push([key, value])
}

function stringify(value) {
  const result = JSON.stringify(value)
  if (result === undefined) throw new ConfigError('target: JSON value を生成できない')
  return result
}

function replaceObjectFields(node, fields, edits, insertions) {
  const entries = objectEntries(node, 'target object')
  const missing = []
  for (const [key, value] of Object.entries(fields)) {
    const entry = entries.get(key)
    if (entry) edits.push({ start: entry.value.start, end: entry.value.end, text: stringify(value) })
    else missing.push([key, value])
  }
  for (const [key, value] of missing) addObjectInsertion(insertions, node, key, value)
}

function deleteObjectField(node, key, edits) {
  const entries = node.entries
  const index = entries.findIndex((entry) => entry.key === key)
  if (index < 0) return
  const entry = entries[index]
  if (entries.length === 1) {
    edits.push({ start: entry.keyStart, end: entry.value.end, text: '' })
  } else if (index < entries.length - 1) {
    edits.push({ start: entry.keyStart, end: entries[index + 1].keyStart, text: '' })
  } else {
    edits.push({ start: entries[index - 1].value.end, end: entry.value.end, text: '' })
  }
}

function addInsertions(insertions, edits) {
  for (const [node, additions] of insertions.entries()) {
    const content = additions.map(([key, value]) => `${stringify(key)}:${stringify(value)}`).join(',')
    const prefix = node.entries.length === 0 ? '' : ','
    edits.push({ start: node.end - 1, end: node.end - 1, text: `${prefix}${content}` })
  }
}

function applyEdits(raw, edits) {
  const sorted = [...edits].sort((left, right) => {
    if (left.start !== right.start) return right.start - left.start
    return right.end - left.end
  })
  let output = raw
  let lowerBound = raw.length + 1
  for (const edit of sorted) {
    if (edit.start < 0 || edit.end < edit.start || edit.end > raw.length || edit.end > lowerBound) {
      throw new ConfigError('target: overlapping JSON edit がある')
    }
    output = output.slice(0, edit.start) + edit.text + output.slice(edit.end)
    lowerBound = edit.start
  }
  return output
}

function assertMaterialized(materialized) {
  if (!isObject(materialized) || !Array.isArray(materialized.profiles) || !isObject(materialized.providers) ||
      !Array.isArray(materialized.warnings) || !materialized.warnings.every((warning) => typeof warning === 'string')) {
    throw new ConfigError('materialized Paseo: shape が不正である')
  }
  const profileIds = new Set()
  for (const profile of materialized.profiles) {
    if (!isObject(profile) || typeof profile.id !== 'string' || profile.id.length === 0 ||
        typeof profile.name !== 'string' || profile.name.length === 0 || typeof profile.provider !== 'string' ||
        typeof profile.model !== 'string' || profile.modeId !== 'auto' || typeof profile.thinkingOptionId !== 'string' ||
        !isObject(profile.featureValues)) throw new ConfigError('materialized profile: shape が不正である')
    if (profileIds.has(profile.id)) throw new ConfigError(`materialized profile ${profile.id}: 重複する`)
    profileIds.add(profile.id)
  }
  for (const [providerId, provider] of Object.entries(materialized.providers)) {
    if (!isObject(provider) || typeof provider.label !== 'string' || !isObject(provider.env)) {
      throw new ConfigError(`materialized provider ${providerId}: shape が不正である`)
    }
    if (provider.extends !== undefined && typeof provider.extends !== 'string') {
      throw new ConfigError(`materialized provider ${providerId}: extends が不正である`)
    }
    for (const [key, value] of Object.entries(provider.env)) {
      if (typeof value !== 'string') throw new ConfigError(`materialized provider ${providerId}: env が不正である`)
      if (!/^[A-Z][A-Z0-9_]*$/.test(key)) throw new ConfigError(`materialized provider ${providerId}: env key が不正である`)
    }
  }
}

function isManagedProfileId(id) {
  return typeof id === 'string' && id.startsWith(MANAGED_PROFILE_PREFIX)
}

function providerMarker(provider) {
  if (!isObject(provider) || !isObject(provider.env)) return undefined
  return provider.env.CHEZMOI_AGENT_CONFIG_MANAGED
}

function hasExpectedLegacyProvider(provider, patch) {
  if (!isObject(provider)) return false
  if (patch.extends !== undefined) {
    return Object.prototype.hasOwnProperty.call(provider, 'extends') &&
      provider.extends === patch.extends &&
      isObject(provider.env) &&
      provider.env.AGENT_ENV === patch.env.AGENT_ENV
  }
  if (Object.prototype.hasOwnProperty.call(provider, 'extends')) {
    return false
  }
  if (isObject(provider.env) && Object.prototype.hasOwnProperty.call(provider.env, 'AGENT_ENV')) {
    if (provider.env.AGENT_ENV !== patch.env.AGENT_ENV) return false
  }
  return true
}

function mergeProvider(raw, node, patch, edits, insertions) {
  const entries = objectEntries(node, 'provider')
  const envEntry = entries.get('env')
  let envNode
  if (envEntry) {
    if (envEntry.value.type !== 'object') throw new ConfigError('target provider: env が object でない')
    envNode = envEntry.value
  } else {
    envNode = null
  }

  if (patch.extends === undefined) {
    deleteObjectField(node, 'extends', edits)
  } else {
    replaceObjectFields(node, { extends: patch.extends }, edits, insertions)
  }
  replaceObjectFields(node, { label: patch.label }, edits, insertions)
  if (envNode) replaceObjectFields(envNode, patch.env, edits, insertions)
  else addObjectInsertion(insertions, node, 'env', patch.env)
}

function mergeManagedPaseo(raw, materialized) {
  assertMaterialized(materialized)
  const root = parseRawJson(raw)
  if (root.type !== 'object') throw new ConfigError('target: root は object である必要がある')
  const rootEntries = objectEntries(root, 'target root')
  const daemonEntry = rootEntries.get('daemon')
  const agentsEntry = rootEntries.get('agents')
  if (!daemonEntry || !agentsEntry) throw new ConfigError('target: daemon と agents の親が必要である')
  if (daemonEntry.value.type !== 'object' || agentsEntry.value.type !== 'object') {
    throw new ConfigError('target: daemon と agents は object である必要がある')
  }
  const daemonEntries = objectEntries(daemonEntry.value, 'target daemon')
  const agentsEntries = objectEntries(agentsEntry.value, 'target agents')
  const profilesEntry = daemonEntries.get('agentProfiles')
  const providersEntry = agentsEntries.get('providers')
  if (!profilesEntry || !providersEntry) throw new ConfigError('target: agentProfiles と providers の親が必要である')
  if (profilesEntry.value.type !== 'array' || providersEntry.value.type !== 'object') {
    throw new ConfigError('target: agentProfiles は array、providers は object である必要がある')
  }

  const materializedProfileById = new Map(materialized.profiles.map((profile) => [profile.id, profile]))
  const materializedProviderById = new Map(Object.entries(materialized.providers))
  const edits = []
  const insertions = new Map()
  const warnings = [...materialized.warnings]
  const existingProfileIds = new Set()
  const existingProviderIds = new Set()

  for (const item of profilesEntry.value.items) {
    if (item.type !== 'object') {
      throw new ConfigError('target: agentProfiles の record が object でない')
    }
    const id = item.value.id
    const name = item.value.name
    if (isManagedProfileId(id)) {
      if (existingProfileIds.has(id)) throw new ConfigError(`target profile ${id}: ID が重複する`)
      existingProfileIds.add(id)
      if (materializedProfileById.has(id)) {
        edits.push({ start: item.start, end: item.end, text: stringify(materializedProfileById.get(id)) })
      } else {
        warnings.push(`stale managed profile: ${id}; remove manually`)
      }
    }
  }

  for (const profile of materialized.profiles) {
    for (const item of profilesEntry.value.items) {
      if (item.type !== 'object' || isManagedProfileId(item.value.id)) continue
      if (item.value.name === profile.name) {
        throw new ConfigError(`target profile name ${profile.name}: unmanaged profile と衝突する`)
      }
    }
  }

  const newProfiles = materialized.profiles.filter((profile) => !existingProfileIds.has(profile.id))
  if (newProfiles.length > 0) {
    const content = newProfiles.map((profile) => stringify(profile)).join(',')
    const prefix = profilesEntry.value.items.length === 0 ? '' : ','
    edits.push({ start: profilesEntry.value.end - 1, end: profilesEntry.value.end - 1, text: `${prefix}${content}` })
  }

  for (const entry of providersEntry.value.entries) {
    if (entry.value.type !== 'object') throw new ConfigError(`target provider ${entry.key}: record が object でない`)
    existingProviderIds.add(entry.key)
    const marker = providerMarker(entry.value.value)
    if (marker === MANAGED_MARKER) {
      if (!materializedProviderById.has(entry.key)) {
        warnings.push(`stale managed provider: ${entry.key}; remove manually`)
      } else {
        mergeProvider(raw, entry.value, materializedProviderById.get(entry.key), edits, insertions)
      }
      continue
    }
    if (marker !== undefined) throw new ConfigError(`target provider ${entry.key}: managed marker が不正である`)
    if (!materializedProviderById.has(entry.key)) continue
    if (!hasExpectedLegacyProvider(entry.value.value, materializedProviderById.get(entry.key))) {
      if (materializedProviderById.get(entry.key).extends !== undefined) {
        warnings.push(`legacy provider preserved: ${entry.key}; remove manually`)
        continue
      }
      throw new ConfigError(`target provider ${entry.key}: ownership が衝突する`)
    }
    mergeProvider(raw, entry.value, materializedProviderById.get(entry.key), edits, insertions)
  }

  const newProviders = Object.entries(materialized.providers).filter(([id]) => !existingProviderIds.has(id))
  if (newProviders.length > 0) {
    const content = newProviders.map(([id, provider]) => `${stringify(id)}:${stringify(provider)}`).join(',')
    const prefix = providersEntry.value.entries.length === 0 ? '' : ','
    edits.push({ start: providersEntry.value.end - 1, end: providersEntry.value.end - 1, text: `${prefix}${content}` })
  }

  addInsertions(insertions, edits)
  const merged = applyEdits(raw, edits)
  return { raw: merged, changed: merged !== raw, warnings }
}

module.exports = { mergeManagedPaseo }
