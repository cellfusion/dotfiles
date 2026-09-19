#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

table="$(render_template "agent-skills/_workflow-table.md" "codex")"
for skill in brainstorming systematic-debugging multi-agent-development \
             finishing-a-development-branch verification-before-completion \
             receiving-code-review; do
  assert_contains "$table" "$skill" "起動表に $skill がある"
done

# Codex と opencode の instructions が起動表を取り込む。
for f in private_dot_config/codex/AGENTS.md.tmpl private_dot_config/opencode/AGENTS.md.tmpl; do
  assert_eq "$([ -f "$CHEZMOI_SOURCE/$f" ] && echo yes || echo no)" "yes" "$f がある"
  body="$(cat "$CHEZMOI_SOURCE/$f")"
  assert_contains "$body" "agent-skills/_workflow-table.md" "$f が起動表を取り込む"
done

codex_agents="$(cat "$CHEZMOI_SOURCE/private_dot_config/codex/AGENTS.md.tmpl")"
assert_contains "$codex_agents" 'chezmoi diff' "Codex instructions: 編集前に差分を確認する"
assert_contains "$codex_agents" 'chezmoi apply' "Codex instructions: apply の承認規則がある"
assert_contains "$codex_agents" 'private_dot_config/docs/keybindings.md' "Codex instructions: キーバインド文書を同期する"
assert_contains "$codex_agents" '~/.local/share/chezmoi/' "Codex instructions: chezmoi ソース側を編集する"

# --- Codex instructions が code mode での MCP ツールの呼び方を持っている ---
# code mode の codex は MCP ツールを通常のツール一覧に出さない。Paseo のスキルは
# 素の名前で書かれているため、対応づけを書いておかないと CLI に逃げる。
assert_contains "$codex_agents" 'tools.mcp__' "Codex instructions: MCP ツールの呼び名を書く"
assert_contains "$codex_agents" 'Object.keys(tools)' "Codex instructions: ツール一覧の確認方法を書く"
assert_contains "$codex_agents" 'tools.mcp__paseo__list_agents' "Codex instructions: Paseo スキルの素の名前との対応を書く"

# --- CLAUDE.md が実在しないものを指していない ---
# 過去の移行で消えた設定への言及が残ると、毎セッション誤情報を配ることになる。
claude_md="$(cat "$CHEZMOI_SOURCE/CLAUDE.md")"
for s in "wezterm/" "alacritty/" "aquaSKK/" ".ideavimrc" "claudecode.lua" \
         "install.ps1" "skkeleton" "denops" "WezTerm" "Alacritty"; do
  assert_not_contains "$claude_md" "$s" "CLAUDE.md: 実在しない $s に言及しない"
done

# --- CLAUDE.md が実在するものを指している ---
assert_contains "$claude_md" "sidekick.lua" "CLAUDE.md: AI 連携が sidekick.nvim だと書いてある"
assert_contains "$claude_md" "tests/run-tests.sh" "CLAUDE.md: テストの回し方が書いてある"
assert_contains "$claude_md" ".chezmoiscripts/" "CLAUDE.md: インストールスクリプトの場所が書いてある"
assert_contains "$claude_md" "private_dot_config/docs/tools.md" "CLAUDE.md: ツール一覧へのリンクがある"

# --- CLAUDE.md が docs/ の配布先を正しく書いている ---
# private_dot_config/docs/ は ~/.config/docs へ配られる。配らないと書くと、
# リポジトリ内部のメモを置いた結果それがホームへ出ていく。
assert_not_contains "$claude_md" '`docs/` - repository documentation, not distributed' \
  "CLAUDE.md: docs/ を配らないと書かない"
assert_contains "$claude_md" '~/.config/docs' "CLAUDE.md: docs/ の配布先が書いてある"

# --- tool-adopt スキルが退役済みのツールを指していない ---
# このスキルは「brew install」で自動起動する。退役したツールを指したままだと、
# 存在しないバイナリを実行し、存在しないファイルを編集させることになる。
tool_adopt="$(cat "$CHEZMOI_SOURCE/private_dot_config/claude/skills/tool-adopt/SKILL.md")"
for s in "zk に" "custom-zk-" "tmux.conf" "private_dot_config/tmux/"; do
  assert_not_contains "$tool_adopt" "$s" "tool-adopt: 退役済みの $s を指さない"
done
assert_contains "$tool_adopt" "private_dot_config/docs/tools.md" \
  "tool-adopt: ツール一覧への追記を指示する"
assert_contains "$tool_adopt" "private_dot_config/herdr/" \
  "tool-adopt: Herdr の設定先を指す"

