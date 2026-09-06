#!/usr/bin/env bash
# 手動 MAD の成果物契約を、Paseo MCP を起動せず実行可能な validator で検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

VALIDATOR="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"
FIXTURE="$(mktemp -d)"
RUN="$FIXTURE/run-01"
trap 'rm -rf "$FIXTURE"' EXIT

validate_run() { bash "$VALIDATOR" "$1" 2>&1; }

mkdir -p "$RUN"
printf '%s\n' '{
  "run_id": "run-01",
  "recipe": "research",
  "state": "ok",
  "phase": "synthesis",
  "phase_state": "ok",
  "next_action": "complete run",
  "current_round": 0,
  "started_at": "2026-09-05T00:00:00Z",
  "finished_at": "2026-09-05T00:01:00Z",
  "backend": "subagent",
  "backend_reason": "Paseo MCP unavailable",
  "parent_decision": "complete",
  "active_nodes": [],
  "completed_nodes": ["research-1", "research-2", "research-3", "synthesis"],
  "adopted_attempts": {
    "research-1": "attempt-002",
    "research-2": "attempt-001",
    "research-3": "attempt-001",
    "synthesis": "attempt-001"
  },
  "artifact_paths": ["REPLACE_WITH_SYNTHESIS_RESULT"]
}' > "$RUN/state.json"

write_attempt_in() {
  local run_dir="$1"
  local node_id="$2"
  local attempt_id="$3"
  local result="$4"
  local run_id
  run_id="$(basename "$run_dir")"
  local attempt_dir="$run_dir/nodes/$node_id/attempts/$attempt_id"
  mkdir -p "$attempt_dir"
  printf '調査指示\n' > "$attempt_dir/prompt.md"
  printf '%s\n' "$result" > "$attempt_dir/result.md"
  printf 'backend log\n' > "$attempt_dir/log.md"
  printf '%s\n' "{
  \"run_id\": \"$run_id\",
  \"node\": \"$node_id\",
  \"attempt\": \"$attempt_id\",
  \"artifact_paths\": [\"$attempt_dir/result.md\"]
}" > "$attempt_dir/handoff.json"
  printf '%s\n' "{
  \"run_id\": \"$run_id\",
  \"node\": \"$node_id\",
  \"attempt\": \"$attempt_id\",
  \"round\": 0,
  \"state\": \"ok\",
  \"phase\": \"child_work\",
  \"phase_state\": \"ok\",
  \"next_action\": \"await parent decision\",
  \"started_at\": \"2026-09-05T00:00:00Z\",
  \"finished_at\": \"2026-09-05T00:01:00Z\",
  \"backend\": \"subagent\",
  \"backend_reason\": \"Paseo MCP unavailable\",
  \"parent_decision\": \"accepted\"
}" > "$attempt_dir/state.json"
}

write_attempt() { write_attempt_in "$RUN" "$@"; }

# 同一 node の再実行は attempt ごとのファイルに分離され、先行結果を上書きしない。
write_attempt research-1 attempt-001 'first result'
write_attempt research-1 attempt-002 'retry result'
write_attempt research-2 attempt-001 'constraint result'
write_attempt research-3 attempt-001 'alternative result'
write_attempt synthesis attempt-001 'synthesis result'
jq --arg result "$RUN/nodes/synthesis/attempts/attempt-001/result.md" \
  '.artifact_paths = [$result]' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "0" "validator: 分離された run と attempt を受け入れる"
assert_contains "$out" "valid manual orchestration run" "validator: 成功した run を報告する"
assert_eq "$(cat "$RUN/nodes/research-1/attempts/attempt-001/result.md")" "first result" \
  "validator: 先行 attempt の成果物を保持する"

# backend の選択は実 backend を起動せず、Paseo MCP が使える場合と使えない場合の
# 共通成果物契約として検証する。
set_backend() {
  local backend="$1"
  local reason="$2"
  local state_file
  jq --arg backend "$backend" --arg reason "$reason" \
    '.backend = $backend | .backend_reason = $reason' "$RUN/state.json" > "$RUN/state.json.tmp"
  mv "$RUN/state.json.tmp" "$RUN/state.json"
  while IFS= read -r state_file; do
    jq --arg backend "$backend" --arg reason "$reason" \
      '.backend = $backend | .backend_reason = $reason' "$state_file" > "$state_file.tmp"
    mv "$state_file.tmp" "$state_file"
  done < <(find "$RUN/nodes" -type f -name state.json -print)
}

