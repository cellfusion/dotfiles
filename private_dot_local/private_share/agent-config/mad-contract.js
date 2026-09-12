'use strict'

const fs = require('node:fs')
const path = require('node:path')

const { validateConfig } = require('./config-validator.js')
const { resolveExport } = require('./resolver.js')
const {
  assertAvailabilitySnapshot,
  enumerateMaterializedProviderIds,
} = require('./paseo-exporter.js')

const TIERS = ['deep', 'think', 'work', 'light']
const SCALAR_TYPES = ['boolean', 'string', 'integer']
const MAD_LAUNCH_KEYS = [
  'version', 'type', 'status', 'profileName', 'environment', 'tier',
  'provider', 'model', 'modeId', 'thinkingOptionId', 'featureValues', 'warnings',
]
const MAD_REQUEST_KEYS = ['title', 'workspaceId', 'initialPrompt', 'notifyOnFinish', 'provider', 'settings']
const MAD_SETTINGS_KEYS = ['modeId', 'thinkingOptionId', 'features']
const SNAPSHOT_KEYS = ['version', 'type', 'providers', 'models']

class MadContractError extends Error {
  constructor(message, code = 'invalid_mad_create_request') {
    super(message)
    this.name = 'MadContractError'
    this.exitCode = 2
    this.code = code
  }
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function fail(code, message) {
  throw new MadContractError(message, code)
}

function exactKeys(value, expected, code, label) {
  if (!isObject(value)) fail(code, `${label}: object が必要である`)
  const actual = Object.keys(value).sort()
  const wanted = [...expected].sort()
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    fail(code, `${label}: key set が不正である`)
  }
}

function nonEmptyString(value, code, label) {
  if (typeof value !== 'string' || value.length === 0) fail(code, `${label}: 非空 string が必要である`)
}

function safeIdentifier(value, code, label) {
  nonEmptyString(value, code, label)
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)) fail(code, `${label}: identifier が不正である`)
}

function absolutePath(value, code, label) {
  if (typeof value !== 'string' || !path.isAbsolute(value)) fail(code, `${label}: 絶対 path が必要である`)
  return value
}

function scalarType(value) {
  if (typeof value === 'boolean') return 'boolean'
  if (typeof value === 'string') return 'string'
  if (typeof value === 'number' && Number.isInteger(value) && Number.isFinite(value)) return 'integer'
  return null
}

function assertFeatureAllowlist(featureAllowlist, code) {
  if (!isObject(featureAllowlist)) fail(code, 'featureAllowlist: object が必要である')
  for (const [key, scalar] of Object.entries(featureAllowlist)) {
    nonEmptyString(key, code, 'featureAllowlist key')
    if (!SCALAR_TYPES.includes(scalar)) fail(code, 'featureAllowlist: scalar type が不正である')
  }
  return featureAllowlist
}

function assertFeatureValues(value, featureAllowlist, code, label) {
  assertFeatureAllowlist(featureAllowlist, code)
  if (!isObject(value)) fail(code, `${label}: object が必要である`)
  for (const [key, actual] of Object.entries(value)) {
    if (!Object.prototype.hasOwnProperty.call(featureAllowlist, key)) {
      fail(code, `${label}: allowlist にない key がある`)
    }
    const expected = featureAllowlist[key]
    const actualType = scalarType(actual)
    if (actualType !== expected) fail(code, `${label}: scalar type が不正である`)
  }
  return value
}

function assertWarnings(value, code, label) {
  if (!Array.isArray(value) || !value.every((warning) => typeof warning === 'string')) {
    fail(code, `${label}: string 配列が必要である`)
  }
  if (value.some((warning) => warning.includes('://'))) fail(code, `${label}: URL が許可されない`)
  return value
}