# --- Claude の CLAUDE.md が常駐プロセスの置き場所を実行環境で分ける ---
# herdr が動いていない環境で、端末を開いて herdr を起動しようとした事故があった。
# 判定表と「多重化ツールを自分で起動しない」の禁止をこのファイルが持つ。
claude_tmpl="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" < "$CHEZMOI_SOURCE/private_dot_config/claude/CLAUDE.md.tmpl")"
assert_contains "$claude_tmpl" 'PASEO_AGENT_ID' \
  "Claude CLAUDE.md: Paseo 環境を判定する"
assert_contains "$claude_tmpl" 'HERDR_ENV' \
  "Claude CLAUDE.md: herdr 環境を判定する"
assert_contains "$claude_tmpl" 'run_in_background' \
  "Claude CLAUDE.md: どちらでもない環境の経路がある"
assert_contains "$claude_tmpl" '端末多重化ツールを自分で起動しない' \
  "Claude CLAUDE.md: 多重化ツールを自分で起動しない"
assert_not_contains "$claude_tmpl" '## Shell Execution with Herdr' \
  "Claude CLAUDE.md: 節の見出しが herdr 固定でない"

# --- herdr の経路が参照先のスキル無しで実行できる ---
# `/herdr` スキルはこのリポジトリが配っていない。判定表の中にコマンドを書き切る。
assert_not_contains "$claude_tmpl" '`/herdr` スキル' \
  "Claude CLAUDE.md: 配っていない /herdr スキルを参照しない"
assert_contains "$claude_tmpl" 'herdr pane split "$HERDR_PANE_ID" --direction down --cwd "$PWD" --no-focus' \
  "Claude CLAUDE.md: herdr の pane 作成コマンドがフラグごと書いてある"
assert_contains "$claude_tmpl" 'herdr pane run <pane_id>' \
  "Claude CLAUDE.md: herdr pane run に pane ID を渡すと書いてある"
assert_contains "$claude_tmpl" '`--current` は使わない' \
  "Claude CLAUDE.md: --current を禁じている"

# --- Session Handoff が herdr 限定であることを本文の先頭で言う ---
# 条件が箇条書きに埋もれていると、herdr の無い環境でも手順に入ろうとする。
assert_contains "$claude_tmpl" 'herdr 管理下（`HERDR_ENV=1`）でのみ行う' \
  "Claude CLAUDE.md: handoff の前提が本文の先頭にある"
assert_contains "$claude_tmpl" 'Paseo もこれに当たり' \
  "Claude CLAUDE.md: Paseo では handoff しないと書いてある"

handoff_skill="$(cat "$CHEZMOI_SOURCE/private_dot_config/claude/skills/handoff/SKILL.md")"
assert_contains "$handoff_skill" 'herdr を起動してはならない' \
  "handoff: herdr を自分で起動しない"

for tmpl in private_dot_config/claude/CLAUDE.md.tmpl private_dot_config/codex/AGENTS.md.tmpl; do
  body="$(cat "$CHEZMOI_SOURCE/$tmpl")"
  assert_eq "$(printf '%s' "$body" | grep -c 'list_profiles')" "0" "$tmpl: list_profiles が残らない"
  assert_eq "$(printf '%s' "$body" | grep -c 'think_\*')" "0" "$tmpl: think_* が残らない"
  assert_contains "$body" "agent-config resolve" "$tmpl: agent-config resolve を通す"
done
section="$(sed -n '/^## Paseo の子エージェントを作るとき/,/^## /p' "$CHEZMOI_SOURCE/private_dot_config/claude/CLAUDE.md.tmpl")"
assert_eq "$(printf '%s' "$section" | grep -c 'tier')" "0" "CLAUDE.md.tmpl: 節に tier が残らない"

plan_criteria="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/_criteria-plan.md")"
assert_contains "$plan_criteria" '`standard` は `routine` へ読み替え' \
  "plan criteria: standard の互換読み替えを説明する"
assert_contains "$plan_criteria" "stderr に warning" \
  "plan criteria: standard の読み替え warning を説明する"

contract="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")"
assert_eq "$(printf '%s' "$contract" | grep -c 'max_rounds: 2')" "0" "契約: max_rounds: 2 が残らない"
assert_eq "$(printf '%s' "$contract" | grep -c 'max_rounds は 2')" "0" "契約: max_rounds は 2 が残らない"
assert_eq "$(printf '%s' "$contract" | grep -c 'max_rounds: 4')" "2" "契約: review_policy の 2 か所が 4"
assert_contains "$contract" "--complexity" "契約: resolve の呼び出し例に --complexity がある"
assert_contains "$contract" "mad-review" "契約: provenance の使い分けに mad-review がある"
assert_eq "$(printf '%s' "$contract" | grep -c 'generate-paseo-config')" "0" "契約: 旧 CLI 名が残らない"
skill="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md")"
assert_eq "$(printf '%s' "$skill" | grep -c '2 round')" "0" "SKILL: 2 round が残らない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
