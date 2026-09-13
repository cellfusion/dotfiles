#!/usr/bin/env bash
# chezmoi が実際に配る対象の集合を検証する。
# このリポジトリの作業用ディレクトリ（docs / tests / _cellfusion）はホームに配らない。
set -u
. "$(dirname "$0")/lib/assert.sh"

managed="$(chezmoi managed --source "$CHEZMOI_SOURCE" 2>&1)"
# .chezmoiremove の削除対象は managed にも列挙されるため、配布ファイルだけを別に見る。
managed_files="$(chezmoi managed --source "$CHEZMOI_SOURCE" --include=files,symlinks 2>&1)"

# `chezmoi managed` 自体が成功していること（.chezmoiremove と source の衝突などを検出する）。
assert_not_contains "$managed" "inconsistent state" "managed が inconsistent state を出さない"

# Paseo の設定生成に必要な CLI と runtime 非依存の契約を配布する。正本は利用者の
# 秘密領域なので配布しない。
assert_contains "$managed" ".local/bin/generate-paseo-config" "distribution: 生成 CLI を配る"
assert_contains "$managed" ".local/share/agent-config/config-types.js" "distribution: runtime 非依存の契約を配る"
assert_contains "$managed" ".local/share/agent-config/mad-contract.js" "distribution: MAD の契約 module を配る"
assert_contains "$managed" ".local/share/agent-config/agent-config.schema.json" "distribution: 公開 schema を配る"
assert_contains "$managed" ".local/share/agent-config/agent-config.sample.json" "distribution: 匿名 sample を配る"
assert_not_contains "$managed" ".config/chezmoi/agent-config.json" "distribution: 正本を配らない"
hook_source="$(cat "$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_90-agent-envs.sh.tmpl")"
for legacy in private-data.toml setup_paseo_provider list_providers; do
  assert_not_contains "$hook_source" "$legacy" "hook: $legacy を持たない"
done
docs="$(cat "$CHEZMOI_SOURCE/private_dot_config/docs/tools.md")"
for step in 'generate-paseo-config resolve' 'generate-paseo-config --diff' 'generate-paseo-config --check'; do
  assert_contains "$docs" "$step" "docs: 移行手順に $step がある"
done
assert_contains "$docs" "--paseo-config <absolute-copy>" \
  "docs: 承認前の各検査と試行 write が target copy を明示する"
assert_contains "$docs" "--paseo-config <absolute-target>" \
  "docs: 承認後の通常 write も target path を明示する"
assert_contains "$docs" 'chezmoi apply' "docs: apply が利用者の明示許可であることを書く"

# リポジトリの作業用ディレクトリを配らない。
for d in docs tests _cellfusion; do
  assert_not_contains "$(printf '%s\n' "$managed" | grep "^$d" || true)" "$d" \
    "$d/ をホームへ配らない"
done

# _cellfusion/ を無視する global gitignore は、新しいマシンでも再現できるよう配る。
assert_contains "$managed" ".config/git/ignore" "global gitignore を配る"
assert_contains "$(cat "$CHEZMOI_SOURCE/private_dot_config/git/ignore")" "_cellfusion/" \
  "global gitignore が _cellfusion/ を無視する"

# MAD の Paseo-only adapter と plan validator を配る。
for s in paseo-mcp-adapter paseo-plan-dependency-validate; do
  assert_contains "$managed" ".agents/skills/multi-agent-development/scripts/$s" \
    "MAD: $s を共有パスへ配る"
done

# SKILL.md は 3 ツールすべてに配られる。
for skill in brainstorming writing-plans using-git-worktrees multi-agent-development; do
  assert_contains "$managed" ".config/claude/skills/$skill/SKILL.md" \
    "$skill: claude へ配られる"
  assert_contains "$managed" ".config/opencode/skills/$skill/SKILL.md" \
    "$skill: opencode へ配られる"
  assert_contains "$managed" ".agents/skills/$skill/SKILL.md" \
    "$skill: ~/.agents へ配られる"
done

# codex の設定は実運用の CODEX_HOME（~/.config/codex）へ配る。
assert_contains "$managed" ".config/codex/AGENTS.md" \
  "codex: AGENTS.md を ~/.config/codex へ配る"
assert_contains "$managed" ".config/codex/config.toml" \
  "codex: config.toml を ~/.config/codex へ配る"