function assertMadLaunchSpecV1(value, featureAllowlist) {
  const code = 'invalid_mad_launch_spec'
  exactKeys(value, MAD_LAUNCH_KEYS, code, 'mad launch')
  if (value.version !== 1 || value.type !== 'mad-launch-spec' || value.status !== 'ok') {
    fail(code, 'mad launch: success discriminator が不正である')
  }
  safeIdentifier(value.profileName, code, 'mad launch profileName')
  safeIdentifier(value.environment, code, 'mad launch environment')
  if (!TIERS.includes(value.tier)) fail(code, 'mad launch tier が不正である')
  safeIdentifier(value.provider, code, 'mad launch provider')
  nonEmptyString(value.model, code, 'mad launch model')
  if (value.modeId !== 'auto') fail(code, 'mad launch modeId は auto でなければならない')
  nonEmptyString(value.thinkingOptionId, code, 'mad launch thinkingOptionId')
  assertFeatureValues(value.featureValues, featureAllowlist, code, 'mad launch featureValues')
  assertWarnings(value.warnings, code, 'mad launch warnings')
  return value
}

function assertMadCreateRequestV1(value, featureAllowlist) {
  const code = 'invalid_mad_create_request'
  exactKeys(value, MAD_REQUEST_KEYS, code, 'mad create request')
  nonEmptyString(value.title, code, 'mad create request title')
  nonEmptyString(value.workspaceId, code, 'mad create request workspaceId')
  nonEmptyString(value.initialPrompt, code, 'mad create request initialPrompt')
  nonEmptyString(value.provider, code, 'mad create request provider')
  if (typeof value.notifyOnFinish !== 'boolean') fail(code, 'mad create request notifyOnFinish が不正である')
  exactKeys(value.settings, MAD_SETTINGS_KEYS, code, 'mad create request settings')
  if (value.settings.modeId !== 'auto') fail(code, 'mad create request modeId は auto でなければならない')
  nonEmptyString(value.settings.thinkingOptionId, code, 'mad create request thinkingOptionId')
  assertFeatureValues(value.settings.features, featureAllowlist, code, 'mad create request features')
  return value
}

function assertCreateContext(value) {
  const code = 'invalid_mad_create_request'
  exactKeys(value, ['title', 'workspaceId', 'initialPrompt', 'notifyOnFinish'], code, 'mad create context')
  nonEmptyString(value.title, code, 'mad create context title')
  nonEmptyString(value.workspaceId, code, 'mad create context workspaceId')
  nonEmptyString(value.initialPrompt, code, 'mad create context initialPrompt')
  if (typeof value.notifyOnFinish !== 'boolean') fail(code, 'mad create context notifyOnFinish が不正である')
  return value
}

function buildMadCreateRequestV1(launchValue, featureAllowlist, context) {
  const launch = assertMadLaunchSpecV1(launchValue, featureAllowlist)
  assertCreateContext(context)
  const request = {
    title: context.title,
    workspaceId: context.workspaceId,
    initialPrompt: context.initialPrompt,
    notifyOnFinish: context.notifyOnFinish,
    provider: `${launch.provider}/${launch.model}`,
    settings: {
      modeId: 'auto',
      thinkingOptionId: launch.thinkingOptionId,
      features: { ...launch.featureValues },
    },
  }
  return assertMadCreateRequestV1(request, featureAllowlist)
}

function lstatRegularFile(filePath, code, label) {
  absolutePath(filePath, code, label)
  let stats
  try {
    stats = fs.lstatSync(filePath)
  } catch {
    fail(code, `${label}: regular file が必要である`)
  }
  if (!stats.isFile() || stats.isSymbolicLink()) fail(code, `${label}: regular file が必要である`)
  return stats
}

function readJson(filePath, code, label) {
  lstatRegularFile(filePath, code, label)
  let raw
  try {
    raw = fs.readFileSync(filePath, 'utf8')
  } catch {
    fail(code, `${label}: 読み込めない`)
  }
  try {
    return JSON.parse(raw)
  } catch {
    fail(code, `${label}: JSON が不正である`)
  }
}

function fsyncDirectory(directory) {
  try {
    const descriptor = fs.openSync(directory, 'r')
    try { fs.fsyncSync(descriptor) } finally { fs.closeSync(descriptor) }
  } catch {
    // Directory fsync is unavailable on some supported filesystems.
  }
}

