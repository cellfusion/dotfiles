'use strict'

const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')

const { validateConfig } = require('./config-validator.js')
const { resolveExport } = require('./resolver.js')
const { assertAvailabilitySnapshot } = require('./paseo-launch.js')
const { enumerateMaterializedProviderIds } = require('./paseo-providers.js')

const { DUTIES, COMPLEXITIES } = require('./config-types.js')
const SCALAR_TYPES = ['boolean', 'string', 'integer']
const MAD_LAUNCH_KEYS = [
  'version', 'type', 'status', 'environment', 'duty', 'complexity', 'requestedComplexity',
  'provider', 'model', 'modeId', 'thinkingOptionId', 'features', 'warnings',
]
const MAD_REQUEST_KEYS = ['title', 'workspaceId', 'initialPrompt', 'notifyOnFinish', 'provider', 'settings']
const MAD_SETTINGS_KEYS = ['modeId', 'thinkingOptionId', 'features']
const MAD_ACCEPTED_RESPONSE_KEYS = ['status', 'childRef']
const MAD_ATTEMPT_STATE_PENDING_KEYS = ['state', 'create_accepted']
const MAD_CREATE_PREPARE_KEYS = ['version', 'type', 'consumed']
// create の前に取る一回性 marker。attempt directory 直下のこの名前だけを使う。
const MAD_CREATE_PREPARE_MARKER_NAME = 'mcp-create.prepared'
const MAD_CREATE_PREPARE_TYPE = 'mad-create-prepare'
const MAD_CALL_LOG_KEYS = ['version', 'type', 'events']
// call log の event ごとの exact key set。seq と operation は全 event が持つ。
// 宣言にない key を足すと unknown key として拒否される。
const MAD_CALL_LOG_EVENT_KEYS = {
  enumerate_materialized_provider_ids: ['providerIds'],
  list_providers: ['callCount', 'materializedProviderIds', 'availableProviderIds'],
  list_models: ['callCount', 'provider'],
  write_snapshot: ['path', 'mode', 'regularFile'],
  resolve: ['exitCode', 'outputType', 'stdoutDocuments', 'environment', 'role', 'duty',
    'complexity', 'requestedComplexity', 'provider', 'model', 'effort', 'features'],
  build_create_request: ['path', 'mode', 'regularFile', 'topLevelKeys', 'settingsKeys', 'validatedBeforeWrite'],
  create_agent: ['callCount', 'requestPath', 'transport'],
  wait_agent: ['callCount', 'timeoutSeconds', 'status'],
  stop_agent: ['callCount', 'status'],
  failure: ['stage', 'exitCode', 'createCalls', 'state'],
}
// create の transport は公式 MCP tool だけである。call log はその一語だけを許す。
const MAD_CREATE_TRANSPORT = 'mcp__paseo__create_agent'
const MAD_POST_CREATE_OPERATIONS = ['create_agent', 'wait_agent', 'stop_agent', 'failure']
// review/fix は round 0 の初回 review と、round 1 から 3 の fix/re-review を許す。
// 上限は protocol の値であり、親が任意の max_rounds を設定して回避できないようにする。
const MAD_REVIEW_MAX_ROUNDS = 4
const MAD_REVIEW_SCOPE_KEYS = ['version', 'type', 'task', 'allowedFiles', 'findingIds', 'outOfScopePath']
const MAD_REVIEW_OPEN_FINDINGS_KEYS = ['version', 'type', 'task', 'round', 'findings']
const MAD_REVIEW_OPEN_FINDING_KEYS = ['id', 'severity', 'summary', 'location', 'origin', 'originItem']
const MAD_REVIEW_OPEN_FINDING_ID = /^OF-[1-9][0-9]*$/
const MAD_REVIEW_ADMISSION_KEYS = ['version', 'type', 'task', 'phase', 'node', 'attempt', 'round', 'scopeDigest']
const MAD_REVIEW_OBSERVATION_KEYS = ['version', 'type', 'task', 'items']
const MAD_REVIEW_PHASE_ROUNDS = { review: [0, 0], fix: [1, 3], 're-review': [1, 3] }
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
  if (value === '.' || value === '..' || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)) {
    fail(code, `${label}: identifier が不正である`)
  }
}

