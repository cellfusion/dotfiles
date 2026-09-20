'use strict'

const fs = require('node:fs')
const path = require('node:path')
const contract = require('./mad-contract.js')

const TOP_KEYS = [
  'version', 'type', 'recordedAt', 'taskId', 'runId', 'attemptId',
  'route', 'outcome', 'usage', 'toolLoopCount', 'toolLoopSource', 'verification',
]
const ROUTE_KEYS = [
  'workClass', 'complexity', 'role', 'backend', 'provider', 'model',
  'effort', 'policyLevel', 'trigger', 'round',
]
const OUTCOME_KEYS = ['status', 'retryCount', 'durationMs']
const USAGE_KEYS = ['inputTokens', 'cachedInputTokens', 'outputTokens', 'costUsd', 'source']
const VERIFICATION_KEYS = ['tests', 'review', 'changedFiles', 'regression']

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function exactKeys(value, keys) {
  return isObject(value) && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort())
}

function nonEmptyString(value, label) {
  if (typeof value !== 'string' || value.length === 0 || value.includes('\n') || value.includes('\r') || value.includes('://')) {
    throw new Error(`${label} must be a non-empty safe string`)
  }
}

function nonNegativeInteger(value, label) {
  if (!Number.isInteger(value) || value < 0) throw new Error(`${label} must be a non-negative integer`)
}

function nonNegativeNumberOrNull(value, label) {
  if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
    throw new Error(`${label} must be a non-negative number or null`)
  }
}

function assertOutcomeV1(value) {
  if (!exactKeys(value, TOP_KEYS) || value.version !== 1 || value.type !== 'mad-attempt-outcome') {
    throw new Error('outcome record has invalid top-level keys')
  }
  nonEmptyString(value.recordedAt, 'recordedAt')
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value.recordedAt)) {
    throw new Error('recordedAt must be an ISO UTC timestamp')
  }
  for (const field of ['taskId', 'runId', 'attemptId']) nonEmptyString(value[field], field)

  if (!exactKeys(value.route, ROUTE_KEYS)) throw new Error('route keys are invalid')
  for (const field of ['workClass', 'complexity', 'role', 'backend', 'provider', 'model', 'effort', 'trigger']) {
    nonEmptyString(value.route[field], `route.${field}`)
  }
  if (!['mechanical', 'routine', 'integration', 'architectural'].includes(value.route.workClass)) throw new Error('route.workClass is invalid')
  if (!['simple', 'routine', 'complex', 'critical'].includes(value.route.complexity)) throw new Error('route.complexity is invalid')
  if (!['paseo-cli', 'paseo-mcp'].includes(value.route.backend)) throw new Error('route.backend is invalid')
  if (!['initial', 'retry', 'escalation'].includes(value.route.trigger)) throw new Error('route.trigger is invalid')
  nonNegativeInteger(value.route.policyLevel, 'route.policyLevel')
  nonNegativeInteger(value.route.round, 'route.round')

  if (!exactKeys(value.outcome, OUTCOME_KEYS)) throw new Error('outcome keys are invalid')
  if (!['completed', 'failed', 'unresolved', 'cancelled'].includes(value.outcome.status)) throw new Error('outcome.status is invalid')
  nonNegativeInteger(value.outcome.retryCount, 'outcome.retryCount')
  nonNegativeInteger(value.outcome.durationMs, 'outcome.durationMs')

  if (!exactKeys(value.usage, USAGE_KEYS)) throw new Error('usage keys are invalid')
  for (const field of ['inputTokens', 'cachedInputTokens', 'outputTokens']) nonNegativeInteger(value.usage[field], `usage.${field}`)
  nonNegativeNumberOrNull(value.usage.costUsd, 'usage.costUsd')
  if (!['paseo-inspect', 'paseo-logs', 'manual', 'unavailable'].includes(value.usage.source)) throw new Error('usage.source is invalid')

  if (value.toolLoopCount !== null) nonNegativeInteger(value.toolLoopCount, 'toolLoopCount')
  if (!['paseo-logs', 'manual', 'unavailable'].includes(value.toolLoopSource)) throw new Error('toolLoopSource is invalid')
  if (value.toolLoopCount === null && value.toolLoopSource !== 'unavailable') {
    throw new Error('null toolLoopCount requires unavailable source')
  }

  if (!exactKeys(value.verification, VERIFICATION_KEYS)) throw new Error('verification keys are invalid')
  if (!['passed', 'failed', 'unknown'].includes(value.verification.tests)) throw new Error('verification.tests is invalid')
  if (!['accepted', 'findings', 'unknown'].includes(value.verification.review)) throw new Error('verification.review is invalid')
  nonNegativeInteger(value.verification.changedFiles, 'verification.changedFiles')
  if (!['none', 'detected', 'unknown'].includes(value.verification.regression)) throw new Error('verification.regression is invalid')
  return value
}

function readRecordFile(recordPath) {
  let stats
  try { stats = fs.lstatSync(recordPath) } catch { throw new Error('record file is unavailable') }
  if (!stats.isFile() || (stats.mode & 0o777) !== 0o600) throw new Error('record file must be a regular mode 0600 file')
  let raw
  try { raw = fs.readFileSync(recordPath, 'utf8') } catch { throw new Error('record file is unreadable') }
  return assertOutcomeV1(contract.parseJsonWithoutDuplicateKeys(raw, 'invalid_mad_attempt_outcome', 'outcome record'))
}

function ensureOutput(outputPath) {
  const directory = path.dirname(outputPath)
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 })
  let directoryStats
  try { directoryStats = fs.statSync(directory) } catch { throw new Error('output directory is unavailable') }
  if (!directoryStats.isDirectory()) throw new Error('output parent is not a directory')
  try {
    const stats = fs.lstatSync(outputPath)
    if (!stats.isFile() || (stats.mode & 0o777) !== 0o600) throw new Error('output must be a regular mode 0600 file')
  } catch (error) {
    if (error && error.code !== 'ENOENT') throw error
  }
}

function appendOutcome(recordPath, outputPath) {
  const record = readRecordFile(recordPath)
  ensureOutput(outputPath)
  let fd
  try {
    fd = fs.openSync(outputPath, 'a', 0o600)
    fs.writeSync(fd, JSON.stringify(record) + '\n', null, 'utf8')
    fs.fsyncSync(fd)
  } finally {
    if (fd !== undefined) fs.closeSync(fd)
  }
  fs.chmodSync(outputPath, 0o600)
  return record
}

module.exports = { assertOutcomeV1, appendOutcome, readRecordFile }
