#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SHARE="$ROOT/private_dot_local/private_share/agent-config"

assert_eq "$(test -f "$SHARE/paseo-exporter.js" && echo yes || echo no)" "no" "paseo-exporter.js が消えている"
for name in paseo-assert paseo-providers paseo-launch; do
  assert_eq "$(test -f "$SHARE/$name.js" && echo yes || echo no)" "yes" "$name.js がある"
done

out="$(node -e '
const fs = require("node:fs")
const { validateConfig } = require(process.argv[1])
const { resolveExport, resolveDispatch } = require(process.argv[2])
const { materializePaseoProviders } = require(process.argv[3])
const { resolvePaseoLaunch, CANDIDATE_REASONS } = require(process.argv[4])
const { config } = validateConfig(fs.readFileSync(process.argv[5], "utf8"))
const materialized = materializePaseoProviders(resolveExport(config))
const dispatch = resolveDispatch(config, {
  project: process.argv[6], role: "implementer", provenance: "mad-dispatch",
  complexity: "standard", environment: "primary",
})
const snapshot = {
  version: 1, type: "paseo-availability-snapshot",
  providers: { codex: { available: true, modeIds: ["auto"] } },
  models: { codex: [{ id: "sample-work", thinkingOptionIds: ["high"] }] },
}
const launch = resolvePaseoLaunch(dispatch, snapshot)
console.log(Object.keys(materialized).sort().join(","),
  Object.keys(launch).sort().join(","),
  launch.duty, launch.complexity, launch.requestedComplexity, launch.thinkingOptionId,
  CANDIDATE_REASONS.includes("backend_unsupported"))
' "$SHARE/config-validator.js" "$SHARE/resolver.js" "$SHARE/paseo-providers.js" \
  "$SHARE/paseo-launch.js" "$SHARE/agent-config.sample.json" "$ROOT")"
assert_eq "$out" \
  "providers,warnings complexity,duty,environment,features,modeId,model,provider,requestedComplexity,status,thinkingOptionId,type,version,warnings implement standard standard high true" \
  "paseo-launch: launch spec の 13 key"
assert_summary