function parseJsonWithoutDuplicateKeys(raw, code, label) {
  if (typeof raw !== 'string') fail(code, `${label}: JSON が不正である`)
  let index = 0
  const whitespace = () => { while (/\s/.test(raw[index] || '')) index += 1 }
  const invalid = () => { throw new Error('invalid JSON') }
  const parseString = () => {
    if (raw[index] !== '"') invalid()
    const start = index
    index += 1
    while (index < raw.length) {
      const character = raw[index]
      if (character === '"') {
        index += 1
        return JSON.parse(raw.slice(start, index))
      }
      if (character === '\\') {
        index += 1
        const escaped = raw[index]
        if (!'"\\/bfnrtu'.includes(escaped || '')) invalid()
        if (escaped === 'u') {
          const hex = raw.slice(index + 1, index + 5)
          if (!/^[0-9A-Fa-f]{4}$/.test(hex)) invalid()
          index += 4
        }
        index += 1
        continue
      }
      if (character < ' ') invalid()
      index += 1
    }
    invalid()
  }
  const parseValue = () => {
    whitespace()
    if (raw[index] === '{') {
      index += 1
      whitespace()
      // A null prototype makes every parsed JSON key an own data property.
      // In particular, `__proto__` must remain visible to exactKeys instead of
      // mutating this parser's object prototype.
      const object = Object.create(null)
      const keys = new Set()
      if (raw[index] === '}') { index += 1; return object }
      while (true) {
        whitespace()
        const key = parseString()
        if (keys.has(key)) invalid()
        keys.add(key)
        whitespace()
        if (raw[index] !== ':') invalid()
        index += 1
        object[key] = parseValue()
        whitespace()
        if (raw[index] === '}') { index += 1; return object }
        if (raw[index] !== ',') invalid()
        index += 1
      }
    }
    if (raw[index] === '[') {
      index += 1
      whitespace()
      const array = []
      if (raw[index] === ']') { index += 1; return array }
      while (true) {
        array.push(parseValue())
        whitespace()
        if (raw[index] === ']') { index += 1; return array }
        if (raw[index] !== ',') invalid()
        index += 1
      }
    }
    if (raw[index] === '"') return parseString()
    for (const [literal, parsed] of [['true', true], ['false', false], ['null', null]]) {
      if (raw.startsWith(literal, index)) { index += literal.length; return parsed }
    }
    const match = raw.slice(index).match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/)
    if (!match) invalid()
    index += match[0].length
    return Number(match[0])
  }
  try {
    const value = parseValue()
    whitespace()
    if (index !== raw.length) invalid()
    return value
  } catch {
    fail(code, `${label}: JSON が不正である`)
  }
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
  safeIdentifier(value.environment, code, 'mad launch environment')
  if (!DUTIES.includes(value.duty)) fail(code, 'mad launch duty が不正である')
  if (!COMPLEXITIES.includes(value.complexity)) fail(code, 'mad launch complexity が不正である')
  if (!COMPLEXITIES.includes(value.requestedComplexity)) fail(code, 'mad launch requestedComplexity が不正である')
  safeIdentifier(value.provider, code, 'mad launch provider')
  nonEmptyString(value.model, code, 'mad launch model')
  if (value.modeId !== 'auto') fail(code, 'mad launch modeId は auto でなければならない')
  nonEmptyString(value.thinkingOptionId, code, 'mad launch thinkingOptionId')
  assertFeatureValues(value.features, featureAllowlist, code, 'mad launch features')
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

// request は launch から作る。allowlist 検証だけでは、別の launch の値に差し替えた
// request も通る。create の直前に一対一の対応が崩れていないことを確認する。
function assertMadCreateRequestMatchesLaunchV1(request, launch) {
  const code = 'invalid_mad_create_request'
  const sorted = (value) => JSON.stringify(Object.entries(value).sort())
  if (request.provider !== `${launch.provider}/${launch.model}` ||
      request.settings.thinkingOptionId !== launch.thinkingOptionId ||
      sorted(request.settings.features) !== sorted(launch.features)) {
    fail(code, 'mad create request: launch spec と一致しない')
  }
  return request
}

function assertMadCreateAcceptedResponseV1(raw) {
  const code = 'invalid_mad_create_response'
  const value = parseJsonWithoutDuplicateKeys(raw, code, 'mad create accepted response')
  exactKeys(value, MAD_ACCEPTED_RESPONSE_KEYS, code, 'mad create accepted response')
  if (value.status !== 'accepted') fail(code, 'mad create accepted response: status が不正である')
  safeIdentifier(value.childRef, code, 'mad create accepted response childRef')
  return { status: 'accepted', childRef: value.childRef }
}

function assertMadCallLogV1(value) {
  const code = 'invalid_mad_call_log'
  exactKeys(value, MAD_CALL_LOG_KEYS, code, 'mad call log')
  if (value.version !== 1 || value.type !== 'mad-call-log') {
    fail(code, 'mad call log: discriminator が不正である')
  }
  if (!Array.isArray(value.events)) fail(code, 'mad call log: events が array でない')
  for (const [index, event] of value.events.entries()) {
    const label = `mad call log event[${index}]`
    if (!isObject(event)) fail(code, `${label}: object が必要である`)
    const operation = event.operation
    if (typeof operation !== 'string' ||
        !Object.prototype.hasOwnProperty.call(MAD_CALL_LOG_EVENT_KEYS, operation)) {
      fail(code, `${label}: operation が宣言にない`)
    }
    exactKeys(event, ['seq', 'operation', ...MAD_CALL_LOG_EVENT_KEYS[operation]], code, label)
    if (event.seq !== index) fail(code, `${label}: seq が連続していない`)
    if (operation === 'create_agent' && event.transport !== MAD_CREATE_TRANSPORT) {
      fail(code, `${label}: transport は ${MAD_CREATE_TRANSPORT} でなければならない`)
    }
  }
  if (JSON.stringify(value).includes('://')) fail(code, 'mad call log: URL が許可されない')
  return value
}

function assertModeIs0600(filePath, code, label) {
  const stats = lstatRegularFile(filePath, code, label)
  if ((stats.mode & 0o777) !== 0o600) fail(code, `${label}: mode 0600 が必要である`)
  return stats
}

function readStrictJson0600(filePath, code, label) {
  assertModeIs0600(filePath, code, label)
  let raw
  try {
    raw = fs.readFileSync(filePath, 'utf8')
  } catch {
    fail(code, `${label}: 読み込めない`)
  }
  return parseJsonWithoutDuplicateKeys(raw, code, label)
}

function assertMadCallLog0600(logPath) {
  return assertMadCallLogV1(readStrictJson0600(logPath, 'invalid_mad_call_log', 'mad call log'))
}