for backend_case in "paseo-mcp:Paseo MCP available" "subagent:Paseo MCP unavailable"; do
  backend="${backend_case%%:*}"
  reason="${backend_case#*:}"
  set_backend "$backend" "$reason"
  out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
  status=$?
  assert_eq "$status" "0" "validator: $backend の共通成果物契約を受け入れる"
done

# backend selector は、Paseo MCP が利用可能なときだけその backend を選ぶ。
out="$(MANUAL_ORCHESTRATION_PASEO_MCP_AVAILABLE=1 bash "$VALIDATOR" --select-backend 2>&1)"
status=$?
assert_eq "$status" "0" "selector: Paseo MCP が利用可能なら selector が成功する"
assert_contains "$out" '"backend":"paseo-mcp"' "selector: Paseo MCP を優先する"
out="$(MANUAL_ORCHESTRATION_PASEO_MCP_AVAILABLE=0 bash "$VALIDATOR" --select-backend 2>&1)"
status=$?
assert_eq "$status" "0" "selector: Paseo MCP が利用不可でも selector が成功する"
assert_contains "$out" '"backend":"subagent"' "selector: Paseo MCP が利用不可なら native subagent を選ぶ"

# 完了した research は既定の 3 調査 node と synthesis output を全て持つ。
rm -rf "$RUN/nodes/research-3"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: research の必須 3 node 欠落を拒否する"
assert_contains "$out" "research-3" "validator: 欠けた research node を示す"
write_attempt research-3 attempt-001 'alternative result'

jq 'del(.completed_nodes[] | select(. == "synthesis"))' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: completed_nodes にない採用 output を root ok で拒否する"
assert_contains "$out" "completed_nodes" "validator: completed_nodes と adopted_attempts の不整合を示す"
jq '.completed_nodes += ["synthesis"]' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

jq 'del(.completed_nodes[] | select(. == "synthesis")) | del(.adopted_attempts.synthesis)' \
  "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: recipe の必須 synthesis output 欠落を root ok で拒否する"
assert_contains "$out" "synthesis" "validator: 欠落した recipe output を示す"
jq '.completed_nodes += ["synthesis"] | .adopted_attempts.synthesis = "attempt-001"' \
  "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

# ok run の採用 handoff は、実在する通常ファイルを後段へ渡さなければならない。
handoff="$RUN/nodes/synthesis/attempts/attempt-001/handoff.json"
jq '.artifact_paths = ["/tmp/missing-synthesis-output.md"]' "$handoff" > "$handoff.tmp"
mv "$handoff.tmp" "$handoff"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: 実在しない採用 handoff artifact を拒否する"
assert_contains "$out" "regular file" "validator: handoff artifact の通常ファイル要件を示す"
jq --arg result "$RUN/nodes/synthesis/attempts/attempt-001/result.md" \
  '.artifact_paths = [$result]' "$handoff" > "$handoff.tmp"
mv "$handoff.tmp" "$handoff"
artifact_link="$FIXTURE/synthesis-output-link.md"
ln -s "$RUN/nodes/synthesis/attempts/attempt-001/result.md" "$artifact_link"
jq --arg link "$artifact_link" '.artifact_paths = [$link]' "$handoff" > "$handoff.tmp"
mv "$handoff.tmp" "$handoff"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: symbolic link の採用 handoff artifact を拒否する"
assert_contains "$out" "regular file" "validator: handoff artifact の symlink を通常ファイルとみなさない"
jq --arg result "$RUN/nodes/synthesis/attempts/attempt-001/result.md" \
  '.artifact_paths = [$result]' "$handoff" > "$handoff.tmp"
mv "$handoff.tmp" "$handoff"
rm "$artifact_link"

# adopted node/attempt ID は basename-safe で、run 内の node/attempt だけを参照する。
jq '.adopted_attempts["../outside"] = "attempt-001"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: run 外を指し得る adopted node ID を拒否する"
assert_contains "$out" "basename-safe" "validator: adopted node ID の安全性を示す"
jq 'del(.adopted_attempts["../outside"])' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

jq '.adopted_attempts.synthesis = "../outside"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: run 外を指し得る adopted attempt ID を拒否する"
assert_contains "$out" "basename-safe" "validator: adopted attempt ID の安全性を示す"
jq '.adopted_attempts.synthesis = "attempt-001"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

