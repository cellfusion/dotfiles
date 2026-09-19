#!/usr/bin/env bash
# MAD review/fix の回数上限と task scope を、実際の validator CLI で検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

RUNNER="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"
SHARE_DIR="$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RUN="$TMP/run"
SCOPE="$TMP/review-scope.json"
OBSERVATIONS="$TMP/out-of-scope.json"
mkdir -p "$RUN/review-admissions" "$RUN/nodes/task-8-review/attempts/a1"

printf '%s\n' '{
  "version": 1,
  "type": "mad-review-scope",
  "task": "task-8",
  "allowedFiles": ["private_dot_local/private_share/agent-config/mad-contract.js", "tests/test-paseo-mad.sh"],
  "findingIds": ["F-1"],
  "outOfScopePath": "'"$OBSERVATIONS"'"
}' > "$SCOPE"
chmod 600 "$SCOPE"

printf '%s\n' '{
  "run_id": "run-review-guard",
  "recipe": "implement",
  "state": "running",
  "phase": "implement",
  "phase_state": "running",
  "next_action": "start review",
  "current_round": 0,
  "max_rounds": 4,
  "review_policy": {
    "max_rounds": 4,
    "scope_file": "'"$SCOPE"'",
    "out_of_scope_path": "'"$OBSERVATIONS"'"
  },
  "started_at": "2026-09-14T00:00:00Z",
  "backend": "paseo-mcp",
  "backend_reason": "offline fixture",
  "parent_decision": "start bounded review",
  "active_nodes": ["task-8-review"],
  "completed_nodes": [],
  "adopted_attempts": {},
  "artifact_paths": []
}' > "$RUN/state.json"
chmod 600 "$RUN/state.json"

out="$(bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$RUN" --task task-8 \
  --phase review --node task-8-review --attempt a1 --scope-file "$SCOPE" 2>&1)"
status=$?
assert_eq "$status" "0" "review guard: 初回 review admission を受理する"
assert_eq "$(find "$RUN/review-admissions" -type f | wc -l | tr -d ' ')" "1" \
  "review guard: admission marker は一件だけ作る"

out="$(bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$RUN" --task task-8 \
  --phase review --node task-8-review --attempt a1 --scope-file "$SCOPE" 2>&1)"
status=$?
assert_eq "$status" "2" "review guard: 同じ review admission を二重作成しない"
assert_eq "$(find "$RUN/review-admissions" -type f | wc -l | tr -d ' ')" "1" \
  "review guard: 二重 admission で marker を増やさない"

jq '.findingIds += ["F-2"]' "$SCOPE" > "$TMP/changed-scope.json"
chmod 600 "$TMP/changed-scope.json"
jq '.current_round = 1 | .phase = "review" | .phase_state = "ok" | .active_nodes = ["task-8-fix"]' \
  "$RUN/state.json" > "$RUN/state.tmp" && mv "$RUN/state.tmp" "$RUN/state.json"
chmod 600 "$RUN/state.json"
out="$(bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$RUN" --task task-8 \
  --phase fix --node task-8-fix --attempt a1 --scope-file "$TMP/changed-scope.json" 2>&1)"
assert_eq "$?" "2" "review guard: loop 中の scope 拡張を拒否する"

jq '.current_round = 0 | .phase = "implement" | .phase_state = "running" | .active_nodes = ["task-8-review"]' \
  "$RUN/state.json" > "$RUN/state.tmp" && mv "$RUN/state.tmp" "$RUN/state.json"
chmod 600 "$RUN/state.json"

jq '.current_round = 1 | .phase = "review" | .phase_state = "ok" | .active_nodes = ["task-8-fix"]' \
  "$RUN/state.json" > "$RUN/state.tmp" && mv "$RUN/state.tmp" "$RUN/state.json"
chmod 600 "$RUN/state.json"
mkdir -p "$RUN/nodes/task-8-fix/attempts/a1"
out="$(bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$RUN" --task task-8 \
  --phase fix --node task-8-fix --attempt a1 --scope-file "$SCOPE" 2>&1)"