function assertMadAttemptStatePending0600(statePath) {
  const code = 'invalid_mad_attempt_state'
  const value = readStrictJson0600(statePath, code, 'mad attempt state')
  exactKeys(value, MAD_ATTEMPT_STATE_PENDING_KEYS, code, 'mad attempt state')
  if (value.state !== 'pending') fail(code, 'mad attempt state: pending が必要である')
  if (value.create_accepted !== false) fail(code, 'mad attempt state: create 未受理が必要である')
  return { state: 'pending', create_accepted: false }
}

function assertMadCreateNotStarted0600(logPath, code) {
  const log = assertMadCallLog0600(logPath)
  if (log.events.some((event) => MAD_POST_CREATE_OPERATIONS.includes(event.operation))) {
    fail(code, 'mad call log: create 後の event が既にある')
  }
  return log
}

// create は attempt ごとに一回だけである。request、attempt state、call log の strict
// 検証が全て成功した後にだけ O_EXCL で marker を作る。marker を作れた呼び出しだけが
// 公式 MCP create へ進める。検証に落ちた呼び出しは marker を残さず、state と call log
// も書き換えない。二回目と同時実行の敗者は marker が既にあるため失敗する。
function prepareMadCreate0600(markerPath, requestPath, logPath, statePath, featureAllowlist) {
  const code = 'invalid_mad_create_prepare'
  absolutePath(markerPath, code, 'mad create prepare marker')
  const request = assertMadCreateRequestFile0600(requestPath, featureAllowlist)
  assertMadAttemptStatePending0600(statePath)
  assertMadCreateNotStarted0600(logPath, code)
  let descriptor
  try {
    descriptor = fs.openSync(markerPath, 'wx', 0o600)
  } catch {
    fail(code, 'mad create prepare marker: create は既に準備されている')
  }
  try {
    fs.writeFileSync(
      descriptor,
      JSON.stringify({ version: 1, type: MAD_CREATE_PREPARE_TYPE, consumed: true }),
      'utf8',
    )
    fs.fsyncSync(descriptor)
  } catch {
    try { fs.closeSync(descriptor) } catch {}
    try { fs.unlinkSync(markerPath) } catch {}
    fail(code, 'mad create prepare marker: 書き込みに失敗した')
  }
  fs.closeSync(descriptor)
  fs.chmodSync(markerPath, 0o600)
  fsyncDirectory(path.dirname(markerPath))
  return request
}

// create の後の境界は marker を作らない。prepare が残した marker の mode と schema、
// attempt state、call log だけを確認する。marker が無い呼び出しは create を通って
// いないので、state と call log を書き換えずに失敗する。
function assertMadCreatePrepared0600(markerPath, logPath, statePath) {
  const code = 'invalid_mad_create_prepare'
  const marker = readStrictJson0600(markerPath, code, 'mad create prepare marker')
  exactKeys(marker, MAD_CREATE_PREPARE_KEYS, code, 'mad create prepare marker')
  if (marker.version !== 1 || marker.type !== MAD_CREATE_PREPARE_TYPE || marker.consumed !== true) {
    fail(code, 'mad create prepare marker: discriminator が不正である')
  }
  assertMadAttemptStatePending0600(statePath)
  assertMadCreateNotStarted0600(logPath, code)
  return markerPath
}

function assertMadCreateRequestFile0600(requestPath, featureAllowlist) {
  const code = 'invalid_mad_create_request'
  const request = readStrictJson0600(requestPath, code, 'mad create request')
  return assertMadCreateRequestV1(request, featureAllowlist)
}

function assertScopeRelativePath(value, code, label) {
  nonEmptyString(value, code, label)
  if (path.posix.isAbsolute(value) || value.includes('\\') || value.split('/').some((part) => part === '' || part === '.' || part === '..')) {
    fail(code, `${label}: repository-relative path が必要である`)
  }
  return value
}

function assertUniqueNonEmptyStrings(value, code, label, validator = nonEmptyString) {
  if (!Array.isArray(value) || value.length === 0) fail(code, `${label}: 非空 string 配列が必要である`)
  const seen = new Set()
  for (const entry of value) {
    validator(entry, code, label)
    if (seen.has(entry)) fail(code, `${label}: 重複している`)
    seen.add(entry)
  }
  return value
}

function assertMadReviewScopeV1(value) {
  const code = 'invalid_mad_review_scope'
  exactKeys(value, MAD_REVIEW_SCOPE_KEYS, code, 'mad review scope')
  if (value.version !== 1 || value.type !== 'mad-review-scope') {
    fail(code, 'mad review scope: discriminator が不正である')
  }
  safeIdentifier(value.task, code, 'mad review scope task')
  assertUniqueNonEmptyStrings(value.allowedFiles, code, 'mad review scope allowedFiles', assertScopeRelativePath)
  if (!Array.isArray(value.findingIds)) fail(code, 'mad review scope findingIds: 配列が必要である')
  const findingIds = new Set()
  for (const findingId of value.findingIds) {
    safeIdentifier(findingId, code, 'mad review scope findingId')
    if (findingIds.has(findingId)) fail(code, 'mad review scope findingIds: 重複している')
    findingIds.add(findingId)
  }
  absolutePath(value.outOfScopePath, code, 'mad review scope outOfScopePath')
  return value
}

function readMadReviewScope0600(scopePath) {
  const code = 'invalid_mad_review_scope'
  assertModeIs0600(scopePath, code, 'mad review scope')
  let raw
  try { raw = fs.readFileSync(scopePath, 'utf8') } catch { fail(code, 'mad review scope: 読み込めない') }
  return { raw, value: assertMadReviewScopeV1(parseJsonWithoutDuplicateKeys(raw, code, 'mad review scope')) }
}

function reviewScopeDigest(raw) {
  return crypto.createHash('sha256').update(raw, 'utf8').digest('hex')
}