function writeAtomic0600(filePath, raw, code, label) {
  absolutePath(filePath, code, label)
  const directory = path.dirname(filePath)
  const temporaryPath = `${filePath}.tmp`
  let descriptor
  let created = false
  try {
    descriptor = fs.openSync(temporaryPath, 'wx', 0o600)
    created = true
    fs.writeFileSync(descriptor, raw, 'utf8')
    fs.fsyncSync(descriptor)
    fs.closeSync(descriptor)
    descriptor = undefined
    fs.renameSync(temporaryPath, filePath)
    created = false
    fs.chmodSync(filePath, 0o600)
    fsyncDirectory(directory)
  } catch (error) {
    if (descriptor !== undefined) {
      try { fs.closeSync(descriptor) } catch {}
    }
    if (created) {
      try { fs.unlinkSync(temporaryPath) } catch {}
    }
    fail(code, `${label}: atomic write に失敗した (${error && error.code ? error.code : 'I/O'})`)
  }
  return filePath
}

function writeMadCreateRequest0600(request, requestPath) {
  const code = 'invalid_mad_create_request'
  absolutePath(requestPath, code, 'mad create request path')
  if (!isObject(request)) fail(code, 'mad create request: 検証済み object が必要である')
  // The writer has no allowlist argument by design. It still checks the complete
  // structural contract and scalar values; callers must pass the result of the
  // allowlist-aware assertion or builder.
  const inferredAllowlist = {}
  if (isObject(request.settings) && isObject(request.settings.features)) {
    for (const [key, value] of Object.entries(request.settings.features)) {
      const type = scalarType(value)
      if (type === null) fail(code, 'mad create request: feature scalar が不正である')
      inferredAllowlist[key] = type
    }
  }
  assertMadCreateRequestV1(request, inferredAllowlist)
  const canonicalRequest = {
    title: request.title,
    workspaceId: request.workspaceId,
    initialPrompt: request.initialPrompt,
    notifyOnFinish: request.notifyOnFinish,
    provider: request.provider,
    settings: {
      modeId: request.settings.modeId,
      thinkingOptionId: request.settings.thinkingOptionId,
      features: { ...request.settings.features },
    },
  }
  return writeAtomic0600(requestPath, JSON.stringify(canonicalRequest), code, 'mad create request')
}

function assertEnumeration(value) {
  const code = 'invalid_mad_snapshot'
  exactKeys(value, ['version', 'type', 'providerIds'], code, 'provider enumeration')
  if (value.version !== 1 || value.type !== 'paseo-provider-enumeration') {
    fail(code, 'provider enumeration: discriminator が不正である')
  }
  if (!Array.isArray(value.providerIds) || value.providerIds.length === 0) {
    fail(code, 'provider enumeration: providerIds が不正である')
  }
  for (const providerId of value.providerIds) safeIdentifier(providerId, code, 'provider enumeration providerId')
  if (new Set(value.providerIds).size !== value.providerIds.length) {
    fail(code, 'provider enumeration: providerIds が重複する')
  }
  return value
}

function assertProviderRecord(value, code, label) {
  exactKeys(value, ['id', 'available', 'modeIds'], code, label)
  safeIdentifier(value.id, code, `${label} id`)
  if (typeof value.available !== 'boolean') fail(code, `${label}: available が不正である`)
  if (!Array.isArray(value.modeIds) || !value.modeIds.every((modeId) => typeof modeId === 'string' && modeId.length > 0)) {
    fail(code, `${label}: modeIds が不正である`)
  }
  if (new Set(value.modeIds).size !== value.modeIds.length) fail(code, `${label}: modeIds が重複する`)
  for (const modeId of value.modeIds) nonEmptyString(modeId, code, `${label} modeId`)
}

function assertModelResponse(value, providerId) {
  const code = 'invalid_mad_snapshot'
  exactKeys(value, ['provider', 'models'], code, `list models ${providerId}`)
  if (value.provider !== providerId || !Array.isArray(value.models)) {
    fail(code, `list models ${providerId}: response が不正である`)
  }
  const ids = new Set()
  for (const [index, model] of value.models.entries()) {
    exactKeys(model, ['id', 'thinkingOptionIds'], code, `list models ${providerId}[${index}]`)
    nonEmptyString(model.id, code, `list models ${providerId}[${index}] id`)
    if (ids.has(model.id)) fail(code, `list models ${providerId}: model が重複する`)
    ids.add(model.id)
    if (!Array.isArray(model.thinkingOptionIds) ||
        !model.thinkingOptionIds.every((option) => typeof option === 'string' && option.length > 0)) {
      fail(code, `list models ${providerId}[${index}]: thinkingOptionIds が不正である`)
    }
    if (new Set(model.thinkingOptionIds).size !== model.thinkingOptionIds.length) {
      fail(code, `list models ${providerId}[${index}]: thinkingOptionIds が重複する`)
    }
    for (const option of model.thinkingOptionIds) nonEmptyString(option, code, `list models ${providerId}[${index}] thinkingOptionId`)
  }
  return value
}

