#!/usr/bin/env bash
# tests/manual/ のスクリプトが --dry-run で期待するコマンドを出すことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

out="$(bash "$CHEZMOI_SOURCE/tests/manual/herdr-smoke.sh" --dry-run 2>&1)"

for script in tests/manual/herdr-smoke.sh tests/test-schemas.sh; do
  assert_eq "$(stat -f '%Lp' "$CHEZMOI_SOURCE/$script")" "755" \
    "mode: $script は executable"
done

# Paseo catalog、launch、承認 gate を順に出す。
for step in "list-providers" "list-models" "agent-config" "mcp__paseo__create_agent"; do
  assert_contains "$out" "$step" "smoke: $step を案内する"
done
assert_contains "$out" "0600" "smoke: artifact の権限を示す"
assert_contains "$out" "PASEO_MAD_CREATE_APPROVED=1" "smoke: create の明示承認を求める"
assert_contains "$out" "chezmoi apply も実行しない" "smoke: dry-run で apply しない"

# merge 前に回すコマンドを smoke 自身が名指しする（プラン 1 で入れた gate を保つ）。
# fake を使うテストは起動引数しか見ないので、実機で 1 度も走らせずに merge へ
# 進める穴を塞ぐ。
assert_contains "$out" "bash tests/run-tests.sh" "gate: 全テストを名指しする"
assert_contains "$out" "bash tests/manual/herdr-smoke.sh --dry-run" "gate: dry-run を名指しする"
assert_contains "$out" "利用者の明示承認後" "gate: 実機 create の承認を求める"

mad_source="$(cat "$CHEZMOI_SOURCE/tests/manual/mad-orchestration-smoke.sh")"
assert_contains "$mad_source" "umask 077" "mad smoke: artifact write を private umask にする"
assert_contains "$mad_source" "chmod 700" "mad smoke: run directory を 0700 に固定する"
assert_contains "$mad_source" "chmod 600" "mad smoke: state artifact を 0600 に固定する"
assert_contains "$mad_source" "stat -f '%Lp' \"\$RUN_DIR\"" "mad smoke: run directory の mode を検証する"
assert_contains "$mad_source" "stat -f '%Lp' \"\$RUN_DIR/state.json\"" "mad smoke: state artifact の mode を検証する"
for forbidden in \
  "paseo inspect" \
  "paseo logs" \
  "paseo wait" \
  "paseo stop"; do
  assert_not_contains "$mad_source" "$forbidden" "mad smoke: source に直接経路 $forbidden を残さない"
done


# ---------------------------------------------------------------------------
# MAD オーケストレーションの実地 smoke。
#
# fixture test は state と成果物の形しか見ない。実 backend で子が 1 つも起動
# しないまま全部緑になる穴が残る。ここでは smoke が実機の手順を欠かさず出すか
# だけを検証する。実際の起動は手動実行が行う。
# ---------------------------------------------------------------------------
mad_smoke="$CHEZMOI_SOURCE/tests/manual/mad-orchestration-smoke.sh"
mad="$(bash "$mad_smoke" --dry-run 2>&1)"
mad_contract="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")"

# 配布先のskillは裸のコマンド名や未定義のAGENT_CONFIGに依存しない。
for mad_path_contract in \
  'MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"' \
  'MAD_SHARE="${MAD_SHARE:-$HOME/.local/share/agent-config}"' \
  'AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"' \
  'MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter"' \
  'MAD_VALIDATE="$MAD_SCRIPTS/manual-orchestration-validate"' \
  'MAD_PLAN_VALIDATE="$MAD_SCRIPTS/paseo-plan-dependency-validate"'; do
  assert_contains "$mad_contract" "$mad_path_contract" \
    "path contract: $mad_path_contract を初期化する"
done
assert_contains "$mad_contract" "checkout 専用である" \
  "path contract: unit gate が repository 専用であることを明記する"
for mad_smoke_path in \
  'MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"' \
  'MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter"' \
  'MAD_VALIDATE="$MAD_SCRIPTS/manual-orchestration-validate"'; do
  assert_contains "$mad" "$mad_smoke_path" \
    "path contract: mad smoke が $mad_smoke_path を出す"
done
assert_contains "$out" 'MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"' \
  "path contract: herdr smoke がMAD script pathを出す"
assert_contains "$out" 'MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter"' \
  "path contract: herdr smoke がadapter pathを出す"
multi_agent_skill="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md")"
assert_contains "$multi_agent_skill" 'PASEO_UNIT_GATE="${PASEO_UNIT_GATE:-$PROJECT_ROOT/tests/manual/paseo-unit-gate.sh}"' \
  "path contract: MAD skill がrepository gate pathを初期化する"