function assertMadReviewAdmissionV1(value) {
  const code = 'invalid_mad_review_admission'
  exactKeys(value, MAD_REVIEW_ADMISSION_KEYS, code, 'mad review admission')
  if (value.version !== 1 || value.type !== 'mad-review-admission') {
    fail(code, 'mad review admission: discriminator が不正である')
  }
  safeIdentifier(value.task, code, 'mad review admission task')
  if (!Object.prototype.hasOwnProperty.call(MAD_REVIEW_PHASE_ROUNDS, value.phase)) {
    fail(code, 'mad review admission phase が不正である')
  }
  safeIdentifier(value.node, code, 'mad review admission node')
  safeIdentifier(value.attempt, code, 'mad review admission attempt')
  if (!Number.isInteger(value.round) || value.round < 0 || value.round >= MAD_REVIEW_MAX_ROUNDS) {
    fail(code, 'mad review admission round が不正である')
  }
  const range = MAD_REVIEW_PHASE_ROUNDS[value.phase]
  if (value.round < range[0] || value.round > range[1]) {
    fail(code, 'mad review admission phase と round が一致しない')
  }
  if (!/^[0-9a-f]{64}$/.test(value.scopeDigest)) fail(code, 'mad review admission scopeDigest が不正である')
  return value
}

function assertMadReviewAdmissionFile0600(admissionPath) {
  return assertMadReviewAdmissionV1(readStrictJson0600(admissionPath, 'invalid_mad_review_admission', 'mad review admission'))
}

function reviewAdmissionPath(runDir, task, phase, round) {
  return path.join(runDir, 'review-admissions', `${task}-${phase}-round-${round}.json`)
}

function assertReviewRunPolicy(runState, scopePath, scope, code) {
  if (!isObject(runState) || !isObject(runState.review_policy)) fail(code, 'mad review policy が必要である')
  const policy = runState.review_policy
  exactKeys(policy, ['max_rounds', 'scope_file', 'out_of_scope_path'], code, 'mad review policy')
  if (policy.max_rounds !== MAD_REVIEW_MAX_ROUNDS) fail(code, `mad review policy: max_rounds は ${MAD_REVIEW_MAX_ROUNDS} でなければならない`)
  if (runState.max_rounds !== MAD_REVIEW_MAX_ROUNDS) fail(code, `mad review: run max_rounds は ${MAD_REVIEW_MAX_ROUNDS} でなければならない`)
  if (policy.scope_file !== scopePath) fail(code, 'mad review policy: scope_file が一致しない')
  if (policy.out_of_scope_path !== scope.outOfScopePath) fail(code, 'mad review policy: out_of_scope_path が一致しない')
  if (!Number.isInteger(runState.current_round) || runState.current_round < 0 || runState.current_round >= MAD_REVIEW_MAX_ROUNDS) {
    fail(code, 'mad review policy: current_round が上限に達している')
  }
  if (!['implement', 'delivery', 'refine'].includes(runState.recipe)) fail(code, 'mad review policy: recipe が不正である')
}

function existingReviewAdmissions(runDir, task) {
  const directory = path.join(runDir, 'review-admissions')
  let entries
  try { entries = fs.readdirSync(directory) } catch { fail('invalid_mad_review_admission', 'review admissions directory がない') }
  const admissions = []
  for (const name of entries) {
    if (!name.endsWith('.json')) continue
    const admissionPath = path.join(directory, name)
    const admission = assertMadReviewAdmissionFile0600(admissionPath)
    if (admission.task === task) admissions.push({ path: admissionPath, value: admission })
  }
  return admissions
}

// review/fix child の create 前に、task scope と round 上限を確認して admission を一回だけ発行する。
// marker の取得に失敗した呼び出しは公式 MCP create へ進めない。
// `findingIds` は round 0 の review より前に確定する immutable な値であり、round 0 の
// findings ではない。空配列を fix の拒否理由にすると、round 0 の結果で初めて指摘が出る
// 通常の経路が成立しない。未解決の指摘は `mad-review-open-findings` が持つ。
function prepareMadReview0600(runDir, scopePath, phase, node, attempt, taskOverride) {
  const code = 'invalid_mad_review_admission'
  absolutePath(runDir, code, 'mad review run directory')
  absolutePath(scopePath, code, 'mad review scope')
  safeIdentifier(phase, code, 'mad review phase')
  if (!Object.prototype.hasOwnProperty.call(MAD_REVIEW_PHASE_ROUNDS, phase)) fail(code, 'mad review phase が不正である')
  safeIdentifier(node, code, 'mad review node')
  safeIdentifier(attempt, code, 'mad review attempt')
  const scopeFile = readMadReviewScope0600(scopePath)
  const scope = scopeFile.value
  if (taskOverride !== undefined && taskOverride !== scope.task) fail(code, 'mad review task が scope と一致しない')
  if (node !== `${scope.task}-${phase}`) fail(code, 'mad review node が scope task と一致しない')
  const statePath = path.join(runDir, 'state.json')
  const runState = readStrictJson0600(statePath, code, 'mad review run state')
  assertReviewRunPolicy(runState, scopePath, scope, code)
  const round = runState.current_round
  const range = MAD_REVIEW_PHASE_ROUNDS[phase]
  if (!Number.isInteger(round) || round < range[0] || round > range[1]) {
    fail(code, 'mad review current_round と phase が一致しない')
  }
  const admissions = existingReviewAdmissions(runDir, scope.task)
  const digest = reviewScopeDigest(scopeFile.raw)
  if (phase !== 'review') {
    const previousPhase = phase === 'fix' ? 'review' : 'fix'
    const previousRound = phase === 'fix' ? 0 : round
    const previous = admissions.find(({ value }) => value.phase === previousPhase && value.round === previousRound)
    if (!previous || previous.value.scopeDigest !== digest) {
      fail(code, 'mad review scope は loop 中に変更できない')
    }
  }
  if (admissions.some(({ value }) => value.phase === phase && value.round === round)) {
    fail(code, 'mad review admission は既に発行されている')
  }
  if (phase === 'fix' && !admissions.some(({ value }) => value.phase === 'review' && value.round === 0)) {
    fail(code, 'fix は review admission の後でなければならない')
  }
  if (phase === 're-review' && !admissions.some(({ value }) => value.phase === 'fix' && value.round === round)) {
    fail(code, 're-review は同じ round の fix admission の後でなければならない')
  }
  const admissionPath = reviewAdmissionPath(runDir, scope.task, phase, round)
  const admission = {
    version: 1,
    type: 'mad-review-admission',
    task: scope.task,
    phase,
    node,
    attempt,
    round,
    scopeDigest: digest,
  }
  assertMadReviewAdmissionV1(admission)
  let descriptor
  try { descriptor = fs.openSync(admissionPath, 'wx', 0o600) } catch { fail(code, 'mad review admission は既に発行されている') }
  try {
    fs.writeFileSync(descriptor, JSON.stringify(admission) + '\n', 'utf8')
    fs.fsyncSync(descriptor)
    fs.closeSync(descriptor)
  } catch (error) {
    try { fs.closeSync(descriptor) } catch {}
    try { fs.unlinkSync(admissionPath) } catch {}
    fail(code, `mad review admission: 書き込みに失敗した (${error && error.code ? error.code : 'I/O'})`)
  }
  fs.chmodSync(admissionPath, 0o600)
  fsyncDirectory(path.dirname(admissionPath))
  return admissionPath
}

