#!/usr/bin/env bash
# mad-run の dry-run が plan、role catalog、config、availability を検証し、外部操作を行わないことを検証する。
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
plan="$tmp/plan.md"
config="$root/private_dot_local/private_share/agent-config/agent-config.sample.json"
snapshot="$tmp/snapshot.json"
marker="$tmp/live-call"
state="$tmp/state"
cat > "$snapshot" <<'SNAPSHOT'
{
  "version": 1,
  "type": "paseo-availability-snapshot",
  "providers": {
    "claude": { "available": true, "modeIds": ["auto"] },
    "codex": { "available": true, "modeIds": ["auto"] },
    "opencode": { "available": true, "modeIds": ["auto"] },
    "pi": { "available": true, "modeIds": ["auto"] }
  },
  "models": {
    "claude": [
      { "id": "sample-think", "thinkingOptionIds": ["high"] },
      { "id": "sample-deep", "thinkingOptionIds": ["max"] }
    ],
    "codex": [
      { "id": "sample-light", "thinkingOptionIds": ["medium"] },
      { "id": "sample-work", "thinkingOptionIds": ["high"] },
      { "id": "sample-think", "thinkingOptionIds": ["high"] },
      { "id": "sample-deep", "thinkingOptionIds": ["max"] }
    ],
    "opencode": [],
    "pi": []
  }
}
SNAPSHOT
cat > "$plan" <<'PLAN'
# Paseo MAD plan

## Task 1: inspect

**Complexity:** routine
**Work class:** routine
**Files:**
- Modify: `one.txt`

**Depends on:** none

## Task 2: prepare

**Complexity:** complex
**Work class:** integration
**Files:**
- Modify: `two.txt`

**Depends on:** none

## Task 3: integrate

**Complexity:** critical
**Work class:** architectural
**Files:**
- Modify: `three.txt`

**Depends on:** Task 1, Task 2
PLAN

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/usr/bin/env bash\nprintf "%s" called > "$MAD_DRY_RUN_MARKER"\n' > "$stub/paseo"
chmod +x "$stub/paseo"

output=""
status=0
output="$(AGENT_ENV= MAD_STATE_DIR="$state" MAD_DRY_RUN_MARKER="$marker" MAD_ROLE_ROOT="$root/.chezmoitemplates/agent-defs" \
  MAD_GENERATOR="$root/private_dot_local/bin/executable_agent-config" PATH="$stub:$PATH" \
  "$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-run" \
  --dry-run --plan "$plan" --project "$root" --run-id dry-run-test \
  --backend paseo-mcp --config "$config" --snapshot "$snapshot" 2>"$tmp/stderr")" || status=$?
assert_eq "$status" 0 'dry-run は成功する'
assert_eq "$(cat "$tmp/stderr")" '' 'dry-run は stderr を出さない'

if node - "$output" "$root" <<'NODE'
const value = JSON.parse(process.argv[2])
const root = process.argv[3]
if (value.version !== 1 || value.type !== 'mad-dry-run') throw new Error('dry-run type is wrong')
if (value.runId !== 'dry-run-test' || value.recipe !== 'delivery') throw new Error('dry-run identity is wrong')
if (value.backend !== 'paseo-mcp' || value.liveCalls !== 0 || value.applyCalls !== 0) throw new Error('dry-run side effects are wrong')
if (value.project !== root) throw new Error('dry-run project is wrong')
if (!Array.isArray(value.launches) || value.launches.length < 5) throw new Error('config-aware launches are missing')
for (const launch of value.launches) {
  if (launch.status !== 'ok' || launch.provider === undefined || launch.model === undefined) {
    throw new Error(`launch was not resolved: ${JSON.stringify(launch)}`)
  }
}
if (!value.launches.some((launch) => launch.role === 'plan-auditor')) throw new Error('plan-auditor launch is missing')
if (!value.launches.some((launch) => launch.role === 'final-reviewer')) throw new Error('final-reviewer launch is missing')
if (JSON.stringify(value.waves.map((wave) => [wave.wave, wave.tasks.map((task) => task.number)])) !== JSON.stringify([[1, [1, 2]], [2, [3]]])) {
  throw new Error(`waves are wrong: ${JSON.stringify(value.waves)}`)
}
const task3 = value.waves[1].tasks[0]
if (task3.complexity !== 'critical' || task3.workClass !== 'architectural') throw new Error('task metadata is wrong')
for (const role of ['plan-auditor', 'implementer', 'task-reviewer', 're-reviewer', 'final-reviewer']) {
  if (!value.roles[role].prompt.endsWith(`/agent-defs/prompts/${role}.md`)) throw new Error(`prompt path is wrong: ${role}`)
  if (!value.roles[role].schema.endsWith(`/agent-defs/schemas/${role}.json`)) throw new Error(`schema path is wrong: ${role}`)
}
NODE
then
  _pass 'dry-run の plan/wave/role 出力が正しい'
else
  _fail 'dry-run の plan/wave/role 出力が正しい'
fi

if [ ! -e "$marker" ] && [ ! -e "$state" ]; then
  _pass 'dry-run は Paseo と state directory を作らない'
else
  _fail 'dry-run は Paseo と state directory を作らない'
fi

status=0
AGENT_ENV= MAD_STATE_DIR="$state" MAD_ROLE_ROOT="$root/.chezmoitemplates/agent-defs" \
  MAD_GENERATOR="$root/private_dot_local/bin/executable_agent-config" PATH="$stub:$PATH" \
  "$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-run" \
  --plan "$plan" --project "$root" --run-id missing-dry-run \
  --backend paseo-mcp --config "$config" --snapshot "$snapshot" >/dev/null 2>"$tmp/invalid-stderr" || status=$?
assert_eq "$status" 2 'dry-run なしは拒否する'

unavailable="$tmp/unavailable.json"
node - "$snapshot" "$unavailable" <<'NODE'
const fs = require('node:fs')
const source = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
source.providers.codex.available = false
source.models.codex = []
fs.writeFileSync(process.argv[3], JSON.stringify(source))
NODE
status=0
AGENT_ENV= MAD_STATE_DIR="$state" MAD_ROLE_ROOT="$root/.chezmoitemplates/agent-defs" \
  MAD_GENERATOR="$root/private_dot_local/bin/executable_agent-config" PATH="$stub:$PATH" \
  "$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-run" \
  --dry-run --plan "$plan" --project "$root" --run-id unavailable \
  --backend paseo-mcp --config "$config" --snapshot "$unavailable" >/dev/null 2>"$tmp/unavailable-stderr" || status=$?
assert_eq "$status" 2 'availability 不足の dry-run は停止する'
assert_contains "$(cat "$tmp/unavailable-stderr")" 'launch unresolved' \
  'availability 不足を launch unresolved として報告する'

assert_summary
