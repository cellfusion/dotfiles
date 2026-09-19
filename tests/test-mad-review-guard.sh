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

# --- 設計 5: 未解決の指摘をラウンドごとの成果物にする ---
OPEN_RUN="$TMP/run-open-findings"
OPEN_SCOPE="$TMP/open-scope.json"
mkdir -p "$OPEN_RUN"
printf '%s\n' '{
  "version": 1,
  "type": "mad-review-scope",
  "task": "task-8",
  "allowedFiles": ["private_dot_local/private_share/agent-config/mad-contract.js"],
  "findingIds": [],
  "outOfScopePath": "'"$TMP/open-observations.json"'"
}' > "$OPEN_SCOPE"
chmod 600 "$OPEN_SCOPE"

write_review_result "$TMP/round0-mixed.json" \
  '{"specVerdict":"issues","qualityVerdict":"needs_fixes","cannotVerify":null,"findings":[{"severity":"critical","summary":"c1","location":"f.js:1","fix":null,"planMandated":false},{"severity":"minor","summary":"m1","location":"f.js:2","fix":null,"planMandated":false},{"severity":"important","summary":"i1","location":"f.js:3","fix":null,"planMandated":null}]}'
bash "$RUNNER" --open-review-findings --share-dir "$SHARE_DIR" --run-dir "$OPEN_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/round0-mixed.json" >/dev/null 2>&1
assert_eq "$?" "0" "open findings: round 0 の結果から round 1 の一覧を作る"
ROUND1="$OPEN_RUN/review-open-findings/task-8-round-1.json"
assert_eq "$(jq -r '[.findings[].id] | join(",")' "$ROUND1")" "OF-1,OF-2" \
  "open findings: critical と important に OF-1 から順に id を振る"
assert_eq "$(jq -r '[.findings[].summary] | join(",")' "$ROUND1")" "c1,i1" \
  "open findings: severity minor の finding を一覧へ入れない"
assert_eq "$(jq -r '[.findings[].origin] | unique | join(",")' "$ROUND1")" "review-finding" \
  "open findings: review の指摘は origin を review-finding にする"
assert_eq "$(jq -r '.round' "$ROUND1")" "1" "open findings: 一覧の round を 1 にする"
assert_eq "$(stat -f '%Lp' "$ROUND1")" "600" "open findings: 一覧を mode 0600 で書く"

bash "$RUNNER" --open-review-findings --share-dir "$SHARE_DIR" --run-dir "$OPEN_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/round0-mixed.json" >/dev/null 2>&1
assert_eq "$?" "2" "open findings: 同じパスへの 2 回目の書き込みを拒否する"

PLAN_RUN="$TMP/run-plan-mandated"
mkdir -p "$PLAN_RUN"
write_review_result "$TMP/round0-plan.json" \
  '{"specVerdict":"issues","qualityVerdict":"approved","cannotVerify":[],"findings":[{"severity":"critical","summary":"c1","location":"f.js:1","fix":null,"planMandated":true}]}'
bash "$RUNNER" --open-review-findings --share-dir "$SHARE_DIR" --run-dir "$PLAN_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/round0-plan.json" >/dev/null 2>&1
assert_eq "$?" "2" "open findings: planMandated の finding を含む結果を拒否する"
assert_eq "$([ -e "$PLAN_RUN/review-open-findings/task-8-round-1.json" ] && printf yes || printf no)" "no" \
  "open findings: planMandated で拒否したとき一覧を作らない"

EMPTY_LIST_RUN="$TMP/run-empty-list"
mkdir -p "$EMPTY_LIST_RUN"
write_review_result "$TMP/round0-clean.json" \
  '{"specVerdict":"compliant","qualityVerdict":"approved","cannotVerify":null,"findings":[{"severity":"minor","summary":"m1","location":"f.js:2","fix":null,"planMandated":false}]}'
bash "$RUNNER" --open-review-findings --share-dir "$SHARE_DIR" --run-dir "$EMPTY_LIST_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/round0-clean.json" >/dev/null 2>&1
assert_eq "$?" "0" "open findings: 重い指摘が 0 件でも空配列の一覧を書いて成功する"
assert_eq "$(jq -r '.findings | length' "$EMPTY_LIST_RUN/review-open-findings/task-8-round-1.json")" "0" \
  "open findings: 空の一覧は findings を空配列にする"