mkdir -p "$FIXTURE/outside-node/attempts/attempt-001"
ln -s "$FIXTURE/outside-node" "$RUN/nodes/escaped"
jq '.completed_nodes += ["escaped"] | .adopted_attempts.escaped = "attempt-001"' \
  "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: run 外を向く adopted node directory を拒否する"
assert_contains "$out" "adopted node" "validator: adopted node の run 内配置を示す"
jq 'del(.completed_nodes[] | select(. == "escaped")) | del(.adopted_attempts.escaped)' \
  "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
rm "$RUN/nodes/escaped"

# root を ok とした run は、failed / stopped の子を隠せない。
for child_state in failed stopped; do
  attempt_state="$RUN/nodes/research-3/attempts/attempt-001/state.json"
  jq --arg state "$child_state" '.state = $state | .phase_state = $state' "$attempt_state" > "$attempt_state.tmp"
  mv "$attempt_state.tmp" "$attempt_state"
  out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
  status=$?
  assert_eq "$status" "1" "validator: root ok と $child_state child の矛盾を拒否する"
  assert_contains "$out" "root state ok" "validator: root と child の状態矛盾を示す"
  jq '.state = "ok" | .phase_state = "ok"' "$attempt_state" > "$attempt_state.tmp"
  mv "$attempt_state.tmp" "$attempt_state"
done

# 3 調査 node が全て ok になるまで、後段の synthesis を開始できない。
jq '.state = "running" | .phase_state = "running"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
attempt_state="$RUN/nodes/research-3/attempts/attempt-001/state.json"
jq '.state = "pending" | .phase_state = "pending"' "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"
write_attempt synthesis attempt-001 'synthesis result'
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: 全 research child ok 前の後段を拒否する"
assert_contains "$out" "before all research nodes are ok" \
  "validator: 後段開始を拒否した理由を示す"
jq '.state = "ok" | .phase_state = "ok"' "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"
jq '.state = "ok" | .phase_state = "ok"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

# 親が採用した retry attempt が ok なら、履歴上の失敗 attempt は run の成功を妨げない。
attempt_state="$RUN/nodes/research-1/attempts/attempt-001/state.json"
jq '.state = "failed" | .phase_state = "failed" | .parent_decision = "retry"' \
  "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "0" "validator: 採用済み retry が成功した run を受け入れる"
jq '.state = "ok" | .phase_state = "ok" | .parent_decision = "accepted"' \
  "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"

# ループ型 recipe は、max_rounds に未完了で到達した run を unresolved として残す。
LOOP_RUN="$FIXTURE/run-loop"
mkdir -p "$LOOP_RUN"
printf '%s\n' '{
  "run_id": "run-loop",
  "recipe": "refine",
  "state": "unresolved",
  "phase": "review",
  "phase_state": "unresolved",
  "next_action": "stop run",
  "current_round": 2,
  "max_rounds": 2,
  "started_at": "2026-09-05T00:00:00Z",
  "finished_at": "2026-09-05T00:01:00Z",
  "backend": "subagent",
  "backend_reason": "Paseo MCP unavailable",
  "parent_decision": "max_rounds reached without completion",
  "active_nodes": [],
  "completed_nodes": [],
  "adopted_attempts": {},
  "artifact_paths": []
}' > "$LOOP_RUN/state.json"
out="$(bash "$VALIDATOR" "$LOOP_RUN" 2>&1)"
status=$?
assert_eq "$status" "0" "validator: max_rounds 到達時の unresolved run を受け入れる"
jq '.max_rounds = 1' "$LOOP_RUN/state.json" > "$LOOP_RUN/state.json.tmp"
mv "$LOOP_RUN/state.json.tmp" "$LOOP_RUN/state.json"
out="$(bash "$VALIDATOR" "$LOOP_RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: max_rounds を超えた unresolved run を拒否する"
assert_contains "$out" "max_rounds" "validator: loop 上限違反を示す"

jq '.max_rounds = 2 | .state = "running" | .phase_state = "running"' \
  "$LOOP_RUN/state.json" > "$LOOP_RUN/state.json.tmp"
mv "$LOOP_RUN/state.json.tmp" "$LOOP_RUN/state.json"
out="$(bash "$VALIDATOR" "$LOOP_RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: 上限到達後も未完了の refine run を拒否する"
assert_contains "$out" "unresolved" "validator: 上限到達時の unresolved 要件を示す"
jq '.state = "unresolved" | .phase_state = "unresolved"' "$LOOP_RUN/state.json" > "$LOOP_RUN/state.json.tmp"
mv "$LOOP_RUN/state.json.tmp" "$LOOP_RUN/state.json"