# 旧配布先には配らない。CODEX_HOME と食い違うと AGENTS.md も agent 定義も効かない。
# `chezmoi managed` は .chezmoiremove の削除対象も列挙するため、実際の destination に
# 旧ファイルが残っているマシンでは managed の出力だけでは判定できない。
# source 側に旧ディレクトリが無いこと・.chezmoiremove が削除対象を宣言していることを見る。
assert_not_contains "$(ls "$CHEZMOI_SOURCE" 2>&1)" "private_dot_codex" \
  "codex: source に旧パス private_dot_codex が残っていない"
assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoiremove")" ".codex/AGENTS.md" \
  "codex: .chezmoiremove が旧パスの AGENTS.md を削除対象に含む"
assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoiremove")" ".codex/agents" \
  "codex: .chezmoiremove が旧パスの agents を削除対象に含む"

# 2 つ目以降の AI 環境は run_onchange スクリプトが private-data.toml の定義から作る。
# 固定名のディレクトリは chezmoi の配布対象にしない。
agent_profile_dirs="$(find "$CHEZMOI_SOURCE/private_dot_config" -maxdepth 1 -type d -print)"
assert_not_contains "$agent_profile_dirs" "claude_secondary" \
  "追加 Claude 環境を固定名で配らない"
assert_not_contains "$agent_profile_dirs" "codex_secondary" \
  "追加 Codex 環境を固定名で配らない"
# 回収するのは旧スロットへ配った symlink の leaf だけである。ディレクトリを 1 行で
# 挙げると chezmoi が RemoveAll し、管理外のランタイム状態（.claude.json /
# auth.json / sessions）まで消える。
chezmoiremove="$(cat "$CHEZMOI_SOURCE/.chezmoiremove")"
for leaf in agents commands skills hooks CLAUDE.md settings.json; do
  assert_contains "$chezmoiremove" ".config/claude_secondary/$leaf" \
    "旧 Claude 環境の $leaf を .chezmoiremove で回収する"
done
for leaf in agents AGENTS.md; do
  assert_contains "$chezmoiremove" ".config/codex_secondary/$leaf" \
    "旧 Codex 環境の $leaf を .chezmoiremove で回収する"
done
assert_eq "$(printf '%s\n' "$chezmoiremove" | grep -c '^\.config/claude_secondary$')" "0" \
  "旧 Claude 環境をディレクトリごとの削除対象にしない（ランタイム状態を巻き添えにする）"
assert_eq "$(printf '%s\n' "$chezmoiremove" | grep -c '^\.config/codex_secondary$')" "0" \
  "旧 Codex 環境をディレクトリごとの削除対象にしない（ランタイム状態を巻き添えにする）"

# インストールのマニフェストはホームへ配る。ここが配られないと各 run_onchange が
# 「マニフェストが無い」で exit 0 し、chezmoi はそれを実行済みとして記録するため、
# インストールが黙って飛ばされる。.chezmoiignore に install などのパターンが
# 増えたときに気付けるようにする。
for m in .config/install/Brewfile .config/install/npm-globals.txt \
         .config/install/cargo-globals.txt .config/mise/config.toml \
         .config/docs/tools.md; do
  assert_contains "$managed" "$m" "インストールのマニフェストを配る: $m"
done

# .chezmoiscripts の中身はターゲットとして配られない。
assert_eq "$(printf '%s\n' "$managed" | grep -c run_onchange)" "0" \
  "run_onchange スクリプトをホームへ配らない"

# MAD の現行 role は prompt と schema を一緒に ~/.agents へ配る。
for role in implementer task-reviewer re-reviewer final-reviewer; do
  assert_contains "$managed" ".agents/agent-defs/prompts/$role.md" \
    "MAD role: prompts/$role.md を ~/.agents へ配る"
  assert_contains "$managed" ".agents/agent-defs/schemas/$role.json" \
    "MAD role: schemas/$role.json を ~/.agents へ配る"
done

# review 統合は研究の要約 role と異なる専用 role を配る。採用 verdict と finding の
# 契約が runtime ごとに欠けると、review recipe が統合結果を判定できなくなる。
assert_contains "$managed" ".agents/agent-defs/prompts/review-synthesizer.md" \
  "MAD delivery: review-synthesizer prompt を ~/.agents へ配る"
assert_contains "$managed" ".agents/agent-defs/schemas/review-synthesizer.json" \
  "MAD delivery: review-synthesizer schema を ~/.agents へ配る"