MISSING_CV_RUN="$TMP/run-missing-cannot-verify"
mkdir -p "$MISSING_CV_RUN"
write_review_result "$TMP/round0-cv.json" \
  '{"specVerdict":"compliant","qualityVerdict":"approved","cannotVerify":["再試行の上限を diff から確認できない"],"findings":[]}'
bash "$RUNNER" --open-review-findings --share-dir "$SHARE_DIR" --run-dir "$MISSING_CV_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/round0-cv.json" >/dev/null 2>&1
assert_eq "$?" "2" "open findings: cannotVerify が非空なのに解消の記録が無ければ拒否する"

# --- 設計 5: ラウンドを進める ---
ADVANCE_RUN="$TMP/run-advance"
mkdir -p "$ADVANCE_RUN/review-open-findings"
write_round_list() {
  printf '%s\n' "$2" > "$1"
  chmod 600 "$1"
}
write_round_list "$ADVANCE_RUN/review-open-findings/task-8-round-1.json" \
  '{"version":1,"type":"mad-review-open-findings","task":"task-8","round":1,"findings":[{"id":"OF-1","severity":"critical","summary":"c1","location":"f.js:1","origin":"review-finding","originItem":null},{"id":"OF-2","severity":"important","summary":"i1","location":"f.js:3","origin":"cannot-verify","originItem":"再試行の上限"}]}'
write_review_result "$TMP/rere-round1.json" \
  '{"verdicts":[{"findingId":"OF-1","finding":"c1","addressed":true,"evidence":"fixed"},{"findingId":"OF-2","finding":"i1","addressed":false,"evidence":"f.js:9"}],"newBreakage":[{"severity":"important","summary":"n1","location":"g.js:1","fix":null,"planMandated":false},{"severity":"minor","summary":"n2","location":"g.js:2","fix":null,"planMandated":false}]}'
bash "$RUNNER" --advance-review-findings --share-dir "$SHARE_DIR" --run-dir "$ADVANCE_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/rere-round1.json" --round 1 >/dev/null 2>&1
assert_eq "$?" "0" "advance findings: round 1 の結果から round 2 の一覧を作る"
ROUND2="$ADVANCE_RUN/review-open-findings/task-8-round-2.json"
assert_eq "$(jq -r '[.findings[].id] | join(",")' "$ROUND2")" "OF-2,OF-3" \
  "advance findings: 未解消の id を引き継ぎ、newBreakage に未使用の番号を振る"
assert_eq "$(jq -r '.findings[0].summary' "$ROUND2")" "i1" \
  "advance findings: 引き継いだ指摘の summary を前のラウンドの値のままにする"
assert_eq "$(jq -r '.findings[0].severity' "$ROUND2")" "important" \
  "advance findings: 引き継いだ指摘の severity を前のラウンドの値のままにする"
assert_eq "$(jq -r '.findings[0].location' "$ROUND2")" "f.js:9" \
  "advance findings: evidence が非空なら location に使う"
assert_eq "$(jq -r '.findings[0].origin' "$ROUND2")" "cannot-verify" \
  "advance findings: 引き継いだ指摘の origin を写す"
assert_eq "$(jq -r '.findings[0].originItem' "$ROUND2")" "再試行の上限" \
  "advance findings: 引き継いだ指摘の originItem を写す"
assert_eq "$(jq -r '[.findings[].summary] | join(",")' "$ROUND2")" "i1,n1" \
  "advance findings: newBreakage の minor を一覧へ入れない"
assert_eq "$(jq -r '.round' "$ROUND2")" "2" "advance findings: 一覧の round を 2 にする"
assert_eq "$(stat -f '%Lp' "$ROUND2")" "600" "advance findings: 一覧を mode 0600 で書く"

bash "$RUNNER" --advance-review-findings --share-dir "$SHARE_DIR" --run-dir "$ADVANCE_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/rere-round1.json" --round 1 >/dev/null 2>&1
assert_eq "$?" "2" "advance findings: 同じパスへの 2 回目の書き込みを拒否する"

REWRITE_RUN="$TMP/run-rewrite"
mkdir -p "$REWRITE_RUN/review-open-findings"
write_round_list "$REWRITE_RUN/review-open-findings/task-8-round-1.json" \
  '{"version":1,"type":"mad-review-open-findings","task":"task-8","round":1,"findings":[{"id":"OF-1","severity":"critical","summary":"original summary","location":"f.js:1","origin":"review-finding","originItem":null}]}'