status=$?
assert_eq "$status" "0" "review guard: 許可された fix round を受理する"

out="$(bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$RUN" --task task-8 \
  --phase fix --node task-8-hotfix --attempt a1 --scope-file "$SCOPE" 2>&1)"
status=$?
assert_eq "$status" "2" "review guard: task scope 外の hotfix node を拒否する"

printf '%s\n' '{"changedFiles":["private_dot_local/private_share/agent-config/mad-contract.js"]}' > "$TMP/in-scope-result.json"
printf '%s\n' '{"changedFiles":["private_dot_local/private_share/other.js"]}' > "$TMP/out-of-scope-result.json"
for result in "$TMP/in-scope-result.json" "$TMP/out-of-scope-result.json"; do chmod 600 "$result"; done

bash "$RUNNER" --check-review-scope --share-dir "$SHARE_DIR" --scope-file "$SCOPE" \
  --result-file "$TMP/in-scope-result.json" >/dev/null 2>&1
assert_eq "$?" "0" "review guard: fix の変更が task scope 内なら受理する"
bash "$RUNNER" --check-review-scope --share-dir "$SHARE_DIR" --scope-file "$SCOPE" \
  --result-file "$TMP/out-of-scope-result.json" >/dev/null 2>&1
assert_eq "$?" "2" "review guard: fix の scope 外変更を拒否する"

jq '.current_round = 2 | .phase = "review" | .phase_state = "ok" | .active_nodes = []' \
  "$RUN/state.json" > "$RUN/state.tmp" && mv "$RUN/state.tmp" "$RUN/state.json"
out="$(bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$RUN" --task task-8 \
  --phase re-review --node task-8-re-review --attempt a1 --scope-file "$SCOPE" 2>&1)"
status=$?
assert_eq "$status" "2" "review guard: 上限到達後に re-review を追加しない"

printf '%s\n' '{"version":1,"type":"mad-review-observations","task":"task-8","items":[{"id":"O-1","severity":"important","location":"outside-task","summary":"important observation","source":"re-reviewer"}]}' > "$OBSERVATIONS"
chmod 600 "$OBSERVATIONS"
cp "$OBSERVATIONS" "$TMP/observations-input.json"
rm -f "$OBSERVATIONS"
bash "$RUNNER" --write-review-observations --share-dir "$SHARE_DIR" \
  --scope-file "$SCOPE" --observation-file "$OBSERVATIONS" \
  --input "$TMP/observations-input.json" >/dev/null 2>&1
assert_eq "$?" "0" "review guard: scope 外 observation を atomic writer で保存する"
assert_eq "$(stat -f '%Lp' "$OBSERVATIONS")" "600" \
  "review guard: observation writer は mode 0600 を強制する"
bash "$RUNNER" --check-review-observations --share-dir "$SHARE_DIR" \
  --scope-file "$SCOPE" --observation-file "$OBSERVATIONS" >/dev/null 2>&1
assert_eq "$?" "0" "review guard: scope 外の観測を最終 gate 用に検査できる"
assert_eq "$(jq -r '.items[0].id' "$OBSERVATIONS")" "O-1" \
  "review guard: scope 外の観測を最終 gate 用に保持する"

# --- 設計 3: review package の範囲を照合する ---
PKG_BASE="1111111111111111111111111111111111111111"
PKG_HEAD="2222222222222222222222222222222222222222"
PACKAGE="$TMP/review-package.diff"
{
  printf '# Review package: %s..%s\n' "$PKG_BASE" "$PKG_HEAD"
  printf '\n## Commits\nabc1234 feat: change\n\n## Files changed\n a.txt | 1 +\n\n## Diff\n'
} > "$PACKAGE"
chmod 600 "$PACKAGE"

write_review_result() {
  printf '%s\n' "$2" > "$1"
  chmod 600 "$1"
}

write_review_result "$TMP/pkg-exact.json" \
  "{\"packageBase\":\"$PKG_BASE\",\"packageHead\":\"$PKG_HEAD\"}"