# 決着した run の phase_state は run の state と一致する。
jq '.phase_state = "running"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: ok run と running phase の矛盾を拒否する"
assert_contains "$out" "phase_state" "validator: run/phase_state の矛盾を示す"
jq '.phase_state = "ok"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

# 実行中の run は、完了した phase を phase_state に残せる。両者を常に同じ値にすると
# phase_state が情報を持たなくなり、複数 phase を持つ delivery を表現できない。
PHASE_RUN="$FIXTURE/run-phase"
mkdir -p "$PHASE_RUN"
printf '%s\n' '{
  "run_id": "run-phase",
  "recipe": "delivery",
  "state": "running",
  "phase": "spec",
  "phase_state": "ok",
  "next_action": "start plan phase",
  "current_round": 0,
  "backend": "subagent",
  "backend_reason": "Paseo MCP unavailable",
  "parent_decision": "continue to plan",
  "active_nodes": [],
  "completed_nodes": [],
  "adopted_attempts": {},
  "artifact_paths": []
}' > "$PHASE_RUN/state.json"
out="$(bash "$VALIDATOR" "$PHASE_RUN" 2>&1)"
status=$?
assert_eq "$status" "0" "validator: 実行中の run が完了 phase を記録できる"

jq '.state = "waiting_for_user"' "$PHASE_RUN/state.json" > "$PHASE_RUN/state.json.tmp"
mv "$PHASE_RUN/state.json.tmp" "$PHASE_RUN/state.json"
out="$(bash "$VALIDATOR" "$PHASE_RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: waiting_for_user は phase_state の一致を要求する"
assert_contains "$out" "waiting_for_user" "validator: user gate の phase_state 要件を示す"

# recipe ごとの必須 output node が completed_nodes と adopted_attempts に無い run は
# `ok` にできない。validator は完了前の唯一の機械的 gate なので、ここが無いと
# final review を持たない delivery run をそのまま完了にできる。
required_output_for() {
  case "$1" in
    spec) printf 'spec-author\n' ;;
    plan) printf 'planner\n' ;;
    implement | delivery) printf 'final-review\n' ;;
    review) printf 'review-synthesis\n' ;;
  esac
}

# recipe の ok run を node 1 つだけで作る。node ID を変えると必須 output を欠いた run になる。
write_recipe_run() {
  local run_dir="$1"
  local recipe="$2"
  local node_id="$3"
  local run_id
  run_id="$(basename "$run_dir")"
  local attempt_dir="$run_dir/nodes/$node_id/attempts/attempt-001"

  rm -rf "$run_dir"
  mkdir -p "$attempt_dir"
  printf '指示\n' > "$attempt_dir/prompt.md"
  printf '{"status":"ok"}\n' > "$attempt_dir/result.json"
  printf 'backend log\n' > "$attempt_dir/log.md"
  jq -n --arg run "$run_id" --arg node "$node_id" --arg artifact "$attempt_dir/result.json" '{
    run_id: $run, node: $node, attempt: "attempt-001", artifact_paths: [$artifact]
  }' > "$attempt_dir/handoff.json"
  jq -n --arg run "$run_id" --arg node "$node_id" '{
    run_id: $run, node: $node, attempt: "attempt-001", round: 0,
    state: "ok", phase: "child_work", phase_state: "ok",
    next_action: "await parent decision",
    backend: "subagent", backend_reason: "Paseo MCP unavailable",
    parent_decision: "accepted"
  }' > "$attempt_dir/state.json"
  jq -n --arg run "$run_id" --arg recipe "$recipe" --arg node "$node_id" \
    --arg artifact "$attempt_dir/result.json" '{
    run_id: $run, recipe: $recipe, state: "ok", phase: $recipe, phase_state: "ok",
    next_action: "complete run", current_round: 1, max_rounds: 2,
    backend: "subagent", backend_reason: "Paseo MCP unavailable",
    parent_decision: "complete", active_nodes: [], completed_nodes: [$node],
    adopted_attempts: { ($node): "attempt-001" }, artifact_paths: [$artifact]
  }' > "$run_dir/state.json"
  # implement と spike は node ごとに worktree を作るので、base と台帳も要る。
  case "$recipe" in
    implement | spike)
      jq '.base = "master"' "$run_dir/state.json" > "$run_dir/tmp" \
        && mv "$run_dir/tmp" "$run_dir/state.json"
      jq -n --arg node "$node_id" '{
        ($node): {
          workspace_id: "ws-abc123",
          cwd: "/Users/someone/.paseo/worktrees/ws-abc123/impl",
          branch: "mad/20260905T120000-a1b2c3/\($node)",
          integration: "merged",
          archived: true
        }
      }' > "$run_dir/workspaces.json" ;;
  esac
}

