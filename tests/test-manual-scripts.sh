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

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
