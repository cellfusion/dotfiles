#!/usr/bin/env bash
# Paseo config の launch 契約を実機で確認する手動 smoke。
set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say() { printf '\n## %s\n' "$*" >&2; }
note() { printf '%s\n' "$*" >&2; }

say "1. input と 0600 target copy を用意する"
note 'MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"'
note 'MAD_SHARE="${MAD_SHARE:-$HOME/.local/share/agent-config}"'
note 'AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"'
note 'MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter"'
note 'MAD_VALIDATE="$MAD_SCRIPTS/manual-orchestration-validate"'
note 'MAD_PLAN_VALIDATE="$MAD_SCRIPTS/paseo-plan-dependency-validate"'
note 'MAD_GENERATOR="${MAD_GENERATOR:-$HOME/.local/bin/generate-paseo-config}"'
note 'agent-config.json と ~/.paseo/config.json の copy は絶対 path で渡す。'
note 'copy は regular file かつ 0600 であることを確認する。'

say "2. Paseo の catalog を列挙する"
note '"$MAD_ADAPTER" list-providers'
note '"$MAD_ADAPTER" list-models --provider <provider>'
note '列挙結果から availability snapshot を 0600 の run artifact に保存する。'

say "3. launch を解決する"
note '"$MAD_GENERATOR" --input <absolute-input> --paseo-config <absolute-copy> resolve \\ '
note '  --project <absolute-project> --role task-reviewer --provenance manual-smoke \\ '
note '  --snapshot <absolute-snapshot>'
note 'resolve の成功後だけ create request を 0600 で作る。'

say "4. create は明示承認後だけ行う"
note 'PASEO_MAD_CREATE_APPROVED=1 を利用者が明示してから mcp__paseo__create_agent を呼ぶ。'
note '承認なし、--dry-run、resolve 失敗時は create も chezmoi apply も実行しない。'
note 'rollback は create 前なら artifact を破棄し、create 後なら Paseo の子を archive する。'

say "merge 前に回す"
note '1. bash tests/run-tests.sh'
note '2. bash tests/manual/herdr-smoke.sh --dry-run'
note '3. 利用者の明示承認後だけ、Paseo 実機で catalog、resolve、create を 1 回通す'

if [ "$DRY" -eq 1 ]; then
  exit 0
fi

if [ "${PASEO_MAD_CREATE_APPROVED:-0}" != 1 ]; then
  printf 'herdr-smoke: 実 MCP の create には PASEO_MAD_CREATE_APPROVED=1 が必要\n' >&2
  exit 2
fi

printf 'herdr-smoke: 実行条件を満たした。上記の絶対 path を使って承認済みの create を実行する。\n' >&2