function writeAvailabilitySnapshot0600(enumerationPath, listProvidersPath, listModelsDirectory, snapshotPath) {
  const code = 'invalid_mad_snapshot'
  const enumeration = assertEnumeration(readJson(enumerationPath, code, 'provider enumeration'))
  absolutePath(listModelsDirectory, code, 'list models directory')
  let directoryStats
  try { directoryStats = fs.lstatSync(listModelsDirectory) } catch { fail(code, 'list models directory: directory が必要である') }
  if (!directoryStats.isDirectory() || directoryStats.isSymbolicLink()) {
    fail(code, 'list models directory: directory が必要である')
  }

  const listProviders = readJson(listProvidersPath, code, 'list providers')
  exactKeys(listProviders, ['providers'], code, 'list providers')
  if (!Array.isArray(listProviders.providers)) fail(code, 'list providers: providers が不正である')

  const byId = new Map()
  for (const provider of listProviders.providers) {
    assertProviderRecord(provider, code, 'list providers provider')
    if (byId.has(provider.id)) fail(code, 'list providers: provider が重複する')
    if (enumeration.providerIds.includes(provider.id)) byId.set(provider.id, provider)
  }

  const providers = {}
  const models = {}
  for (const providerId of enumeration.providerIds) {
    const provider = byId.get(providerId)
    if (!provider) fail(code, 'list providers: enumeration の provider がない')
    providers[providerId] = { available: provider.available, modeIds: [...provider.modeIds] }
    if (!provider.available) {
      models[providerId] = []
      continue
    }
    const modelPath = path.join(listModelsDirectory, `list-models-${providerId}.json`)
    const modelResponse = assertModelResponse(readJson(modelPath, code, `list models ${providerId}`), providerId)
    models[providerId] = modelResponse.models.map((model) => ({
      id: model.id,
      thinkingOptionIds: [...model.thinkingOptionIds],
    }))
  }

  const snapshot = { version: 1, type: 'paseo-availability-snapshot', providers, models }
  try { assertAvailabilitySnapshot(snapshot) } catch { fail(code, 'availability snapshot: shape が不正である') }
  writeAtomic0600(snapshotPath, JSON.stringify(snapshot, null, 2) + '\n', code, 'availability snapshot')
  return snapshot
}

function writeResolvedExport0600(agentConfigPath, outputPath) {
  const code = 'invalid_mad_export'
  const raw = (() => {
    lstatRegularFile(agentConfigPath, code, 'agent config')
    try { return fs.readFileSync(agentConfigPath, 'utf8') } catch { fail(code, 'agent config: 読み込めない') }
  })()
  let resolved
  try {
    resolved = resolveExport(validateConfig(raw).config)
  } catch {
    fail(code, 'resolved export: config が不正である')
  }
  writeAtomic0600(outputPath, JSON.stringify(resolved, null, 2) + '\n', code, 'resolved export')
  return resolved
}

function writeProviderEnumeration0600(resolvedExportPath, outputPath) {
  const code = 'invalid_mad_export'
  const resolved = readJson(resolvedExportPath, code, 'resolved export')
  let providerIds
  try {
    providerIds = enumerateMaterializedProviderIds(resolved)
  } catch {
    fail(code, 'resolved export: provider enumeration が不正である')
  }
  const enumeration = { version: 1, type: 'paseo-provider-enumeration', providerIds }
  writeAtomic0600(outputPath, JSON.stringify(enumeration, null, 2) + '\n', code, 'provider enumeration')
  return enumeration
}

module.exports = {
  MadContractError,
  assertMadLaunchSpecV1,
  assertMadCreateRequestV1,
  buildMadCreateRequestV1,
  writeMadCreateRequest0600,
  writeAvailabilitySnapshot0600,
  writeResolvedExport0600,
  writeProviderEnumeration0600,
}
