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
sample.selection.review.complex.candidates[0].features = {}
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

function launch(workClass) {
  const dispatch = resolveDispatch(config, {
    project: source,
    role: 'task-reviewer',
    provenance: 'mad-review',
    complexity: 'critical',
    workClass,
    round: 0,
    backend: 'paseo-cli'
  })
  return resolvePaseoLaunch(dispatch, snapshot)
}

const mechanical = launch('mechanical')
if (mechanical.model !== 'sample-light') throw new Error(`mechanical reviewer route is wrong: ${JSON.stringify(mechanical)}`)
const integration = launch('integration')
if (integration.model !== 'sample-think') throw new Error(`integration reviewer route is wrong: ${JSON.stringify(integration)}`)
NODE
then
  _pass 'reviewer model routing follows work class on paseo-cli'
else
  _fail 'reviewer model routing follows work class on paseo-cli'
fi
assert_summary