write_review_result "$TMP/rere-rewrite.json" \
  '{"verdicts":[{"findingId":"OF-1","finding":"rewritten summary","addressed":false,"evidence":null}],"newBreakage":[]}'
bash "$RUNNER" --advance-review-findings --share-dir "$SHARE_DIR" --run-dir "$REWRITE_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/rere-rewrite.json" --round 1 >/dev/null 2>&1
assert_eq "$?" "0" "advance findings: summary を書き換えた結果でも一覧を作る"
assert_eq "$(jq -r '.findings[0].summary' "$REWRITE_RUN/review-open-findings/task-8-round-2.json")" "original summary" \
  "advance findings: re-reviewer が書き換えた summary を採らない"
assert_eq "$(jq -r '.findings[0].location' "$REWRITE_RUN/review-open-findings/task-8-round-2.json")" "f.js:1" \
  "advance findings: evidence が空なら前のラウンドの location を使う"

LIMIT_RUN="$TMP/run-round-limit"
mkdir -p "$LIMIT_RUN/review-open-findings"
write_round_list "$LIMIT_RUN/review-open-findings/task-8-round-3.json" \
  '{"version":1,"type":"mad-review-open-findings","task":"task-8","round":3,"findings":[{"id":"OF-1","severity":"critical","summary":"c1","location":"f.js:1","origin":"review-finding","originItem":null}]}'
write_review_result "$TMP/rere-round3.json" \
  '{"verdicts":[{"findingId":"OF-1","finding":"c1","addressed":false,"evidence":null}],"newBreakage":[]}'
bash "$RUNNER" --advance-review-findings --share-dir "$SHARE_DIR" --run-dir "$LIMIT_RUN" \
  --scope-file "$OPEN_SCOPE" --result-file "$TMP/rere-round3.json" --round 3 >/dev/null 2>&1
assert_eq "$?" "2" "advance findings: 上限に達した run の次のラウンドを作らない"

# --- 設計 5: id の書式を強制する ---
for bad_id in F-1 OF0 OF-01; do
  bad_run="$TMP/run-bad-id-$bad_id"
  mkdir -p "$bad_run/review-open-findings"
  write_round_list "$bad_run/review-open-findings/task-8-round-1.json" \
    "{\"version\":1,\"type\":\"mad-review-open-findings\",\"task\":\"task-8\",\"round\":1,\"findings\":[{\"id\":\"$bad_id\",\"severity\":\"critical\",\"summary\":\"c1\",\"location\":\"f.js:1\",\"origin\":\"review-finding\",\"originItem\":null}]}"
  write_review_result "$TMP/rere-bad-$bad_id.json" \
    "{\"verdicts\":[{\"findingId\":\"$bad_id\",\"finding\":\"c1\",\"addressed\":false,\"evidence\":null}],\"newBreakage\":[]}"
  bash "$RUNNER" --advance-review-findings --share-dir "$SHARE_DIR" --run-dir "$bad_run" \
    --scope-file "$OPEN_SCOPE" --result-file "$TMP/rere-bad-$bad_id.json" --round 1 >/dev/null 2>&1
  assert_eq "$?" "2" "open findings: id の書式 $bad_id を拒否する"
done

# --- 設計 6: cannotVerify の解消を強制する ---
CV_RUN="$TMP/run-cannot-verify"
CV_OBSERVATIONS="$TMP/cv-observations.json"
CV_SCOPE="$TMP/cv-scope.json"
mkdir -p "$CV_RUN/review-cannot-verify"
printf '%s\n' '{
  "version": 1,
  "type": "mad-review-scope",
  "task": "task-8",
  "allowedFiles": ["private_dot_local/private_share/agent-config/mad-contract.js"],
  "findingIds": [],
  "outOfScopePath": "'"$CV_OBSERVATIONS"'"
}' > "$CV_SCOPE"
chmod 600 "$CV_SCOPE"
printf '%s\n' '{"version":1,"type":"mad-review-observations","task":"task-8","items":[{"id":"O-1","severity":"minor","location":"outside-task","summary":"先送りする項目","source":"task-reviewer"}]}' > "$CV_OBSERVATIONS"
chmod 600 "$CV_OBSERVATIONS"

write_review_result "$TMP/cv-empty.json" \
  '{"specVerdict":"compliant","qualityVerdict":"approved","cannotVerify":[],"findings":[]}'
