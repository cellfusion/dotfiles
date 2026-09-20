#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

if node - "$CHEZMOI_SOURCE" <<'NODE'
const path = require('node:path')
const fs = require('node:fs')
const source = process.argv[2]
const { validateConfig } = require(path.join(source, 'private_dot_local/private_share/agent-config/config-validator.js'))
const { resolveDispatch } = require(path.join(source, 'private_dot_local/private_share/agent-config/resolver.js'))
const { resolvePaseoLaunch } = require(path.join(source, 'private_dot_local/private_share/agent-config/paseo-launch.js'))

const sample = JSON.parse(fs.readFileSync(path.join(source, 'private_dot_local/private_share/agent-config/agent-config.sample.json'), 'utf8'))
sample.attemptPolicy = {
  implement: {
    simple: {
      levels: [
        { candidates: [{ provider: 'codex', model: 'sample-light', effort: 'medium', features: {} }] },
        { candidates: [{ provider: 'codex', model: 'sample-work', effort: 'high', features: { fast_mode: true } }] },
        { candidates: [{ provider: 'claude', model: 'sample-think', effort: 'high', features: { fast_mode: false } }] }
      ]
    }
  }
}

const config = validateConfig(JSON.stringify(sample)).config
const snapshot = {
  version: 1,
  type: 'paseo-availability-snapshot',
  providers: {
    codex: { available: true, modeIds: ['auto'] },
    claude: { available: true, modeIds: ['auto'] }
  },
  models: {
    codex: [
      { id: 'sample-light', thinkingOptionIds: ['medium'] },
      { id: 'sample-work', thinkingOptionIds: ['high'] }
    ],
    claude: [{ id: 'sample-think', thinkingOptionIds: ['high'] }]
  }
}

function launch(provenance, round) {
  const dispatch = resolveDispatch(config, {
    project: source,
    role: 'implementer',
    provenance,
    complexity: 'simple',
    round
  })
  return resolvePaseoLaunch(dispatch, snapshot)
}

const initial = launch('mad-dispatch', 0)
if (initial.model !== 'sample-light' || initial.thinkingOptionId !== 'medium') {
  throw new Error(`initial policy level is wrong: ${JSON.stringify(initial)}`)
}

const firstFix = launch('mad-fix', 1)
if (firstFix.model !== 'sample-work' || firstFix.thinkingOptionId !== 'high') {
  throw new Error(`first fix policy level is wrong: ${JSON.stringify(firstFix)}`)
}

const secondFix = launch('mad-fix', 2)
if (secondFix.provider !== 'claude' || secondFix.model !== 'sample-think') {
  throw new Error(`second fix policy level is wrong: ${JSON.stringify(secondFix)}`)
}

const review = launch('mad-review', 2)
if (review.model !== 'sample-light') {
  throw new Error(`review must not consume implementer quality escalation: ${JSON.stringify(review)}`)
}
NODE
then
  _pass 'attempt policy resolves quality levels for dispatch and fix rounds'
else
  _fail 'attempt policy resolves quality levels for dispatch and fix rounds'
fi
assert_summary
