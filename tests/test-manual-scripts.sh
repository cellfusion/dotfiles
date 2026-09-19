#!/usr/bin/env bash
# Task 6 の親オーケストレーション契約を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

mad_contract="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")"
mad_skill="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md")"

assert_before() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*"$3"*) _pass "$4" ;;
    *) _fail "$4" "期待した順序が無い: $2 -> $3" ;;
  esac
}

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

common_steps="$(sed -n '/^## 共通手順$/,/^## /p' \
  "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md")"
assert_before "$common_steps" 'plan-auditor 用の provider/model discovery' \
  'plan-auditor の launch を検証' \
  'audit order: provider/model 解決後に launch を検証する'
assert_before "$common_steps" 'plan-auditor の launch を検証' \
  'plan-auditor の create request' \
  'audit order: launch 検証後に create request を作る'
assert_before "$common_steps" 'plan-auditor の create request' \
  '`plan-audit` node を create' \
  'audit order: request 準備後に plan-audit を create する'
assert_before "$common_steps" '`plan-audit` node を create' \
  'audit attempt の state、result、handoff を検証' \
  'audit order: create 後に audit 完了を検証する'
assert_before "$common_steps" 'audit attempt の state、result、handoff を検証' \
  '最初の wave の implementer 用' \
  'audit order: audit 成功後だけ implementer を準備する'

result_contract="$(sed -n '/implementer の終了後、親は `status` で分岐する/,/^## delivery role map$/p' \
  "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")"
done_contract="$(printf '%s\n' "$result_contract" | sed -n '1,/`BLOCKED` または `NEEDS_CONTEXT`/p')"
blocked_contract="$(printf '%s\n' "$result_contract" | sed -n '/`BLOCKED` または `NEEDS_CONTEXT`/,$p')"
assert_before "$done_contract" '`DONE` と `DONE_WITH_CONCERNS` だけ' \
  '"$MAD_VALIDATE" --check-implement-result' \
  'result order: DONE 系だけ post-commit check を実行する'
assert_before "$done_contract" 'exit `2`' '`waiting_for_user`' \
  'result order: validator exit 2 を判断待ちへ遷移する'
assert_contains "$done_contract" 'integration を `pending` のままにして archive しない' \
  'result branch: validator failure は pending・archive 禁止にする'
assert_not_contains "$blocked_contract" '"$MAD_VALIDATE" --check-implement-result' \
  'result branch: BLOCKED/NEEDS_CONTEXT は post-commit check を実行しない'
assert_before "$blocked_contract" '`summary`' 'non-null の `decisionRequestPath`' \
  'result order: BLOCKED 系の summary と判断要求を転記する'
assert_before "$blocked_contract" 'non-null の `decisionRequestPath`' '`waiting_for_user`' \
  'result order: BLOCKED 系の判断要求後に waiting_for_user にする'
assert_contains "$blocked_contract" 'integration は `pending` のままにして archive しない' \
  'result branch: BLOCKED 系は pending・archive 禁止にする'

merge_contract="$(sed -n '/各 wave の採用済み task は task number の昇順/,/^## recipe と判断要求$/p' \
  "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")"
assert_before "$merge_contract" 'merge --no-ff' 'merge 成功時だけ' \
  'merge order: no-ff 成功後だけ merged にする'
assert_before "$merge_contract" 'merge 成功時だけ' 'merge --abort' \
  'merge branch: 成功処理と衝突処理を分ける'
assert_before "$merge_contract" 'merge --abort' 'integration を `pending`' \
  'merge order: abort 後も integration を pending に保つ'
assert_before "$merge_contract" 'integration を `pending`' '`waiting_for_user`' \
  'merge order: pending 記録後に waiting_for_user にする'
assert_before "$merge_contract" '`waiting_for_user`' 'repository-relative path' \
  'merge order: 判断待ちで衝突情報を decision request に書く'
assert_before "$merge_contract" '`Depends on` と `Files:`' '同一 wave の残り' \
  'merge order: 衝突情報を書いてから wave を停止する'

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