# agent 専用の worktrunk config を配る。人の config とは別ファイルである。
assert_contains "$managed" ".config/worktrunk/agent.toml" "worktrunk: agent 専用 config を配る"
assert_contains "$managed" ".config/worktrunk/config.toml" "worktrunk: 人用 config も配る"

for s in agent-docs-dir json-schema; do
  assert_contains "$managed" ".agents/skills/_shared/scripts/$s" \
    "_shared のスクリプトを配る: $s"
done
assert_not_contains "$managed_files" ".agents/skills/_shared/scripts/cellfusion-workdir" \
  "退役した cellfusion-workdir を配らない"
assert_contains "$chezmoiremove" ".agents/skills/_shared/scripts/cellfusion-workdir" \
  "回収: .chezmoiremove が退役した cellfusion-workdir を削除対象にする"

# --- 退役した relay / loam を配らない ---
# relay は CPU/メモリ対策で無効化したまま復帰せず、loam はバイナリも残っていない。
for p in ".config/claude/skills/relay/SKILL.md" \
         ".config/claude/hooks/relay-session-start.sh" \
         ".config/claude/hooks/relay-after-complete.sh" \
         ".config/claude/hooks/relay-link-commit.sh" \
         ".config/claude/hooks/relay-stop-review.sh"; do
  assert_not_contains "$managed_files" "$p" "退役: $p を配らない"
done

# ソースから消しても配布済みの実体は残る。.chezmoiremove で回収する。
chezmoiremove="$(cat "$CHEZMOI_SOURCE/.chezmoiremove")"
for p in ".config/claude/skills/relay" \
         ".config/claude/hooks/relay-session-start.sh" \
         ".config/claude/hooks/relay-after-complete.sh" \
         ".config/claude/hooks/relay-link-commit.sh" \
         ".config/claude/hooks/relay-stop-review.sh"; do
  assert_contains "$chezmoiremove" "$p" "回収: .chezmoiremove が $p を削除対象にする"
done

# 退役ツールのヘルパが ~/.local/bin に残っている。設定ファイル側は回収済みでも
# バイナリやスクリプトは残るので、まとめて削除対象に宣言する。
for p in ".local/bin/zk-memo" ".local/bin/zk-today" ".local/bin/ralph-relay"; do
  assert_contains "$chezmoiremove" "$p" "回収: .chezmoiremove が $p を削除対象にする"
done

# MCP 登録の削除リストからは relay を外さない。外すと登録が復活しうる。
assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/claude-mcp-removed.json")" \
  '"relay"' "relay は MCP 削除リストに残す"

# --- 退役した sesh を配らない ---
# tmux は退役済みで、sesh-connect が呼ぶ tv sesh チャンネルも cable から消えている。
for p in ".config/sesh/sesh.toml" ".local/bin/sesh-connect"; do
  assert_not_contains "$managed_files" "$p" "退役: $p を配らない"
done
for p in ".config/sesh" ".local/bin/sesh-connect"; do
  assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoiremove")" "$p" \
    "回収: .chezmoiremove が $p を削除対象にする"
done
assert_not_contains "$(cat "$CHEZMOI_SOURCE/private_dot_config/television/config.toml")" \
  '"sesh"' "television: sesh のチャンネルトリガを残さない"

# --- .chezmoiremove に保持方針が書かれている ---
# エントリは配布済みの実体を回収するための一時的な指示であり、行き渡ったら消す。
# 方針が無いと、消してよい行かどうかを毎回ゼロから判断することになる。
assert_contains "$chezmoiremove" "追加から 1 ヶ月" ".chezmoiremove: 保持方針が書かれている"

# 剪定済みの古いエントリが復活していない。
# コメント行を落としてから素の部分一致で見る。コメントには退役の経緯として
# `~/.config/zk/helpers.sh` のようなパスが出てくるので、全文のままだと誤検出する。
# 行区切りで挟む形にはしない。$(...) が末尾改行を落とすので最終行に一致せず、
# 末尾追記（このファイルの慣習）での復活とサブパスの復活を見逃す。
chezmoiremove_entries="$(grep -v '^#' "$CHEZMOI_SOURCE/.chezmoiremove")"
for p in ".config/television/cable/tmux-windows.toml" ".config/zk" ".config/tmux" \
         ".config/claude/skills/cairn"; do
  assert_not_contains "$chezmoiremove_entries" "$p" \
    ".chezmoiremove: 剪定済みの $p が残っていない"
done

