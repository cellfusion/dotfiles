'use strict'
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const { spawn } = require('node:child_process')
const readline = require('node:readline')

const STALE_MS = 30 * 60 * 1000
const number = value => typeof value === 'number' && Number.isFinite(value)
const text = value => typeof value === 'string' ? value.replace(/[\x00-\x1f\x7f-\x9f]/g, '').slice(0, 100) : 'unknown'
const percent = value => number(value) && value >= 0 && value <= 100 ? value : null
const timestamp = value => number(value) && value > 0 ? value : null
function flags(status, collectedAt, resetsAt, now, error, measured) {
  const result = []
  if (measured && (collectedAt === null || collectedAt > now || now - collectedAt >= STALE_MS || (resetsAt !== null && resetsAt <= now) || status === 'stale')) result.push('stale')
  if (error || status === 'error' || status === 'parse-error') result.push('error')
  if (status === 'unsupported') result.push('unsupported')
  if (!measured && !result.length) result.push('unknown')
  if (measured && !result.length) result.push('fresh')
  return result
}
function cacheEntries(cache) {
  if (!cache || cache.version !== 1 || !Array.isArray(cache.environments)) throw new Error('invalid native cache')
  if (Array.isArray(cache.sources)) return cache.sources.map((entry, index) => ({ ...entry, key: typeof entry.sourceId === 'string' && /^[a-zA-Z0-9_-]{1,64}$/.test(entry.sourceId) ? entry.sourceId : `source-${index + 1}` }))
  return cache.environments.flatMap((environment, index) => (Array.isArray(environment.agents) ? environment.agents : []).map(entry => ({ ...entry, environments: [environment.name], key: `legacy-${index + 1}-${text(entry.agent)}` })))
}
function cacheRows(cache, now) {
  return cacheEntries(cache).flatMap((entry, index) => {
    const collectedAt = timestamp(entry.collectedAt) === null ? null : entry.collectedAt * 1000
    const environments = (entry.environments || []).map((name, n) => typeof name === 'string' && /^[a-zA-Z0-9_-]{1,32}$/.test(name) ? name : `env-${n + 1}`)
    const base = { source: `native:${entry.key}`, environment: environments.join(',') || 'unknown', account: 'account-unknown', provider: entry.agent === 'claude' ? 'anthropic' : entry.agent === 'codex' ? 'openai-codex' : 'unknown', collectedAt, shared: null }
    const row = (name, window, status, error) => {
      const usedPct = percent(window?.usedPct)
      const resetsAt = timestamp(window?.resetsAt) === null ? null : window.resetsAt * 1000
      const code = typeof error === 'string' ? error.match(/(?:^|: )(auth-missing|auth-rejected|rate-limited|request-failed|parse-error)$/)?.[1] : null
      const errorReason = code === 'auth-missing' || code === 'auth-rejected' ? 'auth-required' : code || null
      return { ...base, window: name, durationMs: timestamp(window?.durationMs), usedPct, remainingPct: null, resetsAt, errorReason, flags: flags(status, collectedAt, resetsAt, now, error, usedPct !== null) }
    }
    return [row('week (source classification)', entry.week, entry.weekStatus, entry.lastError), row('session (source classification)', entry.session, entry.sessionStatus, entry.lastError || entry.sessionError), ...(entry.models || []).map((model, n) => row(`${typeof model.name === 'string' && /^[a-zA-Z0-9 _.-]{1,40}$/.test(model.name) ? model.name : `model-${n + 1}`} week (source classification)`, model, entry.weekStatus, entry.lastError))]
  })
}
function ompRows(snapshot, now) {
  if (!snapshot || !Array.isArray(snapshot.reports)) throw new Error('invalid OMP usage snapshot')
  const rows = snapshot.reports.flatMap((report, index) => {
    const base = { source: 'omp', environment: process.env.OMP_PROFILE ? 'active-profile' : 'default', account: `account-${index + 1}`, provider: text(report.provider), collectedAt: timestamp(report.fetchedAt) }
    const limits = Array.isArray(report.limits) && report.limits.length ? report.limits : [null]
    return limits.map(limit => {
      const amount = limit?.amount
      const usedPct = number(amount?.usedFraction) ? percent(amount.usedFraction * 100) : amount?.unit === 'percent' ? percent(amount.used) : null
      const remainingPct = number(amount?.remainingFraction) ? percent(amount.remainingFraction * 100) : amount?.unit === 'percent' ? percent(amount.remaining) : null
      const resetsAt = timestamp(limit?.window?.resetsAt)
      return { ...base, window: text(limit?.window?.label || limit?.label || limit?.window?.id), durationMs: timestamp(limit?.window?.durationMs), usedPct, remainingPct, resetsAt, shared: limit?.scope?.shared === true, flags: flags(limit?.status, base.collectedAt, resetsAt, now, Boolean(report.error), usedPct !== null || remainingPct !== null) }
    })
  })
  for (const entry of snapshot.accountsWithoutUsage || []) rows.push({ source: 'omp', environment: 'active-profile', account: `account-${rows.length + 1}`, provider: text(entry.provider), window: 'unknown', durationMs: null, usedPct: null, remainingPct: null, resetsAt: null, collectedAt: null, shared: null, flags: ['unsupported'] })
  for (const entry of snapshot.disabledCredentials || []) {
    if (entry.type !== 'oauth') continue
    // Upstream disable causes may contain credentials; only expose actionable state.
    rows.push({ source: 'omp', environment: process.env.OMP_PROFILE ? 'active-profile' : 'default', account: `account-${rows.length + 1}`, provider: text(entry.provider), window: 'unknown', durationMs: null, usedPct: null, remainingPct: null, resetsAt: null, collectedAt: null, shared: null, errorReason: 'auth-required', flags: ['error'] })
  }
  return rows
}
function refreshedSources(before, after) {
  const prior = new Map(before ? cacheEntries(before).map(entry => [entry.key, entry.collectedAt]) : [])
  return new Map(cacheEntries(after).map(entry => [entry.key, number(entry.collectedAt) && entry.collectedAt > (prior.get(entry.key) ?? 0)]))
}
function iso(value) { return value === null ? 'unknown' : new Date(value).toISOString() }
function duration(value) {
  if (value === null) return 'unknown'
  for (const [ms, label] of [[86400000, 'days'], [3600000, 'hours'], [60000, 'minutes']]) if (value % ms === 0) return `${value / ms} ${label}`
  return `${value / 1000} seconds`
}
function render(rows, notices) {
  const lines = ['Account usage limits (not session tokens/cost)', 'Sources may share account quotas; rows are NOT added together.', 'Account identities are redacted; native account identity is unverified.', '']
  for (const row of rows) {
    lines.push(`${row.source} | env=${row.environment} | ${row.account} | ${row.provider}`)
    lines.push(`  ${row.window}; duration=${duration(row.durationMs)}${row.shared ? '; shared quota' : ''}`)
    lines.push(`  used=${row.usedPct === null ? 'unknown' : `${row.usedPct}%`}; remaining=${row.remainingPct === null ? 'unknown' : `${row.remainingPct}%`}; ${row.flags.join(',')}${row.errorReason ? ` (${row.errorReason})` : ''}`)
    lines.push(`  reset=${iso(row.resetsAt)}; collected=${iso(row.collectedAt)}`, '')
  }
  if (!rows.length) lines.push('No account quota measurements available.', '')
  for (const notice of notices) lines.push(`! ${notice}`)
  return lines.join('\n') + '\n'
}
function run(command, args, timeout = 60000, allowFailure = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: os.tmpdir(), env: process.env, detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe'] })
    let output = '', bytes = 0, stopped = false
    const stop = () => {
      if (!child.pid) return
      try { process.platform === 'win32' ? child.kill() : process.kill(-child.pid, 'SIGTERM') } catch {}
    }
    const finish = (error, value) => { if (stopped) return; stopped = true; clearTimeout(timer); error ? reject(error) : resolve(value) }
    const timer = setTimeout(() => { stop(); finish(new Error('command timed out')) }, timeout)
    child.stdout.on('data', chunk => { bytes += chunk.length; if (bytes > 4 * 1024 * 1024) { stop(); finish(new Error('output too large')) } else output += chunk })
    child.stderr.on('data', () => {}) // Raw provider errors can contain account/credential data.
    child.on('error', () => finish(new Error('command unavailable')))
    child.on('close', code => code === 0 || (allowFailure && output) ? finish(null, output) : finish(new Error('command failed')))
  })
}
function readCache(file) { return JSON.parse(fs.readFileSync(file, 'utf8')) }
function collectorCommand(home, explicit) {
  const entry = explicit || process.env.AGENT_USAGE_COLLECTOR || path.join(home, '.local/lib/agent-usage/collect.sh')
  const bundle = /\.[cm]?js$/.test(entry) ? entry : path.join(path.dirname(entry), 'collector.cjs')
  // Old CLI silently ignores unknown flags and starts history/model work, even --help.
  // Inspect before invoking any discovery command; never probe that unsafe entrypoint.
  const source = fs.readFileSync(bundle, 'utf8')
  if (!source.includes('--limits-only') || !source.includes('--capabilities')) throw new Error('native collector upgrade required')
  return /\.[cm]?js$/.test(entry) ? [process.execPath, [entry]] : [entry, []]
}
async function main(args) {
  let collector
  const flagsOnly = []
  const allowed = { '--refresh': true, '--cache-only': true, '--json': true, '--wait': true, '--no-wait': true, '--help': true, '-h': true }
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--collector') {
      if (collector || !args[i + 1] || args[i + 1].startsWith('--') || !path.isAbsolute(args[i + 1])) throw new Error('invalid --collector')
      collector = args[++i]
    } else {
      if (!Object.hasOwn(allowed, args[i])) throw new Error('invalid arguments; see --help')
      flagsOnly.push(args[i])
    }
  }
  args = flagsOnly
  if ((args.includes('--refresh') && args.includes('--cache-only')) || (args.includes('--wait') && args.includes('--no-wait')) || (args.includes('--wait') && args.includes('--json'))) throw new Error('invalid arguments; see --help')
  if (args.includes('--help') || args.includes('-h')) {
    process.stdout.write('Usage: agent-usage [--refresh | --cache-only] [--json] [--wait | --no-wait] [--collector ABSOLUTE-PATH]\nDefault: live OMP limits plus existing native Claude/Codex quota cache.\n--refresh: invalidate OMP cache and force limits-only native collection.\n--cache-only: native cache only; no provider request.\n--wait: keep popup until Enter (automatic on interactive terminals).\n--collector: use an upgraded managed collector bundle/entrypoint without deployment.\nAGENT_USAGE_HOME: quota cache root (refresh writes account-limits/limits.json).\nNative refresh requires the upgraded managed collector; no history/model work.\nAccount labels are redacted; shared quotas are never added.\n')
    return 0
  }
  const home = os.homedir(), directory = process.env.AGENT_USAGE_HOME || path.join(home, '.cache/agent-usage')
  const freshFile = path.join(directory, 'account-limits/limits.json'), commonFile = path.join(directory, 'limits.json')
  let cache = null, rows = [], notices = [], failed = false
  const existingFile = fs.existsSync(freshFile) ? freshFile : commonFile
  try { cache = readCache(existingFile); cacheEntries(cache) } catch { if (!args.includes('--refresh')) { notices.push('Native quota cache unavailable or invalid.'); failed = true } }
  if (args.includes('--refresh')) {
    try {
      const [command, prefix] = collectorCommand(home, collector)
      const capabilities = JSON.parse(await run(command, prefix.concat('--capabilities')))
      if (capabilities.version !== 1 || capabilities.limitsOnly !== true || capabilities.force !== true || capabilities.includesDisabledNativeSources !== true) throw new Error('native refresh unsupported')
      const before = fs.existsSync(freshFile) ? readCache(freshFile) : null
      const result = JSON.parse(await run(command, prefix.concat(['--limits-only', '--force', '--directory', path.dirname(freshFile)]), 240000, true))
      cache = readCache(freshFile)
      const advanced = refreshedSources(before, cache)
      if (result.skipped || !advanced.size || [...advanced.values()].some(value => !value)) { notices.push('Native refresh incomplete: some sources did not produce a newer collection; inspect stale/error rows.'); failed = true }
      if (result.failedSources > 0) { notices.push('Native quota request failed for one or more profiles; authenticate the intended profile if required (no auth copied or changed).'); failed = true }
    } catch {
      notices.push('Native refresh failed/unavailable. Upgrade the managed collector with limits-only/force support; no unsafe legacy collection was started.'); failed = true
    }
  }
  if (cache) { try { rows.push(...cacheRows(cache, Date.now())) } catch { notices.push('Native quota cache schema invalid.'); failed = true } }
  if (!args.includes('--cache-only')) {
    try {
      const omp = process.env.AGENT_USAGE_OMP || 'omp'
      if (args.includes('--refresh')) await run(omp, ['usage', 'invalidate', '--no-extensions'])
      rows.push(...ompRows(JSON.parse(await run(omp, ['usage', '--json', '--redact', '--no-extensions'])), Date.now()))
    } catch { notices.push('OMP account usage retrieval failed; native rows remain independent.'); failed = true }
  }
  if (rows.some(row => row.flags.includes('error'))) failed = true
  const output = { version: 1, generatedAt: Date.now(), rows, notices }
  process.stdout.write(args.includes('--json') ? JSON.stringify(output, null, 2) + '\n' : render(rows, notices))
  const wait = args.includes('--wait') || (!args.includes('--no-wait') && !args.includes('--json') && process.stdin.isTTY && process.stdout.isTTY)
  if (wait) {
    if (!process.stdin.isTTY) throw new Error('--wait requires an interactive terminal')
    const terminal = readline.createInterface({ input: process.stdin, output: process.stdout })
    await new Promise(resolve => { terminal.question('Press Enter to close. ', () => { terminal.close(); resolve() }); terminal.once('close', resolve) })
  }
  return failed ? 1 : 0
}
module.exports = { cacheRows, ompRows, render, refreshedSources, main }