bash "$RUNNER" --check-review-package --share-dir "$SHARE_DIR" \
  --package-file "$PACKAGE" --result-file "$TMP/pkg-exact.json" >/dev/null 2>&1
assert_eq "$?" "0" "review package: header と完全一致する範囲を受理する"

write_review_result "$TMP/pkg-short.json" \
  "{\"packageBase\":\"${PKG_BASE:0:7}\",\"packageHead\":\"${PKG_HEAD:0:12}\"}"
bash "$RUNNER" --check-review-package --share-dir "$SHARE_DIR" \
  --package-file "$PACKAGE" --result-file "$TMP/pkg-short.json" >/dev/null 2>&1
assert_eq "$?" "0" "review package: 短縮 sha を先頭一致で受理する"

write_review_result "$TMP/pkg-wrong-base.json" \
  "{\"packageBase\":\"3333333333333333333333333333333333333333\",\"packageHead\":\"$PKG_HEAD\"}"
bash "$RUNNER" --check-review-package --share-dir "$SHARE_DIR" \
  --package-file "$PACKAGE" --result-file "$TMP/pkg-wrong-base.json" >/dev/null 2>&1
assert_eq "$?" "2" "review package: base が違う報告を拒否する"

write_review_result "$TMP/pkg-wrong-head.json" \
  "{\"packageBase\":\"$PKG_BASE\",\"packageHead\":\"3333333\"}"
bash "$RUNNER" --check-review-package --share-dir "$SHARE_DIR" \
  --package-file "$PACKAGE" --result-file "$TMP/pkg-wrong-head.json" >/dev/null 2>&1
assert_eq "$?" "2" "review package: head が違う報告を拒否する"

write_review_result "$TMP/pkg-too-short.json" \
  "{\"packageBase\":\"111111\",\"packageHead\":\"$PKG_HEAD\"}"
bash "$RUNNER" --check-review-package --share-dir "$SHARE_DIR" \
  --package-file "$PACKAGE" --result-file "$TMP/pkg-too-short.json" >/dev/null 2>&1
assert_eq "$?" "2" "review package: 7 文字未満の sha を拒否する"

printf 'no header here\n' > "$TMP/bad-package.diff"
chmod 600 "$TMP/bad-package.diff"
bash "$RUNNER" --check-review-package --share-dir "$SHARE_DIR" \
  --package-file "$TMP/bad-package.diff" --result-file "$TMP/pkg-exact.json" >/dev/null 2>&1
assert_eq "$?" "2" "review package: header の無い package を拒否する"

cp "$PACKAGE" "$TMP/package-0644.diff"
chmod 644 "$TMP/package-0644.diff"
bash "$RUNNER" --check-review-package --share-dir "$SHARE_DIR" \
  --package-file "$TMP/package-0644.diff" --result-file "$TMP/pkg-exact.json" >/dev/null 2>&1
assert_eq "$?" "2" "review package: mode 0600 でない package を拒否する"

# --- 設計 4: verdict と findings の整合を検査する ---
write_review_result "$TMP/verdict-ok.json" \
  '{"specVerdict":"compliant","qualityVerdict":"approved","findings":[{"severity":"minor","summary":"s","location":"l","fix":null,"planMandated":null}]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/verdict-ok.json" --role task-reviewer >/dev/null 2>&1
assert_eq "$?" "0" "review verdict: 合格の verdict と minor だけの findings を受理する"

write_review_result "$TMP/verdict-issues-empty.json" \
  '{"specVerdict":"issues","qualityVerdict":"approved","findings":[]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/verdict-issues-empty.json" --role task-reviewer >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: specVerdict が issues で findings が空なら拒否する"

write_review_result "$TMP/verdict-needs-fixes-empty.json" \
  '{"specVerdict":"compliant","qualityVerdict":"needs_fixes","findings":[]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/verdict-needs-fixes-empty.json" --role task-reviewer >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: qualityVerdict が needs_fixes で findings が空なら拒否する"