bash "$RUNNER" --check-review-cannot-verify --share-dir "$SHARE_DIR" --run-dir "$CV_RUN" \
  --scope-file "$CV_SCOPE" --result-file "$TMP/cv-empty.json" >/dev/null 2>&1
assert_eq "$?" "0" "cannot verify: cannotVerify が空配列なら何も要求しない"

write_review_result "$TMP/cv-nonempty.json" \
  '{"specVerdict":"compliant","qualityVerdict":"approved","cannotVerify":["再試行の上限","先送りする項目"],"findings":[]}'
bash "$RUNNER" --check-review-cannot-verify --share-dir "$SHARE_DIR" --run-dir "$CV_RUN" \
  --scope-file "$CV_SCOPE" --result-file "$TMP/cv-nonempty.json" >/dev/null 2>&1
assert_eq "$?" "2" "cannot verify: 解消の記録が無ければ拒否する"

write_cannot_verify() {
  printf '%s\n' "$2" > "$1"
  chmod 600 "$1"
}
CV_RECORD="$CV_RUN/review-cannot-verify/task-8.json"
write_cannot_verify "$CV_RECORD" \
  '{"version":1,"type":"mad-review-cannot-verify","task":"task-8","items":[{"item":"再試行の上限","resolution":"confirmed_gap","detail":"spec が要求する再試行の上限が実装に無い","severity":"important","location":"f.js:120"},{"item":"先送りする項目","resolution":"deferred","detail":"この run では解消しない","severity":null,"location":null}]}'
bash "$RUNNER" --check-review-cannot-verify --share-dir "$SHARE_DIR" --run-dir "$CV_RUN" \
  --scope-file "$CV_SCOPE" --result-file "$TMP/cv-nonempty.json" >/dev/null 2>&1
assert_eq "$?" "2" "cannot verify: confirmed_gap があるのに round 1 の一覧が無ければ拒否する"

bash "$RUNNER" --open-review-findings --share-dir "$SHARE_DIR" --run-dir "$CV_RUN" \
  --scope-file "$CV_SCOPE" --result-file "$TMP/cv-nonempty.json" --cannot-verify-file "$CV_RECORD" >/dev/null 2>&1
assert_eq "$?" "0" "cannot verify: confirmed_gap を round 1 の一覧へ入れる"
CV_ROUND1="$CV_RUN/review-open-findings/task-8-round-1.json"
assert_eq "$(jq -r '.findings[0].origin' "$CV_ROUND1")" "cannot-verify" \
  "cannot verify: 入った finding の origin を cannot-verify にする"
assert_eq "$(jq -r '.findings[0].originItem' "$CV_ROUND1")" "再試行の上限" \
  "cannot verify: 入った finding の originItem を記録の item にする"
assert_eq "$(jq -r '.findings[0].summary' "$CV_ROUND1")" "spec が要求する再試行の上限が実装に無い" \
  "cannot verify: 入った finding の summary を記録の detail にする"
assert_eq "$(jq -r '.findings[0].severity' "$CV_ROUND1")" "important" \
  "cannot verify: 入った finding の severity を記録の severity にする"

bash "$RUNNER" --check-review-cannot-verify --share-dir "$SHARE_DIR" --run-dir "$CV_RUN" \
  --scope-file "$CV_SCOPE" --result-file "$TMP/cv-nonempty.json" >/dev/null 2>&1
assert_eq "$?" "0" "cannot verify: 記録と一覧が対応していれば受理する"

write_cannot_verify "$CV_RECORD" \
  '{"version":1,"type":"mad-review-cannot-verify","task":"task-8","items":[{"item":"再試行の上限","resolution":"confirmed_gap","detail":"spec が要求する再試行の上限が実装に無い","severity":"important","location":"f.js:120"},{"item":"先送りする項目","resolution":"deferred","detail":"この run では解消しない","severity":null,"location":null},{"item":"余分な項目","resolution":"satisfied","detail":"別タスクで満たしている","severity":null,"location":null}]}'
bash "$RUNNER" --check-review-cannot-verify --share-dir "$SHARE_DIR" --run-dir "$CV_RUN" \
  --scope-file "$CV_SCOPE" --result-file "$TMP/cv-nonempty.json" >/dev/null 2>&1
assert_eq "$?" "2" "cannot verify: cannotVerify に無い item を持つ記録を拒否する"

