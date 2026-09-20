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

const configValue = JSON.parse(fs.readFileSync(path.join(source, 'private_dot_local/private_share/agent-config/agent-config.sample.json'), 'utf8'))
configValue.routingSelection = {
  candidates: [{ provider: 'codex', model: 'sample-light', effort: 'medium', features: {} }]
}
configValue.agentRoles['intake-router'] = {
  duty: 'review',
  launchPolicy: 'routing',
  access: 'read',
  description: '依頼を task packet に分類する',
  artifactContract: 'task-packet-v1',
  deliveryDuties: []
}

const config = validateConfig(JSON.stringify(configValue)).config
const dispatch = resolveDispatch(config, {
  project: source,
  role: 'intake-router',
  provenance: 'route',
  complexity: 'simple',
  round: 0
})
const launch = resolvePaseoLaunch(dispatch, {
  version: 1,
  type: 'paseo-availability-snapshot',
  providers: { codex: { available: true, modeIds: ['auto'] } },
  models: { codex: [{ id: 'sample-light', thinkingOptionIds: ['medium'] }] }
})
if (launch.provider !== 'codex' || launch.model !== 'sample-light' || launch.thinkingOptionId !== 'medium') {
  throw new Error(`routing launch is wrong: ${JSON.stringify(launch)}`)
}
NODE
then
  _pass 'routing policy resolves an intake-router launch'
else
  _fail 'routing policy resolves an intake-router launch'
fi
assert_summary
