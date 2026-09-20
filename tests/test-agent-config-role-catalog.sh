#!/usr/bin/env bash
# agentRoles、prompt/schema、resolver の role catalog を同じ正本から検証する。
set -u

source "$(dirname "$0")/lib/assert.sh"

if node - "$CHEZMOI_SOURCE" <<'NODE'
const fs = require('node:fs')
const path = require('node:path')
const source = process.argv[2]
const configPath = path.join(source, 'private_dot_local/private_share/agent-config/agent-config.sample.json')
const { validateConfig } = require(path.join(source, 'private_dot_local/private_share/agent-config/config-validator.js'))
const { resolveDispatch } = require(path.join(source, 'private_dot_local/private_share/agent-config/resolver.js'))

const config = validateConfig(fs.readFileSync(configPath, 'utf8')).config
const requiredRoles = [
  'implementer',
  'task-reviewer',
  'plan-auditor',
  'intake-router',
  'architectural-implementer',
  'escalation-judge',
  're-reviewer',
  'final-reviewer',
  'spec-author',
  'plan-author',
  'synthesizer',
  'reviewer',
  'researcher',
  'review-synthesizer',
]
const promptDir = path.join(source, '.chezmoitemplates/agent-defs/prompts')
const schemaDir = path.join(source, '.chezmoitemplates/agent-defs/schemas')
const missing = []
for (const role of requiredRoles) {
  if (!Object.prototype.hasOwnProperty.call(config.agentRoles, role)) missing.push(`config:${role}`)
  if (!fs.existsSync(path.join(promptDir, `${role}.md`))) missing.push(`prompt:${role}`)
  if (!fs.existsSync(path.join(schemaDir, `${role}.json`))) missing.push(`schema:${role}`)
  try {
    resolveDispatch(config, {
      project: source,
      role,
      provenance: 'catalog-test',
      complexity: 'routine',
      workClass: 'routine',
      round: 0,
    })
  } catch (error) {
    missing.push(`resolve:${role}:${error instanceof Error ? error.message : String(error)}`)
  }
}
if (missing.length > 0) throw new Error(missing.join('\n'))
NODE
then
  _pass 'active role catalog has config, prompt, schema, and resolver entries'
else
  _fail 'active role catalog has config, prompt, schema, and resolver entries'
fi

assert_summary
