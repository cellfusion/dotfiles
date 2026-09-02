#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

table="$(render_template "agent-skills/_workflow-table.md" "codex")"
for skill in brainstorming systematic-debugging subagent-driven-development \
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
claude_tmpl="$(cat "$CHEZMOI_SOURCE/private_dot_config/claude/CLAUDE.md.tmpl")"
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

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
