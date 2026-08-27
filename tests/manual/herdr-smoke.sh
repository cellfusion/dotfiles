#!/usr/bin/env bash
# SDD の headless 実行基盤が実機で成立するかを確かめる。
# 手動実行専用。run-tests.sh の対象外（tests/manual/ にあるため）。
#
#   bash tests/manual/herdr-smoke.sh --dry-run   叩くコマンドを表示するだけ
#   bash tests/manual/herdr-smoke.sh             実際に検証する
# 実行前の HEAD を控え、実行後に必要なら git reset --hard <実行前の HEAD> で戻す。
# その後 wt remove と git branch -d で worktree と task branch を片付ける。
set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

TMP="$(mktemp -d)"
SCRIPTS="$HOME/.agents/skills/subagent-driven-development/scripts"

# dry-run では実行せずコマンドだけ出す。実行時は実際に叩いて出力を返す。
run() {
  printf '%s\n' "$*" >&2
  [ "$DRY" -eq 1 ] && return 0
  "$@"
}

say() { printf '\n## %s\n' "$*" >&2; }

say "1. codex を headless で叩く（承認が出ないこと）"
printf '{"type":"object","required":["status"],"properties":{"status":{"type":"string"}}}' \
  > "$TMP/schema.json"
run codex exec --json \
  --output-schema "$TMP/schema.json" \
  --output-last-message "$TMP/codex-last.json" \
  -m gpt-5.6-luna -c model_reasoning_effort=low \
  -c 'sandbox_mode="workspace-write"' \
  -c 'approval_policy="never"' \
  -c "sandbox_workspace_write.writable_roots=[\"$TMP\"]" \
  'status を DONE にして返す。'

say "2. claude を headless で叩く（reviewer は read 役）"
# read 役は --tools でツール面を閉じ、permission-mode を渡さない。
run claude -p --safe-mode \
  --setting-sources "" \
  --model sonnet --effort medium \
  --output-format json \
  --json-schema '{"type":"object","required":["status"],"properties":{"status":{"type":"string"}}}' \
  --tools Read,Grep,Glob \
  'status を DONE にして返す。'

say "3. claude を headless で叩く（implementer は write 役）"
# write 役は --tools でツール面を閉じられないので、--permission-mode auto で許可を与える。
run claude -p --safe-mode \
  --setting-sources "" \
  --model sonnet --effort medium \
  --output-format json \
  --json-schema '{"type":"object","required":["status"],"properties":{"status":{"type":"string"}}}' \
  --permission-mode auto \
  --add-dir "$TMP" \
  "$TMP/write-probe.txt に ok と 1 行だけ書き、status を DONE にして返す。"
printf '確認: %s/write-probe.txt が作られ、承認ダイアログが出ないこと\n' "$TMP" >&2

say "4. worktrunk で worktree を作る（herdr に登録されないこと）"
run wt switch --create "sdd-smoke-$$" --base HEAD \
  --no-cd --format json -y --config "$HOME/.config/worktrunk/agent.toml"
printf '確認: herdr workspace list に sdd-smoke-%s が現れないこと\n' "$$" >&2

# 通しの実行に使う極小のプラン。誰かが SMOKE_PLAN を用意する前提にしない。
PLAN="${SMOKE_PLAN:-$TMP/smoke-plan.md}"
if [ ! -f "$PLAN" ]; then
  cat > "$PLAN" <<'SMOKEPLAN'
# smoke plan

## Global Constraints

- シェルスクリプトは `#!/usr/bin/env bash` と `set -euo pipefail` で始める

## Task 1: smoke-a を足す

**Depends on:** なし

**Files:**
- Create: `tests/smoke-a.sh`

`tests/smoke-a.sh` を新規に作る。実行すると `smoke-a ok` と 1 行出して 0 で終わる。
`bash tests/smoke-a.sh` で動作を確認する。

## Task 2: smoke-b を足す

**Depends on:** なし

**Files:**
- Create: `tests/smoke-b.sh`

`tests/smoke-b.sh` を新規に作る。実行すると `smoke-b ok` と 1 行出して 0 で終わる。
`bash tests/smoke-b.sh` で動作を確認する。
SMOKEPLAN
fi

say "5. 通しの実行"
printf '確認: プランを 1 本用意し、次を叩く\n' >&2
run "$SCRIPTS/sdd-run" --plan "$PLAN"

say "期待する結果"
printf '{ "status": "COMPLETE", "runId": ..., "ledger": ... } が 1 行で返ること\n' >&2
printf 'ledger（<workspace>/<runId>/progress.md）に Wave と Task の行があること\n' >&2
printf '承認ダイアログが 1 度も出ないこと\n' >&2
printf 'herdr の agent 一覧に子エージェントが現れないこと\n' >&2

say "後片付け"
run wt remove "sdd-smoke-$$" --no-delete-branch --foreground -y \
  --config "$HOME/.config/worktrunk/agent.toml"
run rm -rf "$TMP"

# ---------------------------------------------------------------------------
# merge 前に回すもの。
#
# fake を使うテストは起動引数しか見ないので、全部緑のまま実経路が 1 タスクも
# 完走しないことがある。実際に走らせる 4 番目を飛ばして merge しない。
# ---------------------------------------------------------------------------
printf '\n## merge 前に回す\n' >&2
printf '1. bash tests/run-tests.sh\n' >&2
printf '2. node ~/.config/claude/skills/subagent-driven-development/workflows/test-workflows.mjs（run-tests.sh の対象外）\n' >&2
printf '3. bash tests/manual/herdr-smoke.sh --dry-run\n' >&2
printf '4. HERDR_ENV=1 の実機で bash tests/manual/herdr-smoke.sh を 1 回通し、次の 4 つを目で確かめる\n' >&2
printf '   - 2 番の read 役が structured_output を返すこと\n' >&2
printf '   - 3 番の write 役が write-probe.txt を作り、承認ダイアログが出ないこと\n' >&2
printf '   - 5 番の sdd-run が COMPLETE で終わること\n' >&2
printf '   - ledger に Wave と Task の行が残ること\n' >&2
