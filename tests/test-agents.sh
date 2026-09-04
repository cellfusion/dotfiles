#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

render_agent() {
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/render-$2\" (merge (dict \"agent\" \"$1\") .) }}"
}

# tier ごとのモデルが各ツール向けに正しく出る。
out="$(render_agent sdd-implementer codex.toml)"
assert_contains "$out" 'model = "gpt-5.6-luna"' "implementer/codex: work は luna"
assert_contains "$out" 'model_reasoning_effort = "high"' "implementer/codex: effort は high"
assert_contains "$out" 'sandbox_mode = "workspace-write"' "implementer/codex: 書き込み可"

out="$(render_agent sdd-final-reviewer codex.toml)"
assert_contains "$out" 'model = "gpt-5.6-sol"' "final-reviewer/codex: deep は sol"
assert_contains "$out" 'sandbox_mode = "read-only"' "final-reviewer/codex: 読み取り専用"

out="$(render_agent sdd-implementer-think codex.toml)"
assert_contains "$out" 'model = "gpt-5.6-terra"' "implementer-think/codex: think は terra"

out="$(render_agent sdd-re-reviewer codex.toml)"
assert_contains "$out" 'model = "gpt-5.6-luna"' "re-reviewer/codex: fast は luna"
assert_contains "$out" 'model_reasoning_effort = "medium"' "re-reviewer/codex: effort は medium"

# 承認とサンドボックスは親の config.toml に依存させず、定義側に書く。
out="$(render_agent sdd-implementer codex.toml)"
assert_contains "$out" 'approval_policy = "on-request"' \
  "implementer/codex: 承認は on-request"
assert_contains "$out" 'approvals_reviewer = "auto_review"' \
  "implementer/codex: 承認判定は auto_review"
assert_contains "$out" '[sandbox_workspace_write]' \
  "implementer/codex: sandbox の表を出す"
assert_contains "$out" 'network_access = true' \
  "implementer/codex: sandbox 内ネットワークを許す"

# TOML では表の見出しより後のキーがその表に属する。見出しが
# developer_instructions より前に出ると、本文が表の中に入って壊れる。
tail_out="$(printf '%s\n' "$out" | sed -n '/^\[sandbox_workspace_write\]$/,$p')"
assert_not_contains "$tail_out" 'developer_instructions' \
  "implementer/codex: sandbox の表は developer_instructions より後に出る"

# read 役は read-only なので表が効かない。出さない。
out="$(render_agent sdd-task-reviewer codex.toml)"
assert_contains "$out" 'approval_policy = "on-request"' \
  "task-reviewer/codex: 承認は on-request"
assert_contains "$out" 'approvals_reviewer = "auto_review"' \
  "task-reviewer/codex: 承認判定は auto_review"
assert_not_contains "$out" '[sandbox_workspace_write]' \
  "task-reviewer/codex: sandbox の表を出さない"

# 描画結果が TOML としてパースできる。表の位置と三連引用符を同時に検証する。
impl_toml="$(mktemp)"
render_agent sdd-implementer codex.toml > "$impl_toml"
impl_parsed="$(python3 -c "
import tomllib
d = tomllib.load(open('$impl_toml','rb'))
print(d['approval_policy'], d['approvals_reviewer'],
      d['sandbox_workspace_write']['network_access'],
      'あなたは' in d['developer_instructions'])
" 2>&1)"
rm -f "$impl_toml"
assert_eq "$impl_parsed" "on-request auto_review True True" \
  "implementer/codex: TOML としてパースでき、表と本文が正しい位置にある"

read_toml="$(mktemp)"
render_agent sdd-task-reviewer codex.toml > "$read_toml"
read_parsed="$(python3 -c "
import tomllib
d = tomllib.load(open('$read_toml','rb'))
print(d['sandbox_mode'], 'sandbox_workspace_write' in d)
" 2>&1)"
rm -f "$read_toml"
assert_eq "$read_parsed" "read-only False" \
  "task-reviewer/codex: 読み取り専用で sandbox の表を持たない"

# Claude 版。
out="$(render_agent sdd-implementer claude.md)"
assert_contains "$out" "model: sonnet" "implementer/claude: work は sonnet"
assert_contains "$out" "effort: high" "implementer/claude: effort は high"
assert_not_contains "$out" "tools: Read, Grep, Glob" "implementer/claude: ツール制限なし"

out="$(render_agent sdd-final-reviewer claude.md)"
assert_contains "$out" "model: opus" "final-reviewer/claude: deep は opus"
assert_contains "$out" "effort: max" "final-reviewer/claude: effort は max"
assert_contains "$out" "tools: Read, Grep, Glob" "final-reviewer/claude: 読み取り専用"

# opencode 版。
out="$(render_agent sdd-implementer opencode.md)"
assert_contains "$out" "model: openai/gpt-5.6-luna" "implementer/opencode: provider 前置"
assert_contains "$out" "reasoningEffort: high" "implementer/opencode: effort"
assert_contains "$out" "mode: subagent" "implementer/opencode: subagent モード"

out="$(render_agent sdd-final-reviewer opencode.md)"
assert_contains "$out" "edit: deny" "final-reviewer/opencode: 編集を拒否"
assert_contains "$out" "bash: deny" "final-reviewer/opencode: bash を拒否"

# 全 agent の全ツールで、プロンプト本文が入っている。
for a in sdd-implementer sdd-implementer-think sdd-task-reviewer sdd-re-reviewer sdd-final-reviewer; do
  for r in claude.md codex.toml opencode.md; do
    out="$(render_agent "$a" "$r")"
    assert_contains "$out" "あなたは" "$a/$r: プロンプト本文がある"
  done
  # TOML の複数行文字列を壊す三連引用符が、展開後のプロンプトに無い。
  body="$(render_template "agent-defs/prompts/$a.md" claude)"
  assert_not_contains "$body" '"""' "$a: プロンプトが三連引用符を含まない"
done

# sdd-implementer-think は sdd-implementer のプロンプトを include するので、
# 本文は常に同一になる。「指示は同一でモデルだけが上位」という前提を守る。
impl_sum="$(render_template "agent-defs/prompts/sdd-implementer.md" claude | shasum | cut -d' ' -f1)"
think_sum="$(render_template "agent-defs/prompts/sdd-implementer-think.md" claude | shasum | cut -d' ' -f1)"
assert_eq "$think_sum" "$impl_sum" "implementer-think: プロンプト本文が implementer と同一"

# レビュー役のプロンプトは herdr に触れない。SDD の実行経路は sdd-run /
# deterministic-loop / 手動の 3 つで、herdr 経路は存在しない。
for a in sdd-task-reviewer sdd-re-reviewer sdd-final-reviewer; do
  body="$(render_template "agent-defs/prompts/$a.md" claude)"
  assert_not_contains "$body" "herdr" "$a: 存在しない herdr 経路を指さない"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
