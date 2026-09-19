#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
CLI="$ROOT/private_dot_local/bin/executable_agent-config"
SHARE="$ROOT/private_dot_local/private_share/agent-config"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

assert_eq "$(test -f "$ROOT/private_dot_local/bin/executable_generate-paseo-config" && echo yes || echo no)" "no" \
  "generate-paseo-config が消えている"

cat > "$TMP/snapshot.json" <<'JSON'
{"version":1,"type":"paseo-availability-snapshot",
 "providers":{"codex":{"available":true,"modeIds":["auto"]},"claude":{"available":true,"modeIds":["auto"]}},
 "models":{"codex":[{"id":"sample-work","thinkingOptionIds":["high"]},{"id":"sample-light","thinkingOptionIds":["medium"]}],
           "claude":[{"id":"sample-deep","thinkingOptionIds":["max"]},{"id":"sample-think","thinkingOptionIds":["high"]}]}}
JSON

run() {
  env -u AGENT_ENV -u AGENT_ENV_SESSION node "$CLI" --input "$SHARE/agent-config.sample.json" resolve \
    --project "$ROOT" --role implementer --environment primary \
    --snapshot "$TMP/snapshot.json" "$@"
}

out="$(run --provenance mad-fix --round 2 --complexity standard)"
assert_eq "$(printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.complexity,j.requestedComplexity)})')" \
  "complex standard" "resolve: mad-fix round 2 で引き上げる"

out="$(run --provenance mad-review --round 2 --complexity standard)"
assert_eq "$(printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.complexity,j.requestedComplexity)})')" \
  "standard standard" "resolve: mad-review は引き上げない"

out="$(run --provenance mad-dispatch)"
assert_eq "$(printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.complexity,j.warnings.filter(w=>w.includes("complexity missing")).length)})')" \
  "standard 1" "resolve: --complexity 省略で defaults.complexity に落ちる"

status=0
env -u AGENT_ENV -u AGENT_ENV_SESSION node "$CLI" --input "$SHARE/agent-config.sample.json" >/dev/null 2>&1 || status=$?
assert_eq "$status" "2" "subcommand 無しは exit 2"
assert_summary