write_cannot_verify "$CV_RECORD" \
  '{"version":1,"type":"mad-review-cannot-verify","task":"task-8","items":[{"item":"再試行の上限","resolution":"confirmed_gap","detail":"spec が要求する再試行の上限が実装に無い","severity":"important","location":"f.js:120"},{"item":"先送りする項目","resolution":"deferred","detail":"この run では解消しない","severity":"minor","location":null}]}'
bash "$RUNNER" --check-review-cannot-verify --share-dir "$SHARE_DIR" --run-dir "$CV_RUN" \
  --scope-file "$CV_SCOPE" --result-file "$TMP/cv-nonempty.json" >/dev/null 2>&1
assert_eq "$?" "2" "cannot verify: deferred に severity を書いた記録を拒否する"

DEFER_RUN="$TMP/run-deferred-missing"
DEFER_OBSERVATIONS="$TMP/defer-observations.json"
DEFER_SCOPE="$TMP/defer-scope.json"
mkdir -p "$DEFER_RUN/review-cannot-verify"
printf '%s\n' '{
  "version": 1,
  "type": "mad-review-scope",
  "task": "task-8",
  "allowedFiles": ["private_dot_local/private_share/agent-config/mad-contract.js"],
  "findingIds": [],
  "outOfScopePath": "'"$DEFER_OBSERVATIONS"'"
}' > "$DEFER_SCOPE"
chmod 600 "$DEFER_SCOPE"
printf '%s\n' '{"version":1,"type":"mad-review-observations","task":"task-8","items":[]}' > "$DEFER_OBSERVATIONS"
chmod 600 "$DEFER_OBSERVATIONS"
write_cannot_verify "$DEFER_RUN/review-cannot-verify/task-8.json" \
  '{"version":1,"type":"mad-review-cannot-verify","task":"task-8","items":[{"item":"先送りする項目","resolution":"deferred","detail":"この run では解消しない","severity":null,"location":null}]}'
write_review_result "$TMP/cv-deferred.json" \
  '{"specVerdict":"compliant","qualityVerdict":"approved","cannotVerify":["先送りする項目"],"findings":[]}'
bash "$RUNNER" --check-review-cannot-verify --share-dir "$SHARE_DIR" --run-dir "$DEFER_RUN" \
  --scope-file "$DEFER_SCOPE" --result-file "$TMP/cv-deferred.json" >/dev/null 2>&1
assert_eq "$?" "2" "cannot verify: observations に無い項目を deferred にできない"

# --- 設計 6: run 全体の gate ---
GATE_RUN="$TMP/run-cannot-verify-gate"
GATE_SCOPE="$TMP/gate-scope.json"
GATE_OBSERVATIONS="$TMP/gate-observations.json"
mkdir -p "$GATE_RUN/review-admissions" "$GATE_RUN/nodes/task-8-review/attempts/a1"
printf '%s\n' '{
  "version": 1,
  "type": "mad-review-scope",
  "task": "task-8",
  "allowedFiles": ["private_dot_local/private_share/agent-config/mad-contract.js"],
  "findingIds": [],
  "outOfScopePath": "'"$GATE_OBSERVATIONS"'"
}' > "$GATE_SCOPE"
chmod 600 "$GATE_SCOPE"
printf '%s\n' '{
  "run_id": "run-cannot-verify-gate",
  "recipe": "implement",
  "state": "running",
  "phase": "review",
  "phase_state": "ok",
  "next_action": "resolve cannotVerify",
  "current_round": 0,
  "max_rounds": 4,
  "review_policy": {
    "max_rounds": 4,
    "scope_file": "'"$GATE_SCOPE"'",
    "out_of_scope_path": "'"$GATE_OBSERVATIONS"'"
  },
  "started_at": "2026-09-14T00:00:00Z",
  "backend": "paseo-mcp",
  "backend_reason": "offline fixture",
  "parent_decision": "bounded review",
  "active_nodes": [],
  "completed_nodes": [],
  "adopted_attempts": {"task-8-review": "a1"},
  "artifact_paths": [],
  "base": "master"
}' > "$GATE_RUN/state.json"
chmod 600 "$GATE_RUN/state.json"
GATE_DIGEST="$(shasum -a 256 "$GATE_SCOPE" | cut -d' ' -f1)"
printf '%s\n' "{\"version\":1,\"type\":\"mad-review-admission\",\"task\":\"task-8\",\"phase\":\"review\",\"node\":\"task-8-review\",\"attempt\":\"a1\",\"round\":0,\"scopeDigest\":\"$GATE_DIGEST\"}" \
  > "$GATE_RUN/review-admissions/task-8-review-round-0.json"