for recipe in spec plan implement review delivery; do
  node_id="$(required_output_for "$recipe")"
  RECIPE_RUN="$FIXTURE/run-$recipe"

  write_recipe_run "$RECIPE_RUN" "$recipe" "$node_id"
  out="$(bash "$VALIDATOR" "$RECIPE_RUN" 2>&1)"
  status=$?
  assert_eq "$status" "0" "validator: $recipe は $node_id を持つ ok run を受け入れる"

  write_recipe_run "$RECIPE_RUN" "$recipe" "unrelated-node"
  out="$(bash "$VALIDATOR" "$RECIPE_RUN" 2>&1)"
  status=$?
  assert_eq "$status" "1" "validator: $recipe は $node_id を欠く ok run を拒否する"
  assert_contains "$out" "$node_id" "validator: $recipe に欠けた必須 output を示す"
done

# implement と spike は子が同時にファイルを書くので、node ごとに worktree を作る。
# 台帳が無いと、どの run がどの workspace を作ったかが追えなくなる。
mk_run_with_workspaces() {
  local dir="$1"
  local run_id
  rm -rf "$dir"
  mkdir -p "$dir"
  run_id="$(basename "$dir")"
  # 既存の run-01 の state.json を土台にし、recipe を implement、base を足す。
  # implement の ok run は max_rounds と final-review node も要る。
  jq --arg run "$run_id" --arg artifact "$dir/nodes/final-review/attempts/a1/result.md" \
    '.run_id = $run | .recipe = "implement" | .base = "master" | .max_rounds = 2 |
     .completed_nodes = ["implement-1", "final-review"] |
     .adopted_attempts = {"implement-1": "a1", "final-review": "a1"} |
     .artifact_paths = [$artifact]' "$RUN/state.json" > "$dir/state.json"
  write_attempt_in "$dir" "implement-1" "a1" "実装結果"
  write_attempt_in "$dir" "final-review" "a1" "レビュー結果"
  # run は ok なので、台帳の workspace は archive 済みにしておく。
  cat > "$dir/workspaces.json" <<'JSON'
{
  "implement-1": {
    "workspace_id": "ws-abc123",
    "cwd": "/Users/someone/.paseo/worktrees/ws-abc123/impl",
    "branch": "mad/20260905T120000-a1b2c3/implement-1",
    "integration": "merged",
    "archived": true
  }
}
JSON
}

# 正常系
mk_run_with_workspaces "$RUN/nested-ok"
assert_contains "$(validate_run "$RUN/nested-ok")" "valid manual orchestration run" \
  "validator: workspaces.json を持つ run を受け入れる"

# implement は node ごとに worktree を作る。台帳が無い run を素通りさせると、
# 同じ作業ディレクトリで並列に走らせた run を唯一の機械的な検査が捕まえられない。
mk_run_with_workspaces "$RUN/implement-no-workspaces"
rm "$RUN/implement-no-workspaces/workspaces.json"
assert_contains "$(validate_run "$RUN/implement-no-workspaces")" "workspaces.json is required" \
  "validator: implement の run に台帳を要求する"

# cwd が相対パス
mk_run_with_workspaces "$RUN/rel-cwd"
jq '.["implement-1"].cwd = "relative/path"' "$RUN/rel-cwd/workspaces.json" > "$RUN/rel-cwd/tmp" \
  && mv "$RUN/rel-cwd/tmp" "$RUN/rel-cwd/workspaces.json"
assert_contains "$(validate_run "$RUN/rel-cwd")" "cwd must be an absolute path" \
  "validator: workspaces.json の相対パスを拒否する"

# run の node に無い node ID
mk_run_with_workspaces "$RUN/unknown-node"
jq '. + {"no-such-node": .["implement-1"]}' "$RUN/unknown-node/workspaces.json" > "$RUN/unknown-node/tmp" \
  && mv "$RUN/unknown-node/tmp" "$RUN/unknown-node/workspaces.json"
assert_contains "$(validate_run "$RUN/unknown-node")" "unknown node" \
  "validator: run に無い node の workspace を拒否する"

