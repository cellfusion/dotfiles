#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SHARE="$ROOT/private_dot_local/private_share/agent-config"

out="$(node -e '
const c = require(process.argv[1])
console.log(c.MAD_LAUNCH_KEYS.length, c.MAD_LAUNCH_KEYS.includes("profileName"), c.MAD_LAUNCH_KEYS.includes("requestedComplexity"))
' "$SHARE/mad-contract.js")"
assert_eq "$out" "13 false true" "mad-contract: launch key set が 13"

out="$(node -e '
const c = require(process.argv[1])
const launch = {
  version: 1, type: "mad-launch-spec", status: "ok", environment: "primary",
  duty: "implement", complexity: "complex", requestedComplexity: "routine",
  provider: "codex", model: "m", modeId: "auto", thinkingOptionId: "high",
  features: {}, warnings: [],
}
c.assertMadLaunchSpecV1(launch, {})
const log = { version: 1, type: "mad-call-log", events: [{
  seq: 0, operation: "resolve", exitCode: 0, outputType: "mad-launch-spec", stdoutDocuments: 1,
  environment: "primary", role: "implementer", duty: "implement", complexity: "complex",
  requestedComplexity: "routine", provider: "codex", model: "m", effort: "high", features: {},
}] }
c.assertMadCallLogV1(log)
let rejected = false
try {
  c.assertMadCallLogV1({ version: 1, type: "mad-call-log", events: [{ seq: 0, operation: "resolve", exitCode: 0, outputType: "mad-launch-spec", stdoutDocuments: 1 }] })
} catch { rejected = true }
console.log("ok", rejected)
' "$SHARE/mad-contract.js")"
assert_eq "$out" "ok true" "mad-contract: resolve event の 12 key"
assert_summary