chmod 600 "$GATE_RUN/review-admissions/task-8-review-round-0.json"
GATE_ATTEMPT="$GATE_RUN/nodes/task-8-review/attempts/a1"
printf '%s\n' 'prompt' > "$GATE_ATTEMPT/prompt.md"
printf '%s\n' 'log' > "$GATE_ATTEMPT/log.md"
printf '%s\n' "{\"run_id\":\"run-cannot-verify-gate\",\"node\":\"task-8-review\",\"attempt\":\"a1\",\"artifact_paths\":[\"$GATE_ATTEMPT/result.json\"]}" > "$GATE_ATTEMPT/handoff.json"
printf '%s\n' "{\"run_id\":\"run-cannot-verify-gate\",\"node\":\"task-8-review\",\"attempt\":\"a1\",\"round\":0,\"state\":\"ok\",\"phase\":\"review\",\"phase_state\":\"ok\",\"next_action\":\"continue\",\"create_accepted\":true,\"child_ref\":\"child-review\",\"backend\":\"paseo-mcp\",\"backend_reason\":\"offline fixture\",\"parent_decision\":\"accepted\",\"review_admission\":\"$GATE_RUN/review-admissions/task-8-review-round-0.json\"}" > "$GATE_ATTEMPT/state.json"
printf '%s\n' '{"task-8-review":{"workspace_id":"ws-review","cwd":"/tmp/ws-review","branch":"mad/task-8-review","integration":"merged","archived":true}}' > "$GATE_RUN/workspaces.json"
chmod 600 "$GATE_RUN/workspaces.json" "$GATE_ATTEMPT/state.json" "$GATE_ATTEMPT/handoff.json"

# gate の対象外 1 件目: adopted attempt の result.json が cannotVerify という key を持たない run。
printf '%s\n' '{"changedFiles":["private_dot_local/private_share/agent-config/mad-contract.js"]}' > "$GATE_ATTEMPT/result.json"
chmod 600 "$GATE_ATTEMPT/result.json"
MAD_SHARE="$SHARE_DIR" bash "$RUNNER" "$GATE_RUN" >/dev/null 2>&1
assert_eq "$?" "0" "cannot verify gate: result.json が cannotVerify の key を持たない run を受理する"

# cannotVerify が非空で解消の記録が無い run。この result.json は 3 件目でも使う。
# 3 件目が呼ぶ `--open-review-findings` は `findings` が配列であることを先に要求するので、
# 空配列を入れておく。1 件目の result.json は `cannotVerify` という key を持たないままにする。
printf '%s\n' '{"changedFiles":["private_dot_local/private_share/agent-config/mad-contract.js"],"cannotVerify":["再試行の上限"],"findings":[]}' > "$GATE_ATTEMPT/result.json"
chmod 600 "$GATE_ATTEMPT/result.json"
out="$(MAD_SHARE="$SHARE_DIR" bash "$RUNNER" "$GATE_RUN" 2>&1)"
assert_eq "$?" "1" "cannot verify gate: 解消の記録が無い run を ok にしない"
assert_contains "$out" "cannotVerify" "cannot verify gate: 拒否理由に cannotVerify を示す"

# 記録と round 1 の一覧を揃えた run。
mkdir -p "$GATE_RUN/review-cannot-verify"
write_cannot_verify "$GATE_RUN/review-cannot-verify/task-8.json" \
  '{"version":1,"type":"mad-review-cannot-verify","task":"task-8","items":[{"item":"再試行の上限","resolution":"confirmed_gap","detail":"spec が要求する再試行の上限が実装に無い","severity":"important","location":"f.js:120"}]}'
bash "$RUNNER" --open-review-findings --share-dir "$SHARE_DIR" --run-dir "$GATE_RUN" \
  --scope-file "$GATE_SCOPE" --result-file "$GATE_ATTEMPT/result.json" \
  --cannot-verify-file "$GATE_RUN/review-cannot-verify/task-8.json" >/dev/null 2>&1
assert_eq "$?" "0" "cannot verify gate: 記録から round 1 の一覧を作る"
MAD_SHARE="$SHARE_DIR" bash "$RUNNER" "$GATE_RUN" >/dev/null 2>&1
assert_eq "$?" "0" "cannot verify gate: 記録と一覧が揃った run を受理する"

