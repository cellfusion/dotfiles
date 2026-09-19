#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SHARE="$ROOT/private_dot_local/private_share/agent-config"

out="$(node -e '
const t = require(process.argv[1])
if (t.TIERS !== undefined) throw new Error("TIERS が残っている")
console.log(t.DUTIES.join(","), t.COMPLEXITIES.join(","), t.PASEO_FIELDS.includes("thinkingOptionId"), t.PASEO_FIELDS.includes("featureValues"))
' "$SHARE/config-types.js")"
assert_eq "$out" "author,implement,review,synthesize simple,routine,complex,critical true true" \
  "config-types: DUTIES と COMPLEXITIES と PASEO_FIELDS"
assert_summary