function checkMadReviewScope0600(scopePath, resultPath) {
  const code = 'invalid_mad_review_scope'
  const scope = readMadReviewScope0600(scopePath).value
  const result = readStrictJson0600(resultPath, code, 'mad review result')
  if (!Array.isArray(result.changedFiles) || result.changedFiles.length === 0) {
    fail(code, 'mad review result changedFiles: 非空配列が必要である')
  }
  for (const changedFile of result.changedFiles) {
    assertScopeRelativePath(changedFile, code, 'mad review changedFile')
    if (!scope.allowedFiles.includes(changedFile)) fail(code, `mad review changedFile が scope 外である: ${changedFile}`)
  }
  return result.changedFiles
}

function assertMadReviewObservationsV1(value, task) {
  const code = 'invalid_mad_review_observations'
  exactKeys(value, MAD_REVIEW_OBSERVATION_KEYS, code, 'mad review observations')
  if (value.version !== 1 || value.type !== 'mad-review-observations') fail(code, 'mad review observations: discriminator が不正である')
  safeIdentifier(value.task, code, 'mad review observations task')
  if (task !== undefined && value.task !== task) fail(code, 'mad review observations task が scope と一致しない')
  if (!Array.isArray(value.items)) fail(code, 'mad review observations items: 配列が必要である')
  const ids = new Set()
  for (const [index, item] of value.items.entries()) {
    const label = `mad review observation[${index}]`
    exactKeys(item, ['id', 'severity', 'location', 'summary', 'source'], code, label)
    safeIdentifier(item.id, code, `${label} id`)
    if (ids.has(item.id)) fail(code, `${label} id が重複している`)
    ids.add(item.id)
    if (!['critical', 'important', 'minor'].includes(item.severity)) fail(code, `${label} severity が不正である`)
    for (const field of ['location', 'summary', 'source']) nonEmptyString(item[field], code, `${label} ${field}`)
    if (JSON.stringify(item).includes('://')) fail(code, `${label}: URL が許可されない`)
  }
  return value
}

function assertMadReviewObservationsFile0600(observationsPath, task) {
  const code = 'invalid_mad_review_observations'
  const value = readStrictJson0600(observationsPath, code, 'mad review observations')
  return assertMadReviewObservationsV1(value, task)
}

function writeMadReviewObservations0600(value, observationsPath, task) {
  const code = 'invalid_mad_review_observations'
  assertMadReviewObservationsV1(value, task)
  return writeAtomic0600(observationsPath, JSON.stringify(value, null, 2) + '\n', code, 'mad review observations')
}

function shaPrefixMatches(expected, reported) {
  return expected.startsWith(reported) || reported.startsWith(expected)
}

// レビュー役が読んだ範囲を照合する。レビュー役は範囲を自分で調べられないので、親が渡した
// review package の header と、レビュー役の報告した範囲が一致するかだけが手掛かりになる。
function checkMadReviewPackageRange0600(packagePath, resultPath) {
  const code = 'invalid_mad_review_package'
  absolutePath(packagePath, code, 'mad review package')
  assertModeIs0600(packagePath, code, 'mad review package')
  lstatRegularFile(packagePath, code, 'mad review package')
  let raw
  try { raw = fs.readFileSync(packagePath, 'utf8') } catch { fail(code, 'mad review package: 読み込めない') }
  const header = raw.split('\n', 1)[0]
  const match = /^# Review package: ([0-9a-f]{40})\.\.([0-9a-f]{40})$/.exec(header)
  if (match === null) fail(code, 'mad review package: header が範囲を示していない')
  const [, packageBase, packageHead] = match
  const result = readStrictJson0600(resultPath, code, 'mad review result')
  for (const field of ['packageBase', 'packageHead']) {
    const reported = result[field]
    if (typeof reported !== 'string' || !/^[0-9a-f]{7,40}$/.test(reported)) {
      fail(code, `mad review result ${field}: 7 文字以上 40 文字以下の小文字 16 進文字列が必要である`)
    }
  }
  if (!shaPrefixMatches(packageBase, result.packageBase)) {
    fail(code, `mad review result packageBase が範囲と一致しない: 期待 ${packageBase} / 報告 ${result.packageBase}`)
  }
  if (!shaPrefixMatches(packageHead, result.packageHead)) {
    fail(code, `mad review result packageHead が範囲と一致しない: 期待 ${packageHead} / 報告 ${result.packageHead}`)
  }
  return { packageBase, packageHead }
}

