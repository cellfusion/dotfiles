#!/usr/bin/env bash
# mad-progress が run directory だけを読んで進捗・回収・再開を出すことを検査する。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

SCRIPT="$REPO_ROOT/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-progress"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run="$work/state/runs/r1"
mkdir -p "$run/nodes/alive/attempts/a1" "$run/nodes/stale/attempts/a1" \
  "$run/nodes/bare/attempts/a1" "$run/nodes/done/attempts/a1" "$run/nodes/queued/attempts/a1" \
  "$run/nodes/unreadable/attempts/a1" \
  "$run/nodes/unknownkind/attempts/a1"

cat > "$run/state.json" <<'JSON'
{
  "run_id": "r1",
  "recipe": "implement",
  "state": "running",
  "started_at": "2026-09-19T00:00:00Z",
  "completed_nodes": ["done"],
  "adopted_attempts": {"done": "a1"},
  "artifact_paths": ["/Users/x/docs/o/r/plans/2026-09-19-demo.md"],
  "base": "1111111111111111111111111111111111111111"
}
JSON

# JSON として壊れた attempt state。status がこの attempt を落とさないことを検査する。
printf '%s' '{ this is not json' > "$run/nodes/unreadable/attempts/a1/state.json"

cat > "$run/worktrees.json" <<JSON
{
  "alive": {
    "path": "$work/present",
    "branch": "mad/r1/alive",
    "base": "1111111111111111111111111111111111111111",
    "integration": "pending",
    "removed": false,
    "branch_deleted": false
  },
  "stale": {
    "path": "$work/absent",
    "branch": "mad/r1/stale",
    "base": "1111111111111111111111111111111111111111",
    "integration": "pending",
    "removed": false,
    "branch_deleted": false
  }
}
JSON
mkdir -p "$work/present"

cat > "$run/nodes/alive/attempts/a1/state.json" <<'JSON'
{
  "run_id": "r1", "node": "alive", "attempt": "a1", "state": "running",
  "phase": "implement", "phase_state": "running", "next_action": "wait",
  "started_at": "2026-09-19T00:01:00Z", "create_accepted": true, "child_ref": "c1",
  "backend_handle": "ws-1",
  "liveness": {"kind": "child_ref", "heartbeat_at": "2999-01-01T00:00:00Z"}
}
JSON

cat > "$run/nodes/stale/attempts/a1/state.json" <<'JSON'
{
  "run_id": "r1", "node": "stale", "attempt": "a1", "state": "running",
  "phase": "implement", "phase_state": "running", "next_action": "wait",
  "started_at": "2026-09-19T00:01:00Z", "create_accepted": true, "child_ref": "c2",
  "backend_handle": "ws-2",
  "liveness": {"kind": "child_ref", "heartbeat_at": "2000-01-01T00:00:00Z"}
}
JSON

cat > "$run/nodes/bare/attempts/a1/state.json" <<'JSON'
{
  "run_id": "r1", "node": "bare", "attempt": "a1", "state": "running",
  "phase": "implement", "phase_state": "running", "next_action": "wait",
  "started_at": "2026-09-19T00:01:00Z", "create_accepted": true, "child_ref": "c3"
}
JSON

# liveness はあるが kind が pid でも child_ref でもない。判定の根拠が無いので
# bare と同じ扱いになる。
cat > "$run/nodes/unknownkind/attempts/a1/state.json" <<'JSON'
{
  "run_id": "r1", "node": "unknownkind", "attempt": "a1", "state": "running",
  "phase": "implement", "phase_state": "running", "next_action": "wait",
  "started_at": "2026-09-19T00:01:00Z", "create_accepted": true, "child_ref": "c6",
  "liveness": {"kind": "typo", "heartbeat_at": "2000-01-01T00:00:00Z"}
}
JSON

cat > "$run/nodes/done/attempts/a1/state.json" <<'JSON'
{
  "run_id": "r1", "node": "done", "attempt": "a1", "state": "ok",
  "phase": "implement", "phase_state": "ok", "next_action": "adopt",
  "create_accepted": true, "child_ref": "c4"
}
JSON

cat > "$run/nodes/queued/attempts/a1/state.json" <<'JSON'
{"state": "pending", "create_accepted": false}
JSON

# adapter を置いていない PATH で動かし、Paseo の子を起動しないことを確かめる。
# テスト自身が使う cat・head・sed・stat・rm はテスト側の PATH で動かすので、
# PATH の差し替えは mad-progress の起動だけに掛ける。
empty_bin="$work/bin"
mkdir -p "$empty_bin"
for tool in node git ps; do
  resolved="$(command -v "$tool")"
  [ -n "$resolved" ] && ln -sf "$resolved" "$empty_bin/$tool"