write_review_result "$TMP/verdict-pass-important.json" \
  '{"specVerdict":"compliant","qualityVerdict":"approved","findings":[{"severity":"important","summary":"s","location":"l","fix":null,"planMandated":null}]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/verdict-pass-important.json" --role task-reviewer >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: 合格の verdict に important の finding があれば拒否する"

OPEN_FIXTURE="$TMP/open-findings-fixture.json"
write_review_result "$OPEN_FIXTURE" \
  '{"version":1,"type":"mad-review-open-findings","task":"task-8","round":1,"findings":[{"id":"OF-1","severity":"important","summary":"s1","location":"l1","origin":"review-finding","originItem":null},{"id":"OF-2","severity":"critical","summary":"s2","location":"l2","origin":"review-finding","originItem":null}]}'

write_review_result "$TMP/rere-exact.json" \
  '{"verdicts":[{"findingId":"OF-1","finding":"s1","addressed":true,"evidence":"e"},{"findingId":"OF-2","finding":"s2","addressed":false,"evidence":null}]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/rere-exact.json" --role re-reviewer --open-findings-file "$OPEN_FIXTURE" >/dev/null 2>&1
assert_eq "$?" "0" "review verdict: findingId の集合が一覧と一致すれば受理する"

write_review_result "$TMP/rere-missing.json" \
  '{"verdicts":[{"findingId":"OF-1","finding":"s1","addressed":true,"evidence":"e"}]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/rere-missing.json" --role re-reviewer --open-findings-file "$OPEN_FIXTURE" >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: 判定していない指摘があれば拒否する"

write_review_result "$TMP/rere-extra.json" \
  '{"verdicts":[{"findingId":"OF-1","finding":"s1","addressed":true,"evidence":"e"},{"findingId":"OF-2","finding":"s2","addressed":true,"evidence":"e"},{"findingId":"OF-3","finding":"s3","addressed":true,"evidence":"e"}]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/rere-extra.json" --role re-reviewer --open-findings-file "$OPEN_FIXTURE" >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: 一覧に無い findingId を拒否する"

write_review_result "$TMP/rere-duplicate.json" \
  '{"verdicts":[{"findingId":"OF-1","finding":"s1","addressed":true,"evidence":"e"},{"findingId":"OF-1","finding":"s1","addressed":false,"evidence":null}]}'
bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/rere-duplicate.json" --role re-reviewer --open-findings-file "$OPEN_FIXTURE" >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: 同じ findingId を 2 回判定した結果を拒否する"

bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/rere-exact.json" --role re-reviewer >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: re-reviewer で --open-findings-file が無ければ拒否する"

bash "$RUNNER" --check-review-verdict --share-dir "$SHARE_DIR" \
  --result-file "$TMP/verdict-ok.json" --role final-reviewer >/dev/null 2>&1
assert_eq "$?" "2" "review verdict: 未知の role を拒否する"

# --- 決着: findingIds が空の scope でも fix の admission が下りる ---
EMPTY_RUN="$TMP/run-empty-findings"
EMPTY_SCOPE="$TMP/empty-findings-scope.json"
mkdir -p "$EMPTY_RUN/review-admissions"
printf '%s\n' '{
  "version": 1,
  "type": "mad-review-scope",
  "task": "task-9",
  "allowedFiles": ["private_dot_local/private_share/agent-config/mad-contract.js"],
  "findingIds": [],
  "outOfScopePath": "'"$TMP/empty-observations.json"'"
}' > "$EMPTY_SCOPE"
chmod 600 "$EMPTY_SCOPE"
printf '%s\n' '{
  "run_id": "run-empty-findings",
  "recipe": "implement",
  "state": "running",
  "phase": "implement",
  "phase_state": "running",
  "next_action": "start review",
  "current_round": 0,
  "max_rounds": 4,
  "review_policy": {
    "max_rounds": 4,
    "scope_file": "'"$EMPTY_SCOPE"'",
    "out_of_scope_path": "'"$TMP/empty-observations.json"'"
  },
  "started_at": "2026-09-14T00:00:00Z",
  "backend": "paseo-mcp",
  "backend_reason": "offline fixture",
  "parent_decision": "start bounded review",
  "active_nodes": ["task-9-review"],
  "completed_nodes": [],
  "adopted_attempts": {},
  "artifact_paths": []
}' > "$EMPTY_RUN/state.json"
chmod 600 "$EMPTY_RUN/state.json"
bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$EMPTY_RUN" --task task-9 \
  --phase review --node task-9-review --attempt a1 --scope-file "$EMPTY_SCOPE" >/dev/null 2>&1