# --- .DS_Store を git にも chezmoi にも入れない ---
# .chezmoiignore は配布を止めるだけで、git への混入は止まらない。
assert_contains "$(cat "$CHEZMOI_SOURCE/.gitignore")" ".DS_Store" \
  ".gitignore: .DS_Store を無視する"
assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoiignore")" ".DS_Store" \
  ".chezmoiignore: .DS_Store を配らない"

# MAD はスキルと手動オーケストレーション validator だけを配る。旧 shell runner / recipe は
# 配布しない。braid も 3 runtime のいずれにも配布しない。
assert_contains "$managed" ".agents/skills/multi-agent-development/scripts/manual-orchestration-validate" \
  "MAD: validator を共有パスへ配る"
assert_contains "$managed" ".agents/skills/multi-agent-development/scripts/paseo-mcp-adapter" \
  "MAD: Paseo MCP adapter を共有パスへ配る"
assert_contains "$managed" ".agents/skills/multi-agent-development/scripts/paseo-plan-dependency-validate" \
  "MAD: plan dependency validator を共有パスへ配る"
for legacy in \
  ".agents/skills/multi-agent-development/scripts/mad-route" \
  ".agents/skills/multi-agent-development/scripts/mad-agent" \
  ".agents/skills/multi-agent-development/scripts/mad-run" \
  ".agents/skills/multi-agent-development/scripts/mad-lib.sh" \
  ".agents/skills/multi-agent-development/scripts/mad-runs" \
  ".agents/skills/multi-agent-development/recipes" \
  ".agents/skills/braid/SKILL.md" \
  ".config/claude/skills/braid/SKILL.md" \
  ".config/opencode/skills/braid/SKILL.md"; do
  assert_not_contains "$managed_files" "$legacy" "退役資産を配布しない: $legacy"
done
assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoiremove")" ".local/bin/braid" \
  ".chezmoiremove: braid バイナリを回収する"
# ソースから消した braid / 旧 MAD の配布済み実体も回収する。ディレクトリは
# chezmoi が RemoveAll するため、ランタイム状態を含む MAD の新しい保存先は対象にしない。
for p in \
  ".agents/skills/braid" \
  ".config/claude/skills/braid" \
  ".config/opencode/skills/braid" \
  ".agents/skills/multi-agent-development/scripts/mad-run" \
  ".agents/skills/multi-agent-development/scripts/mad-agent" \
  ".agents/skills/multi-agent-development/scripts/mad-route" \
  ".agents/skills/multi-agent-development/scripts/mad-lib.sh" \
  ".agents/skills/multi-agent-development/scripts/mad-runs" \
  ".agents/skills/multi-agent-development/recipes"; do
  assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoiremove")" "$p" \
    ".chezmoiremove: 退役した配布済み資産を回収する: $p"
done
assert_contains "$managed" ".config/claude/skills/multi-agent-development/SKILL.md" \
  "MAD: claude へ配られる"
assert_contains "$managed" ".config/opencode/skills/multi-agent-development/SKILL.md" \
  "MAD: opencode へ配られる"
assert_contains "$managed" ".agents/skills/multi-agent-development/SKILL.md" \
  "MAD: ~/.agents へ配られる"
# この suite が置換先になっている retired distribution source は source tree に残さない。
removal_manifest="$CHEZMOI_SOURCE/private_dot_config/docs/paseo-agent-config-removal-manifest.md"
while read -r source_path; do
  [ -n "$source_path" ] || continue
  assert_eq "$(test -e "$CHEZMOI_SOURCE/$source_path" && echo yes || echo no)" "no" \
    "MAD: retired distribution source を残さない"
done < <(awk -F'|' '$3 ~ /Delete/ && $4 ~ /test-distribution/ { path=$2; gsub(/^ +| +$/, "", path); print path }' "$removal_manifest")

# removal manifest が参照する置換 test は、削除後も実行できる現行 test である。
replacement_tests="$(awk -F'|' '$3 ~ /Delete|Keep/ {
  path=$4
  gsub(/^ +| +$/, "", path)
  if (path ~ /^tests\/test-[^ ]+\.sh$/) print path
}' "$removal_manifest" | sort -u)"
while read -r replacement_test; do
  [ -n "$replacement_test" ] || continue
  assert_eq "$(test -f "$CHEZMOI_SOURCE/$replacement_test" && echo yes || echo no)" "yes" \
    "removal manifest: 置換 test が実在する: $replacement_test"
done <<EOF
$replacement_tests
EOF

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