# --- 上限 4 に合わせた round 2 の run ---
ROUND2_RUN="$TMP/run-round-2"
ROUND2_SCOPE="$TMP/round-2-scope.json"
ROUND2_OBSERVATIONS="$TMP/round-2-observations.json"
ROUND2_ATTEMPT="$ROUND2_RUN/nodes/task-8-re-review/attempts/a1"
mkdir -p "$ROUND2_RUN/review-admissions" "$ROUND2_ATTEMPT"
printf '%s\n' '{
  "version": 1,
  "type": "mad-review-scope",
  "task": "task-8",
  "allowedFiles": ["private_dot_local/private_share/agent-config/mad-contract.js"],
  "findingIds": [],
  "outOfScopePath": "'"$ROUND2_OBSERVATIONS"'"
}' > "$ROUND2_SCOPE"
chmod 600 "$ROUND2_SCOPE"
printf '%s\n' '{
  "run_id": "run-round-2",
  "recipe": "implement",
  "state": "running",
  "phase": "re-review",
  "phase_state": "ok",
  "next_action": "continue",
  "current_round": 2,
  "max_rounds": 4,
  "review_policy": {
    "max_rounds": 4,
    "scope_file": "'"$ROUND2_SCOPE"'",
    "out_of_scope_path": "'"$ROUND2_OBSERVATIONS"'"
  },
  "started_at": "2026-09-14T00:00:00Z",
  "backend": "paseo-mcp",
  "backend_reason": "offline fixture",
  "parent_decision": "bounded review",
  "active_nodes": ["task-8-re-review"],
  "completed_nodes": [],
  "adopted_attempts": {},
  "artifact_paths": [],
  "base": "master"
}' > "$ROUND2_RUN/state.json"
chmod 600 "$ROUND2_RUN/state.json"
ROUND2_DIGEST="$(shasum -a 256 "$ROUND2_SCOPE" | cut -d' ' -f1)"
printf '%s\n' "{\"version\":1,\"type\":\"mad-review-admission\",\"task\":\"task-8\",\"phase\":\"re-review\",\"node\":\"task-8-re-review\",\"attempt\":\"a1\",\"round\":2,\"scopeDigest\":\"$ROUND2_DIGEST\"}" \
  > "$ROUND2_RUN/review-admissions/task-8-re-review-round-2.json"
chmod 600 "$ROUND2_RUN/review-admissions/task-8-re-review-round-2.json"
printf '%s\n' 'prompt' > "$ROUND2_ATTEMPT/prompt.md"
printf '%s\n' 'log' > "$ROUND2_ATTEMPT/log.md"
printf '%s\n' "{\"run_id\":\"run-round-2\",\"node\":\"task-8-re-review\",\"attempt\":\"a1\",\"artifact_paths\":[]}" > "$ROUND2_ATTEMPT/handoff.json"
printf '%s\n' "{\"run_id\":\"run-round-2\",\"node\":\"task-8-re-review\",\"attempt\":\"a1\",\"round\":2,\"state\":\"ok\",\"phase\":\"re-review\",\"phase_state\":\"ok\",\"next_action\":\"continue\",\"create_accepted\":true,\"child_ref\":\"child-re-review\",\"backend\":\"paseo-mcp\",\"backend_reason\":\"offline fixture\",\"parent_decision\":\"accepted\",\"review_admission\":\"$ROUND2_RUN/review-admissions/task-8-re-review-round-2.json\"}" > "$ROUND2_ATTEMPT/state.json"
printf '%s\n' '{"verdicts":[]}' > "$ROUND2_ATTEMPT/result.json"
printf '%s\n' '{"task-8-re-review":{"workspace_id":"ws-re-review","cwd":"/tmp/ws-re-review","branch":"mad/task-8-re-review","integration":"merged","archived":true}}' > "$ROUND2_RUN/workspaces.json"
chmod 600 "$ROUND2_RUN/workspaces.json" "$ROUND2_ATTEMPT/state.json" "$ROUND2_ATTEMPT/handoff.json" "$ROUND2_ATTEMPT/result.json"
bash "$RUNNER" "$ROUND2_RUN" >/dev/null 2>&1
assert_eq "$?" "0" "round limit: round 2 の re-review attempt を持つ run を受理する"

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