done
progress() { env -i "PATH=$empty_bin" "HOME=$work" "$empty_bin/node" "$SCRIPT" "$@"; }

for sub in status reap resume list; do
  progress "$sub" --help >/dev/null 2>&1
  assert_eq "$?" 0 "$sub --help は exit 0 である"
done

progress bogus >/dev/null 2>&1
assert_eq "$?" 2 '未知のサブコマンドは exit 2 である'

progress status --run-dir "$work/nowhere" >/dev/null 2>&1
assert_eq "$?" 2 'state.json を読めない run directory は exit 2 である'

status="$(progress status --run-dir "$run" --json)"
assert_eq "$?" 0 'status は adapter が無い PATH でも exit 0 である'
assert_contains "$status" '"node": "alive"' 'running の attempt を動いている一覧に出す'
assert_contains "$status" "$work/present" 'running の attempt に worktree の path を添える'
assert_contains "$status" '"node": "queued"' 'pending の attempt を止まっている一覧に出す'
# node 名は running の一覧にも出るので、liveness_unknown の中だけを取り出して比べる。
liveness_unknown="$(printf '%s' "$status" | jq -r '[.liveness_unknown[].node] | sort | join(",")')"
assert_eq "$liveness_unknown" 'bare,unknownkind' \
  '判定の根拠が無い attempt だけを liveness_unknown に出す'
assert_contains "$status" '"adopted": true' '採用済みの attempt を終わった一覧に出す'

progress status --run-dir "$run" --write-ledger >/dev/null
ledger="$run/progress.md"
assert_eq "$(head -1 "$ledger")" '# MAD ledger — run: r1' 'progress.md の 1 行目は run ID である'
assert_eq "$(sed -n '2p' "$ledger")" '# plan: /Users/x/docs/o/r/plans/2026-09-19-demo.md' 'progress.md の 2 行目は plan のパスである'
assert_eq "$(stat -f '%Lp' "$ledger")" '600' 'progress.md は mode 0600 である'

reaped="$(progress reap --run-dir "$run")"
assert_eq "$?" 0 'reap は adapter が無い PATH でも exit 0 である'
assert_contains "$reaped" '"node": "stale"' 'heartbeat_at が古い attempt を回収する'
assert_not_contains "$reaped" '"node": "alive"' 'heartbeat_at が新しい attempt は回収しない'
assert_not_contains "$reaped" '"node": "bare"' 'liveness の無い attempt は回収しない'
assert_not_contains "$reaped" '"node": "unknownkind"' '未知の kind の attempt は回収しない'
assert_contains "$(cat "$run/nodes/stale/attempts/a1/state.json")" '"state": "unresolved"' '回収した attempt は unresolved になる'
assert_contains "$(cat "$run/nodes/stale/attempts/a1/state.json")" '"stale_reason"' 'stale_reason を liveness へ書く'
assert_contains "$(cat "$run/nodes/bare/attempts/a1/state.json")" '"state": "running"' 'liveness の無い attempt の state は変わらない'
assert_contains "$(cat "$run/nodes/unknownkind/attempts/a1/state.json")" '"state": "running"' '未知の kind の attempt の state は変わらない'

after="$(progress status --run-dir "$run" --json)"
assert_contains "$after" '"stale_reason"' 'status は reap が書いた stale_reason を読む'

resumed="$(progress resume --run-dir "$run")"
assert_eq "$?" 0 'resume は adapter が無い PATH でも exit 0 である'
assert_contains "$resumed" '"missing": true' '台帳にあって実体が無い worktree に missing を付ける'
assert_contains "$resumed" '"node": "alive"' '台帳のすべての node を一覧に出す'
assert_contains "$resumed" '"unresolved_nodes"' 'resume は unresolved の node を返す'

listed="$(progress list --state-dir "$work/state")"
assert_contains "$listed" 'r1' 'list は run ID を出す'
assert_contains "$listed" 'implement' 'list は recipe を出す'

status_all="$(progress status --run-dir "$run")"
assert_contains "$status_all" 'unreadable/a1' \
  'status: 読めない attempt state を一覧から落とさない'
assert_contains "$status_all" 'unreadable (1)' \
  'status: 読めない attempt の件数を出す'

source_text="$(cat "$SCRIPT")"
assert_not_contains "$source_text" 'create_agent' 'Paseo の子を起動しない'
assert_not_contains "$source_text" 'paseo-mcp-adapter' 'adapter を呼ばない'

assert_summary