# archive していない workspace を持つ run を ok にできない
mk_run_with_workspaces "$RUN/not-archived"
jq '.["implement-1"].archived = false' "$RUN/not-archived/workspaces.json" > "$RUN/not-archived/tmp" \
  && mv "$RUN/not-archived/tmp" "$RUN/not-archived/workspaces.json"
assert_contains "$(validate_run "$RUN/not-archived")" "workspace is not archived" \
  "validator: 未 archive の workspace を持つ run を ok にしない"

# archive は run の完了時に行う。実行中の run は archive 前の workspace を持てる。
mk_run_with_workspaces "$RUN/running-not-archived"
jq '.state = "running" | .phase_state = "running"' "$RUN/running-not-archived/state.json" \
  > "$RUN/running-not-archived/tmp" \
  && mv "$RUN/running-not-archived/tmp" "$RUN/running-not-archived/state.json"
jq '.["implement-1"].archived = false' "$RUN/running-not-archived/workspaces.json" \
  > "$RUN/running-not-archived/tmp" \
  && mv "$RUN/running-not-archived/tmp" "$RUN/running-not-archived/workspaces.json"
assert_contains "$(validate_run "$RUN/running-not-archived")" "valid manual orchestration run" \
  "validator: 実行中の run は未 archive の workspace を許す"

# worktree を作る run は base を run state に記録する。base が無いと diff の起点が
# 決まらず、レビュー役へ渡す差分を作れない。
mk_run_with_workspaces "$RUN/no-base"
jq 'del(.base)' "$RUN/no-base/state.json" > "$RUN/no-base/tmp" \
  && mv "$RUN/no-base/tmp" "$RUN/no-base/state.json"
assert_contains "$(validate_run "$RUN/no-base")" "base is required" \
  "validator: workspace を持つ run に base を要求する"

# node 1 つと、recipe が必須とする output node だけを持つ ok run を作る。
# 土台は run-01 の state.json で、recipe と採用 attempt だけを差し替える。
mk_recipe_run_with_node() {
  local run_dir="$1"
  local recipe="$2"
  local node_id="$3"
  local attempt_id="$4"
  local run_id
  local output_node

  rm -rf "$run_dir"
  mkdir -p "$run_dir"
  run_id="$(basename "$run_dir")"
  output_node="$(required_output_for "$recipe")"
  write_attempt_in "$run_dir" "$node_id" "$attempt_id" "作業結果"
  jq --arg run "$run_id" --arg recipe "$recipe" --arg node "$node_id" \
    --arg attempt "$attempt_id" \
    --arg artifact "$run_dir/nodes/$node_id/attempts/$attempt_id/result.md" \
    '.run_id = $run | .recipe = $recipe | .max_rounds = 2 |
     .completed_nodes = [$node] | .adopted_attempts = { ($node): $attempt } |
     .artifact_paths = [$artifact]' "$RUN/state.json" > "$run_dir/state.json"
  if [ -n "$output_node" ]; then
    write_attempt_in "$run_dir" "$output_node" "$attempt_id" "レビュー結果"
    jq --arg node "$output_node" --arg attempt "$attempt_id" \
      '.completed_nodes += [$node] | .adopted_attempts += { ($node): $attempt }' \
      "$run_dir/state.json" > "$run_dir/tmp"
    mv "$run_dir/tmp" "$run_dir/state.json"
  fi
}

# 実装役の attempt に diff.patch を置く。親は workspaces.json の cwd から diff を取るので、
# 台帳と base も付ける。
mk_attempt_with_diff() {
  local run_dir="$1"
  local node_id="$2"
  local attempt_id="$3"

  mk_recipe_run_with_node "$run_dir" implement "$node_id" "$attempt_id"
  jq '.base = "master"' "$run_dir/state.json" > "$run_dir/tmp"
  mv "$run_dir/tmp" "$run_dir/state.json"
  jq -n --arg node "$node_id" '{
    ($node): {
      workspace_id: "ws-abc123",
      cwd: "/tmp/mad-worktrees/ws-abc123/impl",
      branch: "mad/20260905T120000-a1b2c3/\($node)",
      integration: "merged",
      archived: true
    }
  }' > "$run_dir/workspaces.json"
  printf '%s\n' \
    'diff --git a/src/app.ts b/src/app.ts' \
    '--- a/src/app.ts' \
    '+++ b/src/app.ts' \
    '@@ -1 +1 @@' \
    '-old' \
    '+new' > "$run_dir/nodes/$node_id/attempts/$attempt_id/diff.patch"
}

