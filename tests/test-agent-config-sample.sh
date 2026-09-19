#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SHARE="$ROOT/private_dot_local/private_share/agent-config"

out="$(node -e '
const sample = require(process.argv[1])
const schema = require(process.argv[2])
const duties = ["author", "implement", "review", "synthesize"]
const complexities = ["simple", "routine", "complex", "critical"]
if (sample.tiers !== undefined) throw new Error("sample に tiers が残っている")
const slots = duties.flatMap((duty) => complexities.map((c) => `${duty}.${c}`))
const actual = Object.entries(sample.selection).flatMap(([duty, byComplexity]) =>
  Object.keys(byComplexity).map((c) => `${duty}.${c}`))
if (actual.sort().join(",") !== slots.sort().join(",")) throw new Error("sample の枠が 16 でない")
for (const provider of Object.values(sample.providers)) {
  if (JSON.stringify(provider.backends) !== JSON.stringify(["paseo"])) throw new Error("backends が paseo でない")
}
console.log(sample.version, schema.properties.version.const, sample.defaults.complexity,
  sample.defaults.tier === undefined, sample.agentRoles.implementer.duty)
' "$SHARE/agent-config.sample.json" "$SHARE/agent-config.schema.json")"
assert_eq "$out" "2 2 routine true implement" "agent-config sample: v2 の selection と duty"
assert_summary
