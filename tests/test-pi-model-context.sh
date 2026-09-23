#!/usr/bin/env bash
# Pi の OpenAI Codex model overrides が全ての GPT-6 model に適用されることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

models="$CHEZMOI_SOURCE/private_dot_pi/agent/models.json"
if node - "$models" <<'NODE'
const fs = require('node:fs')
const file = process.argv[2]
const expected = [
  'gpt-5.6-luna',
  'gpt-5.6-sol',
  'gpt-5.6-terra',
  'gpt-6-astra',
  'gpt-6-luna',
  'gpt-6-sol',
]

if (!fs.existsSync(file)) {
  console.error(`Pi model overrides are missing: ${file}`)
  process.exit(1)
}

const config = JSON.parse(fs.readFileSync(file, 'utf8'))
const overrides = config.providers?.['openai-codex']?.modelOverrides ?? {}
const missing = expected.filter((id) => overrides[id]?.contextWindow !== 828400)
if (missing.length > 0) {
  console.error(`Expected contextWindow=828400 for: ${missing.join(', ')}`)
  process.exit(1)
}
NODE
then
  pass 'Pi: GPT-5.6 / GPT-6 Codex models use the configured 828400-token context window'
else
  fail_check 'Pi: GPT-5.6 / GPT-6 Codex models use the configured 828400-token context window'
fi

assert_summary