const MAD_REVIEW_VERDICT_ROLES = ['task-reviewer', 're-reviewer']

// verdict と findings が食い違うレビュー結果を採用しない。合格と報告しながら重い finding を
// 並べる結果も、指摘ありと報告しながら findings を空にする結果も、どちらも親が判断できない。
function checkMadReviewVerdict0600(resultPath, role, openFindingsPath) {
  const code = 'invalid_mad_review_verdict'
  if (!MAD_REVIEW_VERDICT_ROLES.includes(role)) fail(code, 'mad review verdict role が不正である')
  const result = readStrictJson0600(resultPath, code, 'mad review result')
  if (role === 'task-reviewer') {
    const findings = result.findings
    if (!Array.isArray(findings)) fail(code, 'mad review result findings: 配列が必要である')
    if (result.specVerdict === 'issues' && findings.length === 0) {
      fail(code, 'mad review verdict: specVerdict が issues なのに findings が空である')
    }
    if (result.qualityVerdict === 'needs_fixes' && findings.length === 0) {
      fail(code, 'mad review verdict: qualityVerdict が needs_fixes なのに findings が空である')
    }
    if (result.specVerdict === 'compliant' && result.qualityVerdict === 'approved') {
      const heavy = findings.filter((finding) => finding && (finding.severity === 'critical' || finding.severity === 'important'))
      if (heavy.length > 0) {
        fail(code, `mad review verdict: 合格の verdict に critical/important の finding が ${heavy.length} 件ある`)
      }
    }
    return result
  }
  const open = assertMadReviewOpenFindingsV1(
    readStrictJson0600(openFindingsPath, code, 'mad review open findings')
  )
  const expected = new Set(open.findings.map((finding) => finding.id))
  const verdicts = result.verdicts
  if (!Array.isArray(verdicts)) fail(code, 'mad review result verdicts: 配列が必要である')
  if (expected.size === 0 && verdicts.length !== 0) {
    fail(code, 'mad review verdict: 未解決の指摘が無いのに verdict がある')
  }
  const reported = new Set()
  for (const verdict of verdicts) {
    const findingId = verdict && verdict.findingId
    nonEmptyString(findingId, code, 'mad review verdict findingId')
    if (reported.has(findingId)) fail(code, `mad review verdict: findingId が重複している: ${findingId}`)
    reported.add(findingId)
  }
  const missing = [...expected].filter((id) => !reported.has(id))
  const unexpected = [...reported].filter((id) => !expected.has(id))
  if (missing.length > 0 || unexpected.length > 0) {
    fail(code, `mad review verdict: findingId の集合が一覧と一致しない: 欠落 [${missing.join(',')}] / 余分 [${unexpected.join(',')}]`)
  }
  return result
}

// 未解決の指摘の一覧の形を確かめる。`id` は `OF-` から始める書式に固定し、`mad-review-scope`
// の `findingIds` と名前空間を分ける。`safeIdentifier` だけでは `OF0` も `x-1` も通るので、
// 書式の検査を重ねる。空配列を許すため `assertUniqueNonEmptyStrings` は使わない。
function assertMadReviewOpenFindingsV1(value, task, round) {
  const code = 'invalid_mad_review_open_findings'
  exactKeys(value, MAD_REVIEW_OPEN_FINDINGS_KEYS, code, 'mad review open findings')
  if (value.version !== 1 || value.type !== 'mad-review-open-findings') {
    fail(code, 'mad review open findings: discriminator が不正である')
  }
  safeIdentifier(value.task, code, 'mad review open findings task')
  if (task !== undefined && value.task !== task) fail(code, 'mad review open findings task が scope と一致しない')
  if (!Number.isInteger(value.round) || value.round < 1 || value.round >= MAD_REVIEW_MAX_ROUNDS) {
    fail(code, 'mad review open findings round が範囲外である')
  }
  if (round !== undefined && value.round !== round) fail(code, 'mad review open findings round が期待と一致しない')
  if (!Array.isArray(value.findings)) fail(code, 'mad review open findings findings: 配列が必要である')
  const ids = new Set()
  for (const [index, finding] of value.findings.entries()) {
    const label = `mad review open finding[${index}]`
    exactKeys(finding, MAD_REVIEW_OPEN_FINDING_KEYS, code, label)
    safeIdentifier(finding.id, code, `${label} id`)
    if (!MAD_REVIEW_OPEN_FINDING_ID.test(finding.id)) fail(code, `${label} id: OF-<1 以上の整数> が必要である`)
    if (ids.has(finding.id)) fail(code, `${label} id が重複している`)
    ids.add(finding.id)
    if (!['critical', 'important'].includes(finding.severity)) fail(code, `${label} severity が不正である`)
    nonEmptyString(finding.summary, code, `${label} summary`)
    nonEmptyString(finding.location, code, `${label} location`)
    if (!['review-finding', 'cannot-verify'].includes(finding.origin)) fail(code, `${label} origin が不正である`)
    if (finding.origin === 'cannot-verify') {
      nonEmptyString(finding.originItem, code, `${label} originItem`)
    } else if (finding.originItem !== null) {
      fail(code, `${label} originItem: review-finding では null が必要である`)
    }
  }
  return value
}