# 改稿役の attempt に before/ を置く。改稿前の対象ファイルはここへ複製する。
mk_attempt_with_before() {
  local run_dir="$1"
  local node_id="$2"
  local attempt_id="$3"
  local before_dir="$run_dir/nodes/$node_id/attempts/$attempt_id/before"

  mk_recipe_run_with_node "$run_dir" refine "$node_id" "$attempt_id"
  mkdir -p "$before_dir"
  printf '改稿前の本文\n' > "$before_dir/spec.md"
}

# レビュー役と judge は worktree の中を見られない。親が取った diff を attempt に
# 置き、後段には絶対パスだけを渡す。
mk_attempt_with_diff "$RUN/with-diff" "implement-1" "a1"
assert_contains "$(validate_run "$RUN/with-diff")" "valid manual orchestration run" \
  "validator: attempt の diff.patch を受け入れる"

# diff.patch は attempt の中に置く。node 直下は既存の規約どおり拒否する。
mk_attempt_with_diff "$RUN/diff-at-node" "implement-1" "a1"
mv "$RUN/diff-at-node/nodes/implement-1/attempts/a1/diff.patch" \
   "$RUN/diff-at-node/nodes/implement-1/diff.patch"
assert_contains "$(validate_run "$RUN/diff-at-node" 2>&1)" "node artifacts must be under attempts/" \
  "validator: node 直下の diff.patch を拒否する"

# refine は改稿前のファイルを attempt の before/ へ退避する。
mk_attempt_with_before "$RUN/with-before" "revise-1" "a1"
assert_contains "$(validate_run "$RUN/with-before")" "valid manual orchestration run" \
  "validator: attempt の before/ を受け入れる"

# attempt の検索は attempts/ の直下だけを見る。入れ子の attempts をそのまま許すと、
# 検索から外れた state.json が一度も検証されない。attempt の中に置けるディレクトリを
# before/ だけに限って拒否する。
mk_attempt_with_diff "$RUN/nested-attempts" "implement-1" "a1"
nested="$RUN/nested-attempts/nodes/implement-1/attempts/a1/attempts/a2"
mkdir -p "$nested"
cp "$RUN/nested-attempts/nodes/implement-1/attempts/a1/state.json" "$nested/state.json"
assert_contains "$(validate_run "$RUN/nested-attempts")" "attempt directories may only contain before/" \
  "validator: attempt の中の入れ子 attempts を拒否する"

# node 直下も同じで、attempts 以外のディレクトリを許すと、その下の attempt が
# 検索から外れる。
mk_attempt_with_diff "$RUN/node-subdir" "implement-1" "a1"
mkdir -p "$RUN/node-subdir/nodes/implement-1/scratch/attempts/a2"
assert_contains "$(validate_run "$RUN/node-subdir")" "node artifacts must be under attempts/" \
  "validator: node 直下の attempts 以外のディレクトリを拒否する"

# before/ は対象ファイルの複製だけを持つ。ディレクトリを許すと、そこにも検索から
# 外れた構造を作れる。
mk_attempt_with_before "$RUN/before-subdir" "revise-1" "a1"
mkdir -p "$RUN/before-subdir/nodes/revise-1/attempts/a1/before/nested"
assert_contains "$(validate_run "$RUN/before-subdir")" "before/ must contain only regular files" \
  "validator: before/ の中のディレクトリを拒否する"

# spike も node ごとに worktree を作るので、台帳を要求する。
mk_recipe_run_with_node "$RUN/spike-no-workspaces" spike "spike-1" "a1"
assert_contains "$(validate_run "$RUN/spike-no-workspaces")" "workspaces.json is required" \
  "validator: spike の run に台帳を要求する"

# worktree を作らない recipe は、今までどおり台帳も base も要求しない。
mk_recipe_run_with_node "$RUN/review-no-workspaces" review "review-1" "a1"
assert_contains "$(validate_run "$RUN/review-no-workspaces")" "valid manual orchestration run" \
  "validator: worktree を作らない recipe に台帳と base を要求しない"

# archive は worktree のディレクトリごと消す。取り込みの判断を run の完了条件に
# しないと、上限で切られた diff.patch しか残らない実装が復元できなくなる。
set_integration() {
  local dir="$1"
  shift
  jq "$@" "$dir/workspaces.json" > "$dir/tmp" && mv "$dir/tmp" "$dir/workspaces.json"
}

