#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SHARE="$ROOT/private_dot_local/private_share/agent-config"

out="$(node -e '
const fs = require("node:fs")
const { validateConfig } = require(process.argv[1])
const { resolveExport } = require(process.argv[2])
const { config } = validateConfig(fs.readFileSync(process.argv[3], "utf8"))
const exported = resolveExport(config)
const one = exported.resolutions.find((r) => r.environment === "lab" && r.duty === "implement" && r.complexity === "standard")
const other = exported.resolutions.find((r) => r.environment === "lab" && r.duty === "implement" && r.complexity === "routine")
console.log(exported.resolutions.length,
  Object.keys(one).sort().join(","),
  Object.keys(one.candidates[0]).sort().join(","),
  one.candidates[0].model,
  other.warnings[0],
  exported.providerFamilies[0].backends.join(","))
' "$SHARE/config-validator.js" "$SHARE/resolver.js" "$SHARE/agent-config.sample.json")"
assert_eq "$out" \
  "24 candidates,complexity,duty,environment,notes,warnings effort,family,features,model sample-lab-work selection slot missing: lab/implement/routine; using common selection paseo" \
  "resolver: 12 枠 x 2 環境の export"

escalated="$(node -e '
const fs = require("node:fs")
const { validateConfig } = require(process.argv[1])
const { resolveDispatch } = require(process.argv[2])
const { config } = validateConfig(fs.readFileSync(process.argv[3], "utf8"))
const call = (provenance, round) => resolveDispatch(config, {
  project: process.argv[4], role: "implementer", provenance, round, complexity: "standard",
}).selection
const a = call("mad-fix", 2)
const b = call("mad-fix", 1)
const c = call("mad-review", 2)
console.log(a.complexity, a.requestedComplexity, b.complexity, c.complexity)
' "$SHARE/config-validator.js" "$SHARE/resolver.js" "$SHARE/agent-config.sample.json" "$ROOT")"
assert_eq "$escalated" "complex standard standard standard" "resolver: round 2 の mad-fix だけ引き上げる"
omitted="$(node -e '
const fs = require("node:fs")
const { validateConfig } = require(process.argv[1])
const { resolveExport } = require(process.argv[2])
const raw = JSON.parse(fs.readFileSync(process.argv[3], "utf8"))
delete raw.environments.lab.selection
const { config } = validateConfig(JSON.stringify(raw))
const exported = resolveExport(config)
const lab = exported.resolutions.filter((r) => r.environment === "lab")
const one = lab.find((r) => r.duty === "implement" && r.complexity === "standard")
console.log(lab.length, one.candidates[0].model, one.warnings.length)
' "$SHARE/config-validator.js" "$SHARE/resolver.js" "$SHARE/agent-config.sample.json")"
assert_eq "$omitted" "12 sample-work 1" \
  "resolver: 環境の selection 省略は共通の枠へ落ちる"

assert_summary