function madReviewOpenFindingsDirectory(runDir) {
  return path.join(runDir, 'review-open-findings')
}

function madReviewOpenFindingsPath(runDir, task, round) {
  return path.join(madReviewOpenFindingsDirectory(runDir), `${task}-round-${round}.json`)
}

function readMadReviewOpenFindings0600(runDir, task, round) {
  const code = 'invalid_mad_review_open_findings'
  const listPath = madReviewOpenFindingsPath(runDir, task, round)
  const value = readStrictJson0600(listPath, code, 'mad review open findings')
  return assertMadReviewOpenFindingsV1(value, task, round)
}

// その task で一度使った `id` を別の指摘へ割り当てない。ラウンドの途中で解消した指摘の
// 番号も再利用しないので、既に書いた一覧すべてから最大の番号を取る。
function highestMadReviewFindingNumber(runDir, task) {
  const directory = madReviewOpenFindingsDirectory(runDir)
  let entries
  try { entries = fs.readdirSync(directory) } catch { return 0 }
  let highest = 0
  for (const entry of entries) {
    if (!new RegExp(`^${task}-round-[0-9]+\\.json$`).test(entry)) continue
    let parsed
    try { parsed = JSON.parse(fs.readFileSync(path.join(directory, entry), 'utf8')) } catch { continue }
    if (!parsed || !Array.isArray(parsed.findings)) continue
    for (const finding of parsed.findings) {
      const match = finding && typeof finding.id === 'string' ? MAD_REVIEW_OPEN_FINDING_ID.exec(finding.id) : null
      if (match === null) continue
      const number = Number(finding.id.slice(3))
      if (number > highest) highest = number
    }
  }
  return highest
}

function writeMadReviewOpenFindings0600(runDir, list) {
  const code = 'invalid_mad_review_open_findings'
  assertMadReviewOpenFindingsV1(list, list.task, list.round)
  const directory = madReviewOpenFindingsDirectory(runDir)
  try { fs.mkdirSync(directory, { recursive: true, mode: 0o700 }) } catch { fail(code, 'mad review open findings: ディレクトリを作れない') }
  const listPath = madReviewOpenFindingsPath(runDir, list.task, list.round)
  let descriptor
  try { descriptor = fs.openSync(listPath, 'wx', 0o600) } catch { fail(code, 'mad review open findings: 一覧は既に存在する') }
  try {
    fs.writeFileSync(descriptor, JSON.stringify(list, null, 2) + '\n', 'utf8')
    fs.fsyncSync(descriptor)
    fs.closeSync(descriptor)
  } catch (error) {
    try { fs.closeSync(descriptor) } catch {}
    try { fs.unlinkSync(listPath) } catch {}
    fail(code, `mad review open findings: 書き込みに失敗した (${error && error.code ? error.code : 'I/O'})`)
  }
  fs.chmodSync(listPath, 0o600)
  fsyncDirectory(directory)
  return listPath
}

// round 0 の結果と `cannotVerify` の解消の記録から round 1 の一覧を作る。プランと衝突する
// 指摘はユーザーの判断事項なので、1 件でもあれば一覧を作らずに失敗する。
function openMadReviewFindings0600(runDir, scopePath, resultPath, cannotVerifyPath) {
  const code = 'invalid_mad_review_open_findings'
  absolutePath(runDir, code, 'mad review run directory')
  const scope = readMadReviewScope0600(scopePath).value
  const result = readStrictJson0600(resultPath, code, 'mad review result')
  if (!Array.isArray(result.findings)) fail(code, 'mad review result findings: 配列が必要である')
  const cannotVerify = result.cannotVerify
  if (cannotVerify !== null && cannotVerify !== undefined && !Array.isArray(cannotVerify)) {
    fail(code, 'mad review result cannotVerify: 配列か null が必要である')
  }
  const hasCannotVerify = Array.isArray(cannotVerify) && cannotVerify.length > 0
  if (!hasCannotVerify && cannotVerifyPath !== null && cannotVerifyPath !== undefined && cannotVerifyPath !== '') {
    fail(code, 'mad review: cannotVerify が空なのに解消の記録が渡された')
  }
  if (hasCannotVerify && (cannotVerifyPath === null || cannotVerifyPath === undefined || cannotVerifyPath === '')) {
    fail(code, 'mad review: cannotVerify が非空なのに解消の記録が渡されていない')
  }
  if (result.findings.some((finding) => finding && finding.planMandated === true)) {
    fail(code, 'mad review: planMandated の finding は fix ループへ入れられない')
  }
  const findings = []
  let number = 0
  for (const finding of result.findings) {
    if (!finding || (finding.severity !== 'critical' && finding.severity !== 'important')) continue
    nonEmptyString(finding.summary, code, 'mad review finding summary')
    nonEmptyString(finding.location, code, 'mad review finding location')
    number += 1
    findings.push({
      id: `OF-${number}`,
      severity: finding.severity,
      summary: finding.summary,
      location: finding.location,
      origin: 'review-finding',
      originItem: null,
    })
  }
  if (hasCannotVerify) {
    const record = readStrictJson0600(cannotVerifyPath, code, 'mad review cannot verify')
    if (!Array.isArray(record.items)) fail(code, 'mad review cannot verify items: 配列が必要である')
    for (const item of record.items) {
      if (!item || item.resolution !== 'confirmed_gap') continue
      nonEmptyString(item.item, code, 'mad review cannot verify item')
      nonEmptyString(item.detail, code, 'mad review cannot verify detail')
      nonEmptyString(item.location, code, 'mad review cannot verify location')
      if (!['critical', 'important'].includes(item.severity)) fail(code, 'mad review cannot verify severity が不正である')
      number += 1
      findings.push({
        id: `OF-${number}`,
        severity: item.severity,
        summary: item.detail,
        location: item.location,
        origin: 'cannot-verify',
        originItem: item.item,
      })
    }
  }
  return writeMadReviewOpenFindings0600(runDir, {
    version: 1,
    type: 'mad-review-open-findings',
    task: scope.task,
    round: 1,
    findings,
  })
}