# review/fix は固定上限と immutable scope を持つ。scope 外の重要事項は loop に戻さず、
# 最終 gate の一回の user decision へ送る。
for review_guard_step in \
  '"$MAD_VALIDATE" --prepare-review' \
  "max_rounds は 4" \
  "scope 外" \
  "out-of-scope" \
  "最終 gate" \
  "新しい fix/review を起動しない"; do
  assert_contains "$mad_contract" "$review_guard_step" \
    "review guard: 共通契約に $review_guard_step を明記する"
done
for role_prompt in task-reviewer re-reviewer final-reviewer implementer; do
  role_text="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/prompts/$role_prompt.md")"
  assert_contains "$role_text" "scope" "review guard: $role_prompt prompt に scope を明記する"
done
assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/prompts/re-reviewer.md")" \
  "hotfix node" "review guard: re-reviewer は hotfix node を増やさない"

# --- backend は Paseo MCP だけである ---
assert_contains "$mad" '"$MAD_VALIDATE" --select-backend' \
  "mad smoke: backend selector を叩く"
assert_contains "$mad" "paseo-mcp" "mad smoke: Paseo MCP を優先する"
assert_not_contains "$mad" "paseo-mcp-adapter create-agent" \
  "mad smoke: adapter に create の境界を残さない"
assert_contains "$mad" 'wait と stop の境界はすべて "$MAD_ADAPTER" に限定する' \
  "mad smoke: wait/stop の唯一経路を示す"
assert_contains "$mad" "mcp__paseo__create_agent" \
  "mad smoke: create は公式 MCP tool で行う"
# create の順序を smoke が明示する。request を検証せずに create を呼ばせない。
for create_step in \
  '"$MAD_VALIDATE" --exercise-success' \
  "mcp-create.json" \
  "assertMadCreateRequestV1" \
  '"$MAD_VALIDATE" --prepare-create' \
  '"$MAD_VALIDATE" --exercise-accepted'; do
  assert_contains "$mad" "$create_step" "mad smoke: create の手順に $create_step を出す"
done
assert_contains "$mad" "request を検証してから create を呼ぶ" \
  "mad smoke: 未検証 request で create しないと明示する"
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
assert_contains "$mad" '"$MAD_ADAPTER" wait-agent' "mad smoke: adapter で完了を待つ"
assert_not_contains "$mad" "paseo inspect" "mad smoke: raw inspect を呼ばない"
assert_not_contains "$mad" "paseo logs" "mad smoke: raw logs を呼ばない"
assert_not_contains "$mad" "paseo wait" "mad smoke: raw wait を呼ばない"
assert_not_contains "$mad" "mcp__paseo__get_agent_status" "mad smoke: 親から直接 status MCP を呼ばない"
assert_contains "$mad" "attempts/" "mad smoke: attempt の記録場所を出す"
assert_contains "$mad" "sanitized response" "mad smoke: adapter response を縮約して読む"
assert_contains "$mad" "0600 の state/evidence" "mad smoke: state/evidence だけを読む"

# --- 停止方法 ---
assert_contains "$mad" '"$MAD_ADAPTER" stop-agent' "mad smoke: adapter で実行中の子を止める"
assert_not_contains "$mad" "paseo stop" "mad smoke: raw stop を呼ばない"
assert_not_contains "$mad" "mcp__paseo__cancel_agent" "mad smoke: 親から直接 cancel MCP を呼ばない"
assert_contains "$mad" '"state": "stopped"' "mad smoke: 停止を run state に残す"

# --- 実行結果として出す情報 ---
assert_contains "$mad" "run ID" "mad smoke: run ID を出す"
assert_contains "$mad" "backend" "mad smoke: 選んだ backend を出す"
assert_contains "$mad" '"$MAD_VALIDATE" "$RUN_DIR"' \
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

for script in tests/manual/herdr-smoke.sh tests/manual/mad-orchestration-smoke.sh \
  tests/manual/mad-representative-run.sh tests/manual/paseo-unit-gate.sh; do
  assert_eq "$(grep -c 'generate-paseo-config' "$CHEZMOI_SOURCE/$script")" "0" "$script: 旧 CLI 名が残らない"
done
assert_eq "$(grep -c 'agentProfiles' "$CHEZMOI_SOURCE/tests/manual/paseo-unit-gate.sh")" "0" \
  "paseo-unit-gate: agentProfiles の shape 検査が残らない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
