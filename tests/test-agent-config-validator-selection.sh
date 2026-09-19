#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SHARE="$ROOT/private_dot_local/private_share/agent-config"

out="$(node -e '
const fs = require("node:fs")
const { validateConfig } = require(process.argv[1])
const raw = fs.readFileSync(process.argv[2], "utf8")
const { config } = validateConfig(raw)
console.log(config.version, Object.keys(config.selection).length)
' "$SHARE/config-validator.js" "$SHARE/agent-config.sample.json")"
assert_eq "$out" "2 4" "config-validator: v2 の sample を受け入れる"

status=0
node -e '
const { validateConfig } = require(process.argv[1])
const config = JSON.parse(require("node:fs").readFileSync(process.argv[2], "utf8"))
config.agentRoles.implementer.duty = "unknown"
try {
  validateConfig(JSON.stringify(config))
  process.exit(0)
} catch (error) {
  process.exit(error.exitCode || 1)
}
' "$SHARE/config-validator.js" "$SHARE/agent-config.sample.json" 2>/dev/null || status=$?
assert_eq "$status" "2" "config-validator: 未知の duty を拒む"

status=0
node -e '
const { validateConfig } = require(process.argv[1])
const config = JSON.parse(require("node:fs").readFileSync(process.argv[2], "utf8"))
delete config.environments.lab.selection
try {
  validateConfig(JSON.stringify(config))
  process.exit(0)
} catch (error) {
  console.error(error)
  process.exit(error.exitCode || 1)
}
' "$SHARE/config-validator.js" "$SHARE/agent-config.sample.json" 2>/dev/null || status=$?
assert_eq "$status" "0" "config-validator: environment の selection 省略を受け入れる"
assert_summary
