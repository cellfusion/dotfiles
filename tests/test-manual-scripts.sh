#!/usr/bin/env bash
# tests/manual/ のスクリプトが --dry-run で期待するコマンドを出すことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

out="$(bash "$CHEZMOI_SOURCE/tests/manual/herdr-smoke.sh" --dry-run 2>&1)"

# 実 CLI が headless で動くことを確かめる部分。
assert_contains "$out" "codex exec --json" "smoke: codex を headless で叩く"
assert_contains "$out" "--output-schema" "smoke: 出力スキーマを渡す"
assert_contains "$out" 'approval_policy="never"' "smoke: 承認を切る"
assert_contains "$out" "claude -p --safe-mode" "smoke: claude を headless で叩く"
assert_contains "$out" "--json-schema" "smoke: claude にスキーマを渡す"
assert_contains "$out" "--tools Read,Grep,Glob" "smoke: reviewer は読み取り専用"
assert_not_contains "$out" "dontAsk" "smoke: dontAsk を使わない"

# worktrunk が worktree を作り、herdr には登録しないことを確かめる部分。
assert_contains "$out" "wt switch --create" "smoke: worktree は worktrunk が作る"
assert_contains "$out" "worktrunk/agent.toml" "smoke: agent 専用 config を使う"
assert_not_contains "$out" "herdr worktree create" "smoke: herdr で worktree を作らない"

# 通しの実行。
assert_contains "$out" "sdd-run --plan" "smoke: driver を通しで回す"
assert_contains "$out" '"status": "COMPLETE"' "smoke: 期待する結果を明示する"
assert_contains "$out" "progress.md" "smoke: ledger の場所を出す"

# merge 前に回すコマンドを smoke 自身が名指しする（プラン 1 で入れた gate を保つ）。
# fake を使うテストは起動引数しか見ないので、実機で 1 度も走らせずに merge へ
# 進める穴を塞ぐ。
assert_contains "$out" "bash tests/run-tests.sh" "gate: 全テストを名指しする"
assert_contains "$out" "workflows/test-workflows.mjs" "gate: run-tests.sh の対象外の workflow テストを名指しする"
assert_contains "$out" "bash tests/manual/herdr-smoke.sh --dry-run" "gate: dry-run を名指しする"
assert_contains "$out" "HERDR_ENV=1 の実機" "gate: 実機で 1 度通すことを求める"


# ---------------------------------------------------------------------------
# MAD オーケストレーションの実地 smoke。
#
# fixture test は state と成果物の形しか見ない。実 backend で子が 1 つも起動
# しないまま全部緑になる穴が残る。ここでは smoke が実機の手順を欠かさず出すか
# だけを検証する。実際の起動は手動実行が行う。
# ---------------------------------------------------------------------------
mad_smoke="$CHEZMOI_SOURCE/tests/manual/mad-orchestration-smoke.sh"
mad="$(bash "$mad_smoke" --dry-run 2>&1)"

# --- backend は Paseo MCP を優先し、使えないときだけ native subagent にする ---
assert_contains "$mad" "manual-orchestration-validate --select-backend" \
  "mad smoke: backend selector を叩く"
assert_contains "$mad" "MANUAL_ORCHESTRATION_PASEO_MCP_AVAILABLE" \
  "mad smoke: Paseo MCP の可否をどう判定するか出す"
assert_contains "$mad" "paseo-mcp" "mad smoke: Paseo MCP を優先する"
assert_contains "$mad" "mcp__paseo__create_agent" "mad smoke: Paseo MCP での起動方法を出す"
assert_contains "$mad" "[dispatch-subagent: researcher]" \
  "mad smoke: native subagent への fallback 方法を出す"
assert_contains "$mad" "自動で切り替えない" "mad smoke: 実行開始後に backend を替えない"
assert_not_contains "$mad" "herdr" "mad smoke: Herdr を backend にしない"

# --- research は 3 観点の子を並列に起動する ---
for n in research-1 research-2 research-3; do
  assert_contains "$mad" "$n" "mad smoke: $n を起動する"
done
for p in "現状と確認済みの事実" "制約とリスク" "代替案"; do
  assert_contains "$mad" "$p" "mad smoke: 既定観点の $p を出す"
done

# --- 親 gate。3 子が ok になるまで統合役を起動しない ---
assert_contains "$mad" "3 件すべてが ok" "mad smoke: 統合の前提を出す"
assert_contains "$mad" "parent_decision" "mad smoke: 親の判断を記録させる"
assert_contains "$mad" "本文を親の会話へ転記しない" "mad smoke: 子の本文を親へ集めない"

# --- 統合 ---
assert_contains "$mad" "synthesis" "mad smoke: 統合 node を作る"
assert_contains "$mad" "artifact_paths" "mad smoke: 統合役へ絶対パスだけを渡す"

# --- 観測方法 ---
assert_contains "$mad" "paseo ls" "mad smoke: 実行中の子の一覧方法を出す"
assert_contains "$mad" "paseo logs" "mad smoke: 子のログの見方を出す"
assert_contains "$mad" "mcp__paseo__get_agent_status" "mad smoke: MCP での状態確認方法を出す"
assert_contains "$mad" "attempts/" "mad smoke: attempt の記録場所を出す"

# --- 停止方法 ---
assert_contains "$mad" "paseo stop" "mad smoke: 実行中の子の止め方を出す"
assert_contains "$mad" "mcp__paseo__cancel_agent" "mad smoke: MCP での止め方を出す"
assert_contains "$mad" '"state": "stopped"' "mad smoke: 停止を run state に残す"

# --- 実行結果として出す情報 ---
assert_contains "$mad" "run ID" "mad smoke: run ID を出す"
assert_contains "$mad" "backend" "mad smoke: 選んだ backend を出す"
assert_contains "$mad" "manual-orchestration-validate \"\$RUN_DIR\"" \
  "mad smoke: 成果物契約の検証コマンドを出す"

# --- 常時 suite から外れている ---
# run-tests.sh は tests/ 直下の test-*.sh だけを回す。tests/manual/ に置く限り
# 実機と課金を伴う smoke が CI 相当の全件実行に混ざらない。
suite_files="$(cd "$CHEZMOI_SOURCE/tests" && printf '%s\n' test-*.sh)"
assert_not_contains "$suite_files" "mad-orchestration-smoke" \
  "mad smoke: 常時 suite に含まれない"

# --- 使い方が単体で引ける ---
mad_help="$(bash "$mad_smoke" --help 2>&1)"
assert_contains "$mad_help" "--dry-run" "mad smoke: --help が dry-run を案内する"
assert_contains "$mad_help" "--report" "mad smoke: --help が実行済み run の検証方法を案内する"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
