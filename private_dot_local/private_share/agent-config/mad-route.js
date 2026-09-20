'use strict'

const fs = require('node:fs')
const path = require('node:path')
const contract = require('./mad-contract.js')

const TOP_KEYS = ['version', 'type', 'routeId', 'recordedAt', 'route', 'workClass', 'complexity', 'role', 'confidence', 'reasonCode', 'backend', 'provider', 'model', 'effort', 'delegated']
const WORK_CLASSES = ['mechanical', 'routine', 'integration', 'architectural']
const COMPLEXITIES = ['simple', 'routine', 'complex', 'critical']

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function exactKeys(value, keys) { return isObject(value) && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort()) }
function safeString(value, label) {
  if (typeof value !== 'string' || value.length === 0 || value.includes('\n') || value.includes('\r') || value.includes('://')) throw new Error(`${label} must be a non-empty safe string`)
}
function nullableString(value, label) { if (value !== null) safeString(value, label) }
function assertRouteV1(value) {
  if (!exactKeys(value, TOP_KEYS) || value.version !== 1 || value.type !== 'mad-route-decision') throw new Error('route record has invalid top-level keys')
  safeString(value.routeId, 'routeId')
  safeString(value.recordedAt, 'recordedAt')
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value.recordedAt)) throw new Error('recordedAt must be an ISO UTC timestamp')
  if (!['direct', 'single', 'delivery'].includes(value.route)) throw new Error('route is invalid')
  if (!WORK_CLASSES.includes(value.workClass)) throw new Error('workClass is invalid')
  if (!COMPLEXITIES.includes(value.complexity)) throw new Error('complexity is invalid')
  safeString(value.role, 'role')
  if (!['low', 'medium', 'high'].includes(value.confidence)) throw new Error('confidence is invalid')
  safeString(value.reasonCode, 'reasonCode')
  if (value.backend !== null && !['paseo-cli', 'paseo-mcp'].includes(value.backend)) throw new Error('backend is invalid')
  for (const field of ['provider', 'model', 'effort']) nullableString(value[field], field)
  if (typeof value.delegated !== 'boolean') throw new Error('delegated must be boolean')
  return value
}
function ensureOutput(outputPath) {
  const dir = path.dirname(outputPath)
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 })
  try { const stats = fs.lstatSync(outputPath); if (!stats.isFile() || (stats.mode & 0o777) !== 0o600) throw new Error('output must be a regular mode 0600 file') } catch (error) { if (error && error.code !== 'ENOENT') throw error }
}
function readRecord(recordPath) {
  let stats; try { stats = fs.lstatSync(recordPath) } catch { throw new Error('record file is unavailable') }
  if (!stats.isFile() || (stats.mode & 0o777) !== 0o600) throw new Error('record file must be a regular mode 0600 file')
  return assertRouteV1(contract.parseJsonWithoutDuplicateKeys(fs.readFileSync(recordPath, 'utf8'), 'invalid_mad_route', 'route record'))
}
function appendRoute(recordPath, outputPath) {
  const record = readRecord(recordPath); ensureOutput(outputPath)
  const fd = fs.openSync(outputPath, 'a', 0o600)
  try { fs.writeSync(fd, JSON.stringify(record) + '\n', null, 'utf8'); fs.fsyncSync(fd) } finally { fs.closeSync(fd) }
  fs.chmodSync(outputPath, 0o600)
  return record
}
module.exports = { assertRouteV1, appendRoute }
