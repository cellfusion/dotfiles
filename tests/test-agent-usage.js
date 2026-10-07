'use strict'
const { test } = require('node:test')
const assert = require('node:assert/strict')
const { cacheRows, ompRows, render, refreshedSources } = require('../private_dot_local/private_share/agent-usage/runtime.js')
const now = 1791210000000

test('old successful quotas stay stale and absent windows never become zero', () => {
  const rows = cacheRows({ version: 1, updatedAt: now / 1000, environments: [{ name: 'work@example.com', agents: [{ agent: 'claude', collectedAt: now / 1000 - 132 * 3600, weekStatus: 'ok', week: { usedPct: 0, resetsAt: now / 1000 - 1 }, sessionStatus: 'missing', session: null, lastError: 'secret' }] }] }, now)
  assert.equal(rows[0].usedPct, 0)
  assert.deepEqual(rows[0].flags, ['stale', 'error'])
  assert.equal(rows[1].usedPct, null)
  assert.equal(rows[0].durationMs, null)
  assert.equal(rows[0].account, 'account-unknown')
  assert.doesNotMatch(render(rows, []), /work@example|secret|5 hours|7 days/)
})

test('independent sources and shared OMP quotas are never aggregated', () => {
  const value = { version: 1, environments: [], sources: [1, 2].map(n => ({ sourceId: `native-${n}`, environments: ['default'], agent: 'codex', collectedAt: now / 1000, weekStatus: 'ok', week: { usedPct: 30, resetsAt: now / 1000 + 1000, durationMs: 604800000 }, sessionStatus: 'missing', session: null })) }
  const rows = cacheRows(value, now)
  assert.equal(rows.length, 4)
  assert.notEqual(rows[0].source, rows[2].source)
  const omp = ompRows({ reports: [{ provider: 'openai-codex', fetchedAt: now, metadata: { email: 'raw@example.com' }, limits: [{ label: '7 days', scope: { shared: true }, window: { durationMs: 604800000, resetsAt: now + 100000 }, amount: { usedFraction: 0.08 }, status: 'ok' }] }], accountsWithoutUsage: [] }, now)
  assert.equal(omp[0].usedPct, 8)
  assert.equal(omp[0].account, 'account-1')
  assert.equal(omp[0].shared, true)
  assert.doesNotMatch(render(omp.concat(rows), []), /raw@example|total|summed/i)
})

test('refresh proves source collection timestamps advanced, not global cache timestamp', () => {
  const before = { version: 1, sources: [{ sourceId: 'one', agent: 'claude', environments: ['default'], collectedAt: 10 }], environments: [] }
  const after = { ...before, updatedAt: 500 }
  assert.equal(refreshedSources(before, after).get('one'), false)
  after.sources = [{ ...before.sources[0], collectedAt: 20 }]
  assert.equal(refreshedSources(before, after).get('one'), true)
})

test('future timestamps and past resets do not appear fresh', () => {
  const rows = ompRows({ reports: [{ provider: 'anthropic', fetchedAt: now + 100000, limits: [{ amount: { remainingFraction: 0.2 }, window: { resetsAt: now - 1000 }, status: 'ok' }] }] }, now)
  assert.equal(rows[0].remainingPct, 20)
  assert.ok(rows[0].flags.includes('stale'))
})

test('native auth and throttling failures keep quota unavailable with safe reasons', () => {
  for (const [lastError, reason] of [['claude: auth-rejected', 'auth-required'], ['claude: rate-limited', 'rate-limited']]) {
    const rows = cacheRows({ version: 1, sources: [{ sourceId: 'native-one', agent: 'claude', environments: ['default'], collectedAt: null, week: null, session: null, lastError }], environments: [] }, now)
    assert.equal(rows[0].errorReason, reason)
    assert.equal(rows[0].usedPct, null)
    assert.deepEqual(rows[0].flags, ['error'])
    assert.match(render(rows, []), new RegExp(reason))
  }
})

test('disabled OAuth accounts remain actionable without exposing upstream causes or identity', () => {
  const rows = ompRows({ reports: [], accountsWithoutUsage: [], disabledCredentials: [{
    id: 42, provider: 'anthropic', type: 'oauth', email: 'private@example.com',
    accountId: 'private-account', cause: 'upstream secret-token',
    disabledAtMs: now,
  }] }, now)
  assert.equal(rows.length, 1)
  assert.equal(rows[0].provider, 'anthropic')
  assert.equal(rows[0].usedPct, null)
  assert.equal(rows[0].collectedAt, null)
  assert.equal(rows[0].errorReason, 'auth-required')
  assert.deepEqual(rows[0].flags, ['error'])
  assert.match(render(rows, []), /auth-required/)
  assert.doesNotMatch(JSON.stringify(rows), /private@example|private-account|secret-token|upstream/)
})