assert_eq "$?" "0" "review guard: findingIds が空の scope で review admission を受理する"
jq '.current_round = 1 | .phase = "review" | .phase_state = "ok" | .active_nodes = ["task-9-fix"]' \
  "$EMPTY_RUN/state.json" > "$EMPTY_RUN/state.tmp" && mv "$EMPTY_RUN/state.tmp" "$EMPTY_RUN/state.json"
chmod 600 "$EMPTY_RUN/state.json"
bash "$RUNNER" --prepare-review --share-dir "$SHARE_DIR" --run-dir "$EMPTY_RUN" --task task-9 \
  --phase fix --node task-9-fix --attempt a1 --scope-file "$EMPTY_SCOPE" >/dev/null 2>&1
assert_eq "$?" "0" "review guard: findingIds が空の scope で fix admission を受理する"

RUNAWAY="$TMP/run-runaway"
RUNAWAY_SCOPE="$TMP/runaway-scope.json"
mkdir -p "$RUNAWAY/nodes/task-8-hotfix/attempts/a1" "$RUNAWAY/review-admissions"
cp "$SCOPE" "$RUNAWAY_SCOPE"
chmod 600 "$RUNAWAY_SCOPE"
printf '%s\n' '{
  "run_id": "run-runaway",
  "recipe": "implement",
  "state": "running",
  "phase": "implement",
  "phase_state": "running",
  "next_action": "start review",
  "current_round": 0,
  "max_rounds": 5,
  "started_at": "2026-09-14T00:00:00Z",
  "backend": "paseo-mcp",
  "backend_reason": "offline fixture",
  "parent_decision": "legacy unbounded loop",
  "active_nodes": ["task-8-hotfix"],
  "completed_nodes": [],
  "adopted_attempts": {},
  "artifact_paths": [],
  "base": "master"
}' > "$RUNAWAY/state.json"
chmod 600 "$RUNAWAY/state.json"
printf '%s\n' 'prompt' > "$RUNAWAY/nodes/task-8-hotfix/attempts/a1/prompt.md"
printf '%s\n' '{"changedFiles":["private_dot_local/private_share/agent-config/mad-contract.js"]}' > "$RUNAWAY/nodes/task-8-hotfix/attempts/a1/result.json"
printf '%s\n' 'log' > "$RUNAWAY/nodes/task-8-hotfix/attempts/a1/log.md"
printf '%s\n' '{"run_id":"run-runaway","node":"task-8-hotfix","attempt":"a1","artifact_paths":["'"$RUNAWAY/nodes/task-8-hotfix/attempts/a1/result.json"'"]}' > "$RUNAWAY/nodes/task-8-hotfix/attempts/a1/handoff.json"
printf '%s\n' '{"run_id":"run-runaway","node":"task-8-hotfix","attempt":"a1","round":0,"state":"ok","phase":"fix","phase_state":"ok","next_action":"review","create_accepted":true,"child_ref":"child-a1","backend":"paseo-mcp","backend_reason":"offline fixture","parent_decision":"legacy"}' > "$RUNAWAY/nodes/task-8-hotfix/attempts/a1/state.json"
printf '%s\n' '{"task-8-hotfix":{"workspace_id":"ws-a1","cwd":"/tmp/ws-a1","branch":"mad/task-8-hotfix","integration":"merged","archived":true}}' > "$RUNAWAY/workspaces.json"
out="$(bash "$RUNNER" "$RUNAWAY" 2>&1)"
assert_eq "$?" "1" "review guard: admission policy 無しの runaway run を拒否する"
assert_contains "$out" "review policy" "review guard: runaway の原因を review policy 不在として示す"

