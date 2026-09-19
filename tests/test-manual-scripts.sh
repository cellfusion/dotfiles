#!/usr/bin/env bash
# Task 6 の親オーケストレーション契約を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

mad_contract="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")"
mad_skill="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md")"

for token in MAD_TASK_BRIEF brief.md --waves --check-implement-result PROJECT_ROOT 'merge --abort'; do
  assert_contains "$mad_contract" "$token" "MAD contract: $token を持つ"
done

assert_contains "$mad_contract" 'MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"' \
  'path: task-brief を絶対 script path から使う'
assert_contains "$mad_skill" 'MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"' \
  'skill path: task-brief を初期化する'
assert_contains "$mad_contract" '"$MAD_TASK_BRIEF" "$PLAN_FILE" "$TASK_NUMBER" "$ATTEMPT_DIR/brief.md"' \
  'brief: attempt ごとに専用 brief を作る'
assert_contains "$mad_contract" 'initialPrompt' 'brief: create request の入力を明記する'
assert_contains "$mad_contract" 'brief.md の absolute path だけ' \
  'brief: implementer には brief path だけを渡す'
assert_contains "$mad_contract" 'plan 本文は渡さない' \
  'brief: implementer に plan 本文を渡さない'
assert_contains "$mad_contract" 'initial attempt と fix attempt' \
  'brief: initial と fix の両方を fresh brief にする'
assert_contains "$mad_contract" 'brief 作成に失敗' \
  'brief: 作成失敗時は create しない'
assert_contains "$mad_contract" 'mode `0600` の regular file' \
  'brief: private artifact とする'

assert_contains "$mad_contract" '"$MAD_PLAN_VALIDATE" --waves "$PLAN_FILE"' \
  'wave: validator から wave を得る'
assert_contains "$mad_contract" '次の wave' \
  'wave: 現 wave 完了前に次 wave を作らない'
assert_contains "$mad_contract" 'task number の昇順' \
  'merge: task number 順を固定する'
assert_contains "$mad_contract" 'git -C "$PROJECT_ROOT" merge --no-ff "mad/<run-id>/<node-id>"' \
  'merge: project root へ no-ff merge する'
assert_contains "$mad_contract" 'integration を `merged`' \
  'merge: 成功時に merged を記録する'
assert_contains "$mad_contract" 'integration を `pending`' \
  'merge: 衝突時は pending を維持する'
assert_contains "$mad_contract" 'repository-relative path' \
  'merge: 衝突ファイルを repository-relative で記録する'
assert_contains "$mad_contract" '衝突した 2 task' \
  'merge: 衝突した task 番号を記録する'
assert_contains "$mad_contract" '`Depends on` と `Files:`' \
  'merge: 両 task の plan metadata を記録する'
assert_contains "$mad_contract" '同一 wave の残り' \
  'merge: 衝突後は同一 wave を停止する'

assert_contains "$mad_contract" 'DONE' 'result: DONE 系分岐を持つ'
assert_contains "$mad_contract" 'exit `2`' 'result: validator failure を扱う'
assert_contains "$mad_contract" 'stderr の 1 行' 'result: validator 理由を転記する'
assert_contains "$mad_contract" 'BLOCKED' 'result: BLOCKED 分岐を持つ'
assert_contains "$mad_contract" 'NEEDS_CONTEXT' 'result: NEEDS_CONTEXT 分岐を持つ'
assert_contains "$mad_contract" 'summary' 'result: summary を転記する'
assert_contains "$mad_contract" 'non-null の `decisionRequestPath`' \
  'result: write role の decision request を要求する'
assert_contains "$mad_contract" '`waiting_for_user`' \
  'result: 判断待ちへ遷移する'
assert_contains "$mad_contract" 'archive しない' \
  'result: pending workspace を archive しない'

assert_contains "$mad_skill" 'plan-auditor は delivery role ではない' \
  'audit: delivery role 4役を維持する'
assert_contains "$mad_skill" '最初の implementer create 前' \
  'audit: implementer より前に実行する'
assert_contains "$mad_skill" '同一 run で一回だけ' \
  'audit: one-shot gate とする'
assert_contains "$mad_skill" 'findings が空' \
  'audit: findings が空のときだけ進む'
assert_contains "$mad_skill" '`question`、`options`、`recommendation`、`confirmed`' \
  'audit: decision request の4欄を転記する'
assert_contains "$mad_skill" 'state と phase_state を `waiting_for_user`' \
  'audit: finding があれば判断待ちにする'
assert_contains "$mad_skill" 'audit attempt が `ok`' \
  'audit: ok でなければ implementer を作らない'

dependency_line="$(grep -nF '"$MAD_PLAN_VALIDATE" "$PLAN_FILE"' \
  "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md" | head -1 | cut -d: -f1)"
waves_line="$(grep -nF '"$MAD_PLAN_VALIDATE" --waves "$PLAN_FILE"' \
  "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md" | head -1 | cut -d: -f1)"
if [ -n "$dependency_line" ] && [ -n "$waves_line" ] && [ "$dependency_line" -lt "$waves_line" ]; then
  _pass 'order: dependency validation の後に waves を得る'
else
  _fail 'order: dependency validation の後に waves を得る'
fi
TESTS_RUN=$((TESTS_RUN + 1))

assert_summary