# integration が無い台帳を拒否する。
mk_run_with_workspaces "$RUN/no-integration"
set_integration "$RUN/no-integration" 'del(.["implement-1"].integration)'
assert_contains "$(validate_run "$RUN/no-integration")" "integration must be one of" \
  "validator: integration を持たない台帳を拒否する"

# 定義されていない値を拒否する。
mk_run_with_workspaces "$RUN/bad-integration"
set_integration "$RUN/bad-integration" '.["implement-1"].integration = "done"'
assert_contains "$(validate_run "$RUN/bad-integration")" "integration must be one of" \
  "validator: 定義外の integration を拒否する"

# 未判断のまま run を ok にできない。
mk_run_with_workspaces "$RUN/pending-integration"
set_integration "$RUN/pending-integration" '.["implement-1"].integration = "pending"'
assert_contains "$(validate_run "$RUN/pending-integration")" "integration is still pending" \
  "validator: 取り込みが未判断の run を ok にしない"

# archived の要求は、判断が済んだ後にだけ掛ける。未判断かつ未 archive の run では
# 未判断のほうを先に報告する。
mk_run_with_workspaces "$RUN/pending-and-unarchived"
set_integration "$RUN/pending-and-unarchived" \
  '.["implement-1"].integration = "pending" | .["implement-1"].archived = false'
assert_contains "$(validate_run "$RUN/pending-and-unarchived")" "integration is still pending" \
  "validator: 未判断を未 archive より先に報告する"

# 実行中の run は未判断の workspace を持てる。
mk_run_with_workspaces "$RUN/running-pending"
jq '.state = "running" | .phase_state = "running"' "$RUN/running-pending/state.json" \
  > "$RUN/running-pending/tmp" && mv "$RUN/running-pending/tmp" "$RUN/running-pending/state.json"
set_integration "$RUN/running-pending" \
  '.["implement-1"].integration = "pending" | .["implement-1"].archived = false'
assert_contains "$(validate_run "$RUN/running-pending")" "valid manual orchestration run" \
  "validator: 実行中の run は未判断の workspace を許す"

# 取り込まないと決めたなら理由を残す。理由が無いと、後から判断を追えない。
mk_run_with_workspaces "$RUN/declined-no-reason"
set_integration "$RUN/declined-no-reason" '.["implement-1"].integration = "declined"'
assert_contains "$(validate_run "$RUN/declined-no-reason")" "integration_reason is required" \
  "validator: 理由の無い declined を拒否する"

mk_run_with_workspaces "$RUN/declined-with-reason"
set_integration "$RUN/declined-with-reason" \
  '.["implement-1"].integration = "declined" | .["implement-1"].integration_reason = "試作なので捨てる"'
assert_contains "$(validate_run "$RUN/declined-with-reason")" "valid manual orchestration run" \
  "validator: 理由付きの declined を受け入れる"

# --- 判断要求: decision_request の実体が無い run を拒否する ---
# 実体が無いと、親はユーザーへ何を聞けばよいか分からないまま waiting_for_user になる。
DR="$FIXTURE/run-dr"
mkdir -p "$DR"
write_attempt_in "$DR" spec-author a1 '設計案'
DR_FILE="$DR/nodes/spec-author/attempts/a1/decision-request.md"
printf '%s\n' "{
  \"run_id\": \"run-dr\",
  \"recipe\": \"spec\",
  \"state\": \"waiting_for_user\",
  \"phase\": \"spec-author\",
  \"phase_state\": \"waiting_for_user\",
  \"next_action\": \"relay decision request\",
  \"current_round\": 0,
  \"started_at\": \"2026-09-06T00:00:00Z\",
  \"backend\": \"subagent\",
  \"backend_reason\": \"Paseo MCP unavailable\",
  \"parent_decision\": \"ask user\",
  \"active_nodes\": [\"spec-author\"],
  \"completed_nodes\": [],
  \"adopted_attempts\": {},
  \"artifact_paths\": [],
  \"decision_request\": \"$DR_FILE\"
}" > "$DR/state.json"

out="$(validate_run "$DR")"
assert_contains "$out" "decision_request の実体" \
  "decision_request の実体が無い run を validator が拒否する"

printf '質問と選択肢\n' > "$DR_FILE"
out="$(validate_run "$DR")"
assert_not_contains "$out" "decision_request の実体" \
  "decision_request の実体がある run では、その指摘を出さない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