// round N の再レビューの結果から round N+1 の一覧を作る。`severity` と `summary` は round N の
// 一覧の値をそのまま写す。再レビュー役は指摘を判定するだけで severity を付け直さないので、
// 写し直すと元の較正が失われる。引き継ぎは `id` だけで行い、`summary` の文字列一致で
// 絞り込まない。
function advanceMadReviewFindings0600(runDir, scopePath, round, resultPath) {
  const code = 'invalid_mad_review_open_findings'
  absolutePath(runDir, code, 'mad review run directory')
  if (!Number.isInteger(round)) fail(code, 'mad review round: 整数が必要である')
  if (round + 1 >= MAD_REVIEW_MAX_ROUNDS) fail(code, 'mad review: 上限に達した run は次のラウンドの一覧を作らない')
  const scope = readMadReviewScope0600(scopePath).value
  const previous = readMadReviewOpenFindings0600(runDir, scope.task, round)
  const result = readStrictJson0600(resultPath, code, 'mad review result')
  if (!Array.isArray(result.verdicts)) fail(code, 'mad review result verdicts: 配列が必要である')
  const newBreakage = result.newBreakage === null || result.newBreakage === undefined ? [] : result.newBreakage
  if (!Array.isArray(newBreakage)) fail(code, 'mad review result newBreakage: 配列か null が必要である')
  const byId = new Map(previous.findings.map((finding) => [finding.id, finding]))
  const seen = new Set()
  const findings = []
  for (const verdict of result.verdicts) {
    const findingId = verdict && verdict.findingId
    nonEmptyString(findingId, code, 'mad review verdict findingId')
    if (seen.has(findingId)) fail(code, `mad review verdict: findingId が重複している: ${findingId}`)
    seen.add(findingId)
    if (!byId.has(findingId)) fail(code, `mad review verdict: 一覧に無い findingId である: ${findingId}`)
    if (typeof verdict.addressed !== 'boolean') fail(code, 'mad review verdict addressed: boolean が必要である')
    if (verdict.addressed) continue
    const carried = byId.get(findingId)
    const evidence = typeof verdict.evidence === 'string' && verdict.evidence.length > 0 ? verdict.evidence : carried.location
    findings.push({
      id: carried.id,
      severity: carried.severity,
      summary: carried.summary,
      location: evidence,
      origin: carried.origin,
      originItem: carried.originItem,
    })
  }
  for (const missing of byId.keys()) {
    if (!seen.has(missing)) fail(code, `mad review verdict: 判定されていない findingId がある: ${missing}`)
  }
  let number = highestMadReviewFindingNumber(runDir, scope.task)
  for (const breakage of newBreakage) {
    if (!breakage || (breakage.severity !== 'critical' && breakage.severity !== 'important')) continue
    nonEmptyString(breakage.summary, code, 'mad review newBreakage summary')
    nonEmptyString(breakage.location, code, 'mad review newBreakage location')
    number += 1
    findings.push({
      id: `OF-${number}`,
      severity: breakage.severity,
      summary: breakage.summary,
      location: breakage.location,
      origin: 'review-finding',
      originItem: null,
    })
  }
  return writeMadReviewOpenFindings0600(runDir, {
    version: 1,
    type: 'mad-review-open-findings',
    task: scope.task,
    round: round + 1,
    findings,
  })
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
      features: { ...launch.features },
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
  MAD_CREATE_TRANSPORT,
  MAD_CREATE_PREPARE_MARKER_NAME,
  MAD_LAUNCH_KEYS,
  MAD_REVIEW_MAX_ROUNDS,
  MAD_REVIEW_PHASE_ROUNDS,
  assertMadLaunchSpecV1,
  assertMadCreateRequestV1,
  assertMadCreateRequestFile0600,
  assertMadCreateRequestMatchesLaunchV1,
  assertMadCallLogV1,
  assertMadCallLog0600,
  assertMadAttemptStatePending0600,
  prepareMadCreate0600,
  assertMadCreatePrepared0600,
  assertMadReviewScopeV1,
  assertMadReviewAdmissionV1,
  assertMadReviewAdmissionFile0600,
  reviewAdmissionPath,
  prepareMadReview0600,
  checkMadReviewScope0600,
  checkMadReviewPackageRange0600,
  checkMadReviewVerdict0600,
  assertMadReviewOpenFindingsV1,
  openMadReviewFindings0600,
  advanceMadReviewFindings0600,
  assertMadReviewObservationsV1,
  assertMadReviewObservationsFile0600,
  writeMadReviewObservations0600,
  assertMadCreateAcceptedResponseV1,
  parseJsonWithoutDuplicateKeys,
  buildMadCreateRequestV1,
  writeMadCreateRequest0600,
  writeAvailabilitySnapshot0600,
  writeResolvedExport0600,
  writeProviderEnumeration0600,
}