VALID_RUN="$TMP/run-valid"
VALID_SCOPE="$TMP/valid-scope.json"
VALID_OBSERVATIONS="$TMP/valid-observations.json"
cp "$SCOPE" "$VALID_SCOPE"
chmod 600 "$VALID_SCOPE"
mkdir -p "$VALID_RUN/review-admissions" \
  "$VALID_RUN/nodes/task-8-review/attempts/a1" \
  "$VALID_RUN/nodes/task-8-fix/attempts/a1"
printf '%s\n' '{
  "run_id": "run-valid",
  "recipe": "implement",
  "state": "running",
  "phase": "review",
  "phase_state": "ok",
  "next_action": "final review",
  "current_round": 1,
  "max_rounds": 4,
  "review_policy": {
    "max_rounds": 4,
    "scope_file": "'"$VALID_SCOPE"'",
    "out_of_scope_path": "'"$VALID_OBSERVATIONS"'"
  },
  "started_at": "2026-09-14T00:00:00Z",
  "backend": "paseo-mcp",
  "backend_reason": "offline fixture",
  "parent_decision": "bounded review",
  "active_nodes": [],
  "completed_nodes": [],
  "adopted_attempts": {},
  "artifact_paths": [],
  "base": "master"
}' > "$VALID_RUN/state.json"
chmod 600 "$VALID_RUN/state.json"
printf '%s\n' "{
  \"version\":1,\"type\":\"mad-review-admission\",\"task\":\"task-8\",\"phase\":\"review\",\"node\":\"task-8-review\",\"attempt\":\"a1\",\"round\":0,\"scopeDigest\":\"$(shasum -a 256 "$VALID_SCOPE" | cut -d' ' -f1)\"
}" > "$VALID_RUN/review-admissions/task-8-review-round-0.json"
printf '%s\n' "{
  \"version\":1,\"type\":\"mad-review-admission\",\"task\":\"task-8\",\"phase\":\"fix\",\"node\":\"task-8-fix\",\"attempt\":\"a1\",\"round\":1,\"scopeDigest\":\"$(shasum -a 256 "$VALID_SCOPE" | cut -d' ' -f1)\"
}" > "$VALID_RUN/review-admissions/task-8-fix-round-1.json"
chmod 600 "$VALID_RUN/review-admissions"/*.json
for phase in review fix; do
  attempt_dir="$VALID_RUN/nodes/task-8-$phase/attempts/a1"
  printf '%s\n' 'prompt' > "$attempt_dir/prompt.md"
  printf '%s\n' '{"changedFiles":["private_dot_local/private_share/agent-config/mad-contract.js"]}' > "$attempt_dir/result.json"
  printf '%s\n' 'log' > "$attempt_dir/log.md"
  printf '%s\n' "{\"run_id\":\"run-valid\",\"node\":\"task-8-$phase\",\"attempt\":\"a1\",\"artifact_paths\":[\"$attempt_dir/result.json\"]}" > "$attempt_dir/handoff.json"
  round=0; [ "$phase" = fix ] && round=1
  marker="$VALID_RUN/review-admissions/task-8-$phase-round-$round.json"
  printf '%s\n' "{\"run_id\":\"run-valid\",\"node\":\"task-8-$phase\",\"attempt\":\"a1\",\"round\":$round,\"state\":\"ok\",\"phase\":\"$phase\",\"phase_state\":\"ok\",\"next_action\":\"continue\",\"create_accepted\":true,\"child_ref\":\"child-$phase\",\"backend\":\"paseo-mcp\",\"backend_reason\":\"offline fixture\",\"parent_decision\":\"accepted\",\"review_admission\":\"$marker\"}" > "$attempt_dir/state.json"
  chmod 600 "$attempt_dir/result.json" "$attempt_dir/state.json" "$attempt_dir/handoff.json"
done
printf '%s\n' '{"task-8-review":{"workspace_id":"ws-review","cwd":"/tmp/ws-review","branch":"mad/task-8-review","integration":"merged","archived":true},"task-8-fix":{"workspace_id":"ws-fix","cwd":"/tmp/ws-fix","branch":"mad/task-8-fix","integration":"merged","archived":true}}' > "$VALID_RUN/workspaces.json"
chmod 600 "$VALID_RUN/workspaces.json"
out="$(bash "$RUNNER" "$VALID_RUN" 2>&1)"
assert_eq "$?" "0" "review guard: admission と scope が揃う run を受理する"

jq '.max_rounds = 5' "$VALID_RUN/state.json" > "$VALID_RUN/state.tmp" && mv "$VALID_RUN/state.tmp" "$VALID_RUN/state.json"
chmod 600 "$VALID_RUN/state.json"
out="$(bash "$RUNNER" "$VALID_RUN" 2>&1)"
assert_eq "$?" "1" "review guard: 任意の max_rounds を review policy に設定できない"
assert_contains "$out" "max_rounds" "review guard: 任意の max_rounds を拒否理由に示す"
jq '.max_rounds = 4' "$VALID_RUN/state.json" > "$VALID_RUN/state.tmp" && mv "$VALID_RUN/state.tmp" "$VALID_RUN/state.json"
chmod 600 "$VALID_RUN/state.json"

printf '%s\n' '{"changedFiles":["tests/other.sh"]}' > "$VALID_RUN/nodes/task-8-fix/attempts/a1/result.json"
chmod 600 "$VALID_RUN/nodes/task-8-fix/attempts/a1/result.json"
out="$(bash "$RUNNER" "$VALID_RUN" 2>&1)"
assert_eq "$?" "1" "review guard: validator は fix の scope 外変更を拒否する"
assert_contains "$out" "scope" "review guard: validator が scope 外変更を示す"
printf '%s\n' '{"changedFiles":["private_dot_local/private_share/agent-config/mad-contract.js"]}' > "$VALID_RUN/nodes/task-8-fix/attempts/a1/result.json"
chmod 600 "$VALID_RUN/nodes/task-8-fix/attempts/a1/result.json"

printf '%s\n' '{"version":1,"type":"mad-review-observations","task":"task-8","items":[{"id":"O-1","severity":"important","location":"outside-task","summary":"important observation","source":"re-reviewer"}]}' > "$VALID_OBSERVATIONS"
chmod 600 "$VALID_OBSERVATIONS"
jq '.state = "waiting_for_user" | .phase_state = "waiting_for_user"' \
  "$VALID_RUN/state.json" > "$VALID_RUN/state.tmp" && mv "$VALID_RUN/state.tmp" "$VALID_RUN/state.json"
chmod 600 "$VALID_RUN/state.json"
out="$(bash "$RUNNER" "$VALID_RUN" 2>&1)"
assert_eq "$?" "1" "review guard: scope 外 observation は user decision 無しで終えない"
assert_contains "$out" "final gate" "review guard: observation の最終確認を要求する"
DECISION="$TMP/review-decision.md"
printf '%s\n' 'scope expansion?' > "$DECISION"
chmod 600 "$DECISION"
jq --arg path "$DECISION" '.decision_request = $path' \
  "$VALID_RUN/state.json" > "$VALID_RUN/state.tmp" && mv "$VALID_RUN/state.tmp" "$VALID_RUN/state.json"
chmod 600 "$VALID_RUN/state.json"
out="$(bash "$RUNNER" "$VALID_RUN" 2>&1)"
assert_eq "$?" "0" "review guard: observation と user decision が揃えば終端を受理する"

out="$(node -e '
const c = require(process.argv[1])
console.log(c.MAD_REVIEW_MAX_ROUNDS,
  JSON.stringify(c.MAD_REVIEW_PHASE_ROUNDS.review),
  JSON.stringify(c.MAD_REVIEW_PHASE_ROUNDS["re-review"]))
' "$SHARE_DIR/mad-contract.js")"
assert_eq "$out" "4 [0,0] [1,3]" "review guard: max_rounds 4 と phase ごとの round 範囲"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
