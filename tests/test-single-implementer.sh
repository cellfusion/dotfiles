#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

packet="$tmp/packet.json"
prompt="$tmp/implementer.md"
schema="$tmp/implementer.json"
snapshot="$tmp/snapshot.json"
attempt="$tmp/attempt"

cat > "$packet" <<'JSON'
{
  "route": "single",
  "workClass": "mechanical",
  "role": "implementer",
  "complexity": "simple",
  "goal": "Apply the requested local change",
  "writeScope": ["src/example.ts"],
  "acceptanceCriteria": ["The requested behavior is present"],
  "verification": ["npm test -- src/example.test.ts"],
  "needsBrainstorming": false,
  "needsUserDecision": false,
  "confidence": "high",
  "reason": "The task is local and fully specified"
}
JSON
printf '%s\n' 'implementer prompt' > "$prompt"
printf '%s\n' '{}' > "$schema"
cat > "$snapshot" <<'JSON'
{
  "version": 1,
  "type": "paseo-availability-snapshot",
  "providers": { "codex": { "available": true, "modeIds": ["auto"] } },
  "models": { "codex": [{ "id": "sample-light", "thinkingOptionIds": ["medium"] }] }
}
JSON

script="$root/private_dot_agents/skills/task-routing/scripts/executable_single-implementer"
if AGENT_ENV=primary "$script" prepare \
  --packet "$packet" \
  --config "$root/private_dot_local/private_share/agent-config/agent-config.sample.json" \
  --project "$root" \
  --snapshot "$snapshot" \
  --workspace-id workspace-test \
  --attempt-dir "$attempt" \
  --role-prompt "$prompt" \
  --role-schema "$schema" \
  --title 'single implementer test' >/tmp/single-implementer-output; then
  _pass 'single implementer prepare succeeds'
else
  _fail 'single implementer prepare succeeds'
fi

if [ -f "$attempt/single-create.json" ]; then
  _pass 'single implementer create request exists'
else
  _fail 'single implementer create request exists'
fi

if [ -f "$attempt/single-create.json" ]; then
  request="$(cat "$attempt/single-create.json")"
  assert_contains "$request" '"provider":"codex/sample-light"' 'single request uses resolved provider/model'
  assert_contains "$request" 'workspace-test' 'single request uses the supplied workspace'
  assert_contains "$request" "$packet" 'single request references the packet path'
  assert_eq "$(stat -f '%Lp' "$attempt/single-create.json" 2>/dev/null || stat -c '%a' "$attempt/single-create.json")" 600 \
    'single request is private'
fi

assert_summary
