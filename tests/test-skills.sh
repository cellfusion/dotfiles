#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

# 移設済みのスキル。
SKILLS="brainstorming writing-plans subagent-driven-development executing-plans systematic-debugging test-driven-development verification-before-completion requesting-code-review receiving-code-review finishing-a-development-branch using-git-worktrees multi-agent-development"

for skill in $SKILLS; do
  for tool in claude codex opencode; do
    out="$(render_template "agent-skills/$skill/SKILL.md" "$tool")"

    # frontmatter が先頭にあり、name が一致する。
    assert_contains "$out" "name: $skill" "$skill/$tool: frontmatter の name"

    # runtime ブロックが注入されている。
    assert_contains "$out" "この環境での対応" "$skill/$tool: runtime ブロックがある"

    # 本文にツール名が漏れていない。
    assert_not_contains "$out" 'AskUserQuestion で' "$skill/$tool: 本文が AskUserQuestion を直書きしない"
  done

  # Claude 版だけが Claude のツール名を持つ（runtime ブロック由来）。
  claude_out="$(render_template "agent-skills/$skill/SKILL.md" "claude")"
  assert_contains "$claude_out" "AskUserQuestion" "$skill: claude 版は AskUserQuestion を指す"

  codex_out="$(render_template "agent-skills/$skill/SKILL.md" "codex")"
  assert_not_contains "$codex_out" "AskUserQuestion" "$skill: codex 版は AskUserQuestion を出さない"

  # 論理名が本文に残っている。
  assert_contains "$codex_out" "[ask-user]" "$skill: 本文が論理名を使う"
done

# 開発工程 skill は親が本文を作らず、MAD recipe へ成果物パスで委譲する薄い入口である。
# user gate だけを親が relay し、braid / 旧 mad-run の実行経路を持たない。
for spec in \
  "brainstorming:spec" \
  "writing-plans:plan" \
  "subagent-driven-development:implement" \
  "executing-plans:implement" \
  "requesting-code-review:review" \
  "receiving-code-review:review" \
  "verification-before-completion:review"; do
  skill="${spec%%:*}"
  recipe="${spec##*:}"
  for tool in claude codex opencode; do
    out="$(render_template "agent-skills/$skill/SKILL.md" "$tool")"
    assert_contains "$out" "MAD の \`$recipe\`" "$skill/$tool: MAD recipe へ委譲する"
    assert_contains "$out" "handoff.json" "$skill/$tool: 成果物を handoff で渡す"
    assert_contains "$out" "waiting_for_user" "$skill/$tool: 親の user gate を記録する"
    assert_contains "$out" "本文を作らない" "$skill/$tool: 親が本文を作らない"
    assert_not_contains "$out" "braid" "$skill/$tool: braid を参照しない"
    assert_not_contains "$out" "mad-run" "$skill/$tool: 旧 mad-run を参照しない"
    # recipe の名前だけでは実行できない。手順を持つ skill と、その読み込み先を示す。
    assert_contains "$out" "multi-agent-development" \
      "$skill/$tool: 委譲先の skill を名指しする"
    assert_contains "$out" ".agents/skills/multi-agent-development/SKILL.md" \
      "$skill/$tool: 委譲先の手順の在り処を示す"
  done
done

# description で skill を選ぶ runtime のために、frontmatter が開発ライフサイクルの
# recipe を挙げる。挙げないと「spec を作る」「plan を実装する」で MAD が読み込まれない。
mad_description="$(printf '%s\n' "$(render_template "agent-skills/multi-agent-development/SKILL.md" "claude")" \
  | sed -n '/^description:/,/^---$/p')"
for recipe in spec plan implement review delivery; do
  assert_contains "$mad_description" "$recipe" \
    "mad: description が $recipe recipe を挙げる"
done

# requesting-code-review は単発利用でも MAD review の入力 package を先に作る。
# review-package の PLAN_FILE / BASE / HEAD / OUTFILE 契約と、未解決時の停止を
# render 後の手順に残し、親が review 本文を代筆しないことを確認する。
for tool in claude codex opencode; do
  request_review="$(render_template "agent-skills/requesting-code-review/SKILL.md" "$tool")"
  assert_contains "$request_review" "PLAN_FILE" \
    "requesting-code-review/$tool: review-package の PLAN_FILE を指定する"
  assert_contains "$request_review" "BASE" \
    "requesting-code-review/$tool: review-package の BASE を指定する"
  assert_contains "$request_review" "HEAD" \
    "requesting-code-review/$tool: review-package の HEAD を指定する"
  assert_contains "$request_review" "OUTFILE" \
    "requesting-code-review/$tool: review-package の OUTFILE を指定する"
  assert_contains "$request_review" 'REPO_ROOT="$(git rev-parse --show-toplevel)"' \
    "requesting-code-review/$tool: review 対象の repo root を解決する"
  assert_contains "$request_review" 'bash "$REVIEW_PACKAGE" "$PLAN_FILE" "$BASE" "$HEAD" "$OUTFILE"' \
    "requesting-code-review/$tool: review-package を正しい引数で実行する"
  assert_contains "$request_review" 'bash "$CELLFUSION_WORKDIR" >/dev/null' \
    "requesting-code-review/$tool: cellfusion-workdir を先に実行する"
  assert_contains "$request_review" "git rev-parse --verify" \
    "requesting-code-review/$tool: ref を実行前に解決する"
  assert_contains "$request_review" "test -s \"\$OUTFILE\"" \
    "requesting-code-review/$tool: package の生成結果を確認する"
  assert_contains "$request_review" "exit 2" \
    "requesting-code-review/$tool: package 検証失敗で停止する"
  assert_contains "$request_review" '`PLAN_FILE` が無い' \
    "requesting-code-review/$tool: plan 不在時の fallback を定義する"
  assert_contains "$request_review" '`requirements` の絶対パス' \
    "requesting-code-review/$tool: requirements を fallback の plan にできる"
  assert_contains "$request_review" 'REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-}"' \
    "requesting-code-review/$tool: requirements path を安全に受け取る"
  assert_contains "$request_review" 'PLAN_FILE="$REQUIREMENTS_FILE"' \
    "requesting-code-review/$tool: plan 不在時に requirements path を plan として採用する"
  assert_contains "$request_review" 'case "$PLAN_FILE" in' \
    "requesting-code-review/$tool: 採用した plan path が絶対パスか確認する"
  assert_contains "$request_review" 'review package の入力 file を確認できないため MAD review を開始しない' \
    "requesting-code-review/$tool: fallback 後の plan file の存在を確認する"
  assert_contains "$request_review" '`review-package` の実体を解決する' \
    "requesting-code-review/$tool: script 不在時の fallback を定義する"
  assert_contains "$request_review" "executable_review-package" \
    "requesting-code-review/$tool: checkout の script fallback を示す"
  assert_contains "$request_review" "package を作れない場合は MAD review を開始しない" \
    "requesting-code-review/$tool: package 失敗時に review を開始しない"
  # BASE / HEAD を親が渡し忘れると、空の ref 2 つで review-package を呼ぶことになる。
  assert_contains "$request_review" "set -eu" \
    "requesting-code-review/$tool: 未設定と失敗でブロックを止める"
  assert_contains "$request_review" ': "${BASE:?' \
    "requesting-code-review/$tool: BASE の未設定を検出する"
  assert_contains "$request_review" ': "${HEAD:?' \
    "requesting-code-review/$tool: HEAD の未設定を検出する"
done

# 実装工程の子は TDD / debugging / worktree の既存規約を使い、finish は親の finalizer に残す。
for tool in claude codex opencode; do
  sdd_out="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "$tool")"
  assert_contains "$sdd_out" "test-driven-development" "sdd/$tool: 子の TDD 規約を維持する"
  assert_contains "$sdd_out" "systematic-debugging" "sdd/$tool: 子の debug 規約を維持する"
  assert_contains "$sdd_out" "using-git-worktrees" "sdd/$tool: 子の worktree 規約を維持する"
  finish_out="$(render_template "agent-skills/finishing-a-development-branch/SKILL.md" "$tool")"
  assert_contains "$finish_out" "親専用 finalizer" "finish/$tool: 親の finalizer である"
  assert_contains "$finish_out" "MAD の \`delivery\`" "finish/$tool: delivery 完了後に使う"
done

# プレビュー手順は共有パーシャルに 1 本だけ置く。
preview="$(render_template "agent-skills/_preview-tab.md" "claude")"
assert_contains "$preview" "## プレビュー" "_preview-tab: 節の見出しがある"
assert_contains "$preview" "HERDR_ENV" "_preview-tab: herdr 環境かを判定する"
assert_contains "$preview" "herdr tab create --workspace" "_preview-tab: 自分の workspace にタブを作る"
assert_contains "$preview" "workspace_id" "_preview-tab: workspace ID を自 pane から引く"
assert_contains "$preview" 'EDITOR' '_preview-tab: $EDITOR で開く'
assert_contains "$preview" '; exit' "_preview-tab: エディタ終了で pane を閉じる"
assert_contains "$preview" "読み直す" "_preview-tab: 手編集の取り込みを指示する"
assert_not_contains "$preview" "herdr tab close" "_preview-tab: タブを閉じない"

# Paseo は HERDR_ENV を持たない。端末を作らず、ファイルリンクで表示する。
assert_contains "$preview" "PASEO_AGENT_ID" "_preview-tab: Paseo 環境かを判定する"
assert_contains "$preview" "Paseo のファイルリンクを出す" \
  "_preview-tab: Paseo ではファイルリンクを出す"
assert_contains "$preview" "[specを閲覧する]" \
  "_preview-tab: Paseo ではspecリンクを出す"
assert_not_contains "$preview" "paseo terminal create" \
  "_preview-tab: Paseo では端末を作らない"
assert_not_contains "$preview" "glow -p" "_preview-tab: Paseo ではglowを使わない"

# チェックリストは経路を書かない。手順は _preview-tab.md が環境ごとに分岐して持つ。
brainstorming_out="$(render_template "agent-skills/brainstorming/SKILL.md" "claude")"
assert_not_contains "$brainstorming_out" "herdr の別タブに" \
  "brainstorming: チェックリストが herdr 固定でない"

# [todo] の対応先は実在するツールでなければならない。TaskCreate / TaskUpdate は
# 手元の Claude Code に無い。
claude_runtime="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_runtime/claude.md")"
assert_not_contains "$claude_runtime" "TaskCreate" \
  "claude runtime: 実在しないツール名を指さない"
assert_not_contains "$claude_runtime" "TaskUpdate" \
  "claude runtime: 実在しないツール名を指さない（TaskUpdate）"
assert_contains "$claude_runtime" "ledger ファイルで代替" \
  "claude runtime: todo の代替手段を書く"

# sandbox の permission denied だけは承認付きで同じプレビューを一度だけ再試行する。
for tool in claude codex opencode; do
  runtime="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_runtime/$tool.md")"
  assert_contains "$runtime" '[retry-outside-sandbox]' \
    "$tool runtime: sandbox 外再試行の対応を定義する"
done

codex_runtime="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_runtime/codex.md")"
assert_contains "$codex_runtime" 'sandbox_permissions=require_escalated' \
  "codex runtime: require_escalated で再試行する"
assert_contains "$codex_runtime" 'justification' \
  "codex runtime: 再試行時に承認理由を付ける"
assert_contains "$preview" "PermissionDenied" \
  "_preview-tab: sandbox の権限拒否を識別する"
assert_contains "$preview" '[retry-outside-sandbox]' \
  "_preview-tab: 権限拒否時だけ sandbox 外で再試行する"
assert_contains "$preview" "同じプレビューコマンドを 1 回だけ再実行" \
  "_preview-tab: 無限再試行しない"
assert_contains "$preview" "permission denied 以外" \
  "_preview-tab: 他の失敗を権限問題として扱わない"

# 補助ファイルの実体は ~/.agents/skills 側にあり、Claude / opencode 側は symlink である。
for f in systematic-debugging/condition-based-waiting.md \
         systematic-debugging/defense-in-depth.md \
         systematic-debugging/root-cause-tracing.md \
         test-driven-development/writing-good-tests.md; do
  assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_agents/skills/$f" ] && echo yes || echo no)" \
            "yes" "補助ファイルの実体がある: $f"
  dir="$(dirname "$f")"
  base="$(basename "$f")"
  assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_config/claude/skills/$dir/symlink_$base.tmpl" ] && echo yes || echo no)" \
            "yes" "claude 側に symlink がある: $f"
  assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_config/opencode/skills/$dir/symlink_$base.tmpl" ] && echo yes || echo no)" \
            "yes" "opencode 側に symlink がある: $f"
done

# SDD のスクリプトは ~/.agents/skills 側の 1 箇所だけにある。
for s in review-package sdd-workspace task-brief task-waves; do
  p="private_dot_agents/skills/subagent-driven-development/scripts/executable_$s"
  assert_eq "$([ -f "$CHEZMOI_SOURCE/$p" ] && echo yes || echo no)" \
            "yes" "スクリプトの実体がある: $s"
  old="private_dot_config/claude/skills/subagent-driven-development/scripts/executable_$s"
  assert_eq "$([ -e "$CHEZMOI_SOURCE/$old" ] && echo yes || echo no)" \
            "no" "旧 scripts が残っていない: $s"
done

# _cellfusion/ の自己無視を作るスクリプトは 1 箇所にあり、そこへ書き込む
# 3 つのスキルすべてが書き込む前にそれを呼ぶ。
assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_cellfusion-workdir" ] && echo yes || echo no)" \
          "yes" "cellfusion-workdir の実体がある"
assert_contains "$(cat "$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts/executable_sdd-workspace")" \
  "cellfusion-workdir" "sdd-workspace が cellfusion-workdir を呼ぶ"
for skill in brainstorming writing-plans; do
  for tool in claude codex opencode; do
    out="$(render_template "agent-skills/$skill/SKILL.md" "$tool")"
    assert_contains "$out" ".agents/skills/_shared/scripts/cellfusion-workdir" \
      "$skill/$tool: 保存前に cellfusion-workdir を呼ぶ"
  done
done

# herdr 管理下では worktree を workspace として作り、既にある worktree も workspace として開く。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/using-git-worktrees/SKILL.md" "$tool")"
  assert_contains "$out" "HERDR_ENV" "using-git-worktrees/$tool: herdr 環境かを判定する"
  assert_contains "$out" "herdr worktree create" "using-git-worktrees/$tool: worktree を workspace として作る"
  assert_contains "$out" "herdr worktree open" "using-git-worktrees/$tool: 既存の worktree を workspace として開く"
  assert_contains "$out" "herdr worktree list" "using-git-worktrees/$tool: workspace として開かれているかを調べる"
  assert_contains "$out" "git worktree add" "using-git-worktrees/$tool: herdr が無い環境の経路が残っている"
done

# finishing-a-development-branch は herdr が作った worktree も後始末できる。
finish="$(render_template "agent-skills/finishing-a-development-branch/SKILL.md" "claude")"
assert_contains "$finish" '~/.herdr/worktrees/' "finishing-a-development-branch: herdr worktree のパスを判定する"
assert_contains "$finish" "herdr worktree list" "finishing-a-development-branch: workspace ID を引く"
assert_contains "$finish" 'herdr worktree remove --workspace "$ws" --force' \
  "finishing-a-development-branch: workspace ごと畳む"

# using-git-worktrees の 1a は ws が空のときだけ remove する。
using="$(render_template "agent-skills/using-git-worktrees/SKILL.md" "claude")"
assert_contains "$using" '`ws` が非空なら' "using-git-worktrees: ws が空のときは remove しない"
assert_contains "$using" "git check-ignore" "using-git-worktrees: SDD 用に .worktrees/ の ignore を確認する"
assert_contains "$using" '.result.workspace.workspace_id' "using-git-worktrees: workspace ID の取得元を書く"
assert_contains "$using" '--cwd "$(pwd -P)"' "using-git-worktrees: --cwd を物理パスに揃える"
assert_contains "$using" "// empty" "using-git-worktrees: jq に // empty を付ける"
assert_contains "$using" "この確認を飛ばして先へ進む" "using-git-worktrees: herdr worktree list 失敗時の逃げ道がある"
assert_contains "$using" "下の herdr の確認と報告を済ませてから Step 2 へ進む" \
  "using-git-worktrees: herdr の確認を Step 2 へ飛ぶより先に行う"

# 1a・1b は ignore 確認節を素通りせず、Step 2 へ行く前に必ず経由する。
assert_eq "$(printf '%s' "$using" | grep -c '`\.worktrees/` の ignore を確認する（SDD 用）」を済ませてから Step 2 へ進む')" \
  "2" "using-git-worktrees: 1a と 1b の両方が ignore 確認節を前方参照する"

# implementer は波の中で全体スイートを回さない。並行するとタスク数だけ重複する。
impl_prompt="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/prompts/sdd-implementer.md")"
assert_contains "$impl_prompt" "全体のスイートは回しません" \
  "implementer: タスク中は focused test だけにする"

# スキル本文の bash ブロックは、そのままコピーして実行できる構文であること。
# プレースホルダーを `<name>` の形で裸で書くと `<` と `>` がリダイレクトになり、読者が
# 実行すると落ちる。この欠陥はレビューを 2 度素通りしたので、テストで縛る。
for skill in requesting-code-review multi-agent-development; do
  for tool in claude codex opencode; do
    out="$(render_template "agent-skills/$skill/SKILL.md" "$tool")"
    blocks="$(printf '%s\n' "$out" | sed -n '/^```bash$/,/^```$/p' | grep -v '^```')"
    ok="$(printf '%s\n' "$blocks" | bash -n 2>/dev/null && echo yes || echo no)"
    assert_eq "$ok" "yes" "$skill/$tool: bash ブロックが構文として妥当"
  done
done

# MAD スキルは共通の手動オーケストレーション契約を取り込む。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/multi-agent-development/SKILL.md" "$tool")"
  assert_contains "$out" "## 手動オーケストレーション" "mad/$tool: 手動方式の節が展開される"
  assert_contains "$out" "Paseo MCP" "mad/$tool: Paseo を優先する"
  assert_contains "$out" "_cellfusion/orchestration/" "mad/$tool: run 成果物の保存先を定義する"
  assert_contains "$out" "state.json" "mad/$tool: 状態契約を定義する"
done

# MAD の全レシピは、親が介入する手順として展開される。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/multi-agent-development/SKILL.md" "$tool")"
  for recipe in research decide debate fanout review triage implement spike refine; do
    assert_contains "$out" "\`$recipe\`" "mad/$tool: レシピ $recipe が表にある"
  done
  assert_contains "$out" "親が確認" "mad/$tool: 親の介入点を定義する"
  assert_contains "$out" "max_rounds" "mad/$tool: loop 上限を定義する"
  assert_not_contains "$out" "mad-run" "mad/$tool: 旧方式を参照しない"
done

# 全レシピの表には、親が確認した絶対パス handoff と失敗時停止を残す。非ループ型は
# 後段自身も確認してから run を完了し、loop 型はレビューまたは批評を確認してから親が
# 次ラウンドを判断する。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/multi-agent-development/SKILL.md" "$tool")"
  for recipe in research decide debate fanout review triage implement spike refine; do
    recipe_row="$(printf '%s\n' "$out" | grep -F "| \`$recipe\` |" || true)"
    assert_contains "$recipe_row" "絶対パス" \
      "mad/$tool: $recipe は絶対パスで後段へ handoff する"
    assert_contains "$recipe_row" "失敗" \
      "mad/$tool: $recipe は失敗時に後段を停止する"
  done
  assert_contains "$out" "後段の \`state.json\` と成果物を親が確認し、\`ok\` のときだけ run を完了する" \
    "mad/$tool: 非ループ型は後段を確認してから run を完了する"
  assert_contains "$out" "成果物を欠く場合は run を \`failed\` または \`stopped\` として記録して停止する" \
    "mad/$tool: 非ループ型は後段の成果物欠落で run を停止する"
  assert_contains "$out" "親がレビューまたは批評の成果物と \`state.json\` を確認し" \
    "mad/$tool: loop 型は後段を確認してから親が判断する"
done

mad_src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md")"
assert_contains "$mad_src" 'includeTemplate "agent-skills/_manual-orchestration.md"' \
  "mad: 手動方式を共有パーシャルから取り込む"
assert_not_contains "$mad_src" "## 旧方式" "mad: 旧方式の節を残さない"

manual_mad="$(render_template "agent-skills/_manual-orchestration.md" "claude")"
assert_contains "$manual_mad" "## 手動オーケストレーション" \
  "_manual-orchestration: 節の見出しがある"
assert_contains "$manual_mad" "Paseo MCP" \
  "_manual-orchestration: Paseo MCP を優先する"
assert_contains "$manual_mad" "[dispatch-subagent: role]" \
  "_manual-orchestration: fallback の論理名を使う"
assert_contains "$manual_mad" "_cellfusion/orchestration/<run-id>/" \
  "_manual-orchestration: run 成果物の保存先を定義する"
assert_contains "$manual_mad" "nodes/<node-id>/attempts/<attempt-id>/" \
  "_manual-orchestration: node と attempt の成果物を分離する"
assert_contains "$manual_mad" "prompt.md" \
  "_manual-orchestration: prompt の成果物を定義する"
assert_contains "$manual_mad" "result.md" \
  "_manual-orchestration: result の成果物を定義する"
assert_contains "$manual_mad" "state.json" \
  "_manual-orchestration: state の成果物を定義する"
assert_contains "$manual_mad" "pending" \
  "_manual-orchestration: pending 状態を定義する"
assert_contains "$manual_mad" "running" \
  "_manual-orchestration: running 状態を定義する"
assert_contains "$manual_mad" "ok" \
  "_manual-orchestration: ok 状態を定義する"
assert_contains "$manual_mad" "failed" \
  "_manual-orchestration: failed 状態を定義する"
assert_contains "$manual_mad" "stopped" \
  "_manual-orchestration: stopped 状態を定義する"
assert_contains "$manual_mad" "unresolved" \
  "_manual-orchestration: unresolved 状態を定義する"
assert_contains "$manual_mad" "backend" \
  "_manual-orchestration: backend を state に記録する"
for field in run_id node attempt round; do
  assert_contains "$manual_mad" "\`$field\`" \
    "_manual-orchestration: $field は state の第一級フィールドである"
done
assert_contains "$manual_mad" "manual-orchestration-validate" \
  "_manual-orchestration: 実行可能な成果物検証を案内する"
# chezmoi apply 前は ~/.agents に validator が無い。契約側にも checkout の fallback を置く。
assert_contains "$manual_mad" "executable_manual-orchestration-validate" \
  "_manual-orchestration: checkout の validator fallback を示す"

# 子をどう起動するかを 1 箇所に書く。ここが無いと prompt と schema は配布されるだけで
# 実行時に誰も参照せず、result.json が schema 検査を受けない。
assert_contains "$manual_mad" "### 子の起動" \
  "_manual-orchestration: 子の起動手順の節がある"
assert_contains "$manual_mad" ".agents/agent-defs/prompts/" \
  "_manual-orchestration: role の system prompt の在り処を示す"
assert_contains "$manual_mad" ".agents/agent-defs/schemas/" \
  "_manual-orchestration: role の出力 schema の在り処を示す"
assert_contains "$manual_mad" "result.json" \
  "_manual-orchestration: 構造化出力の保存先を示す"
assert_contains "$manual_mad" "initialPrompt" \
  "_manual-orchestration: Paseo MCP へ prompt と schema を渡す方法を示す"
assert_contains "$manual_mad" "[dispatch-subagent: <role>]" \
  "_manual-orchestration: native subagent での起動方法を示す"
assert_contains "$manual_mad" "\`mad-attempt-v1\` は" \
  "_manual-orchestration: mad-attempt-v1 を定義する"
assert_contains "$manual_mad" "max_rounds" \
  "_manual-orchestration: loop 上限を定義する"
# validator の必須 output node は親が付ける node ID である。契約側に一覧が無いと、
# 親は validator を通す node 名を推測することになる。
assert_contains "$manual_mad" "必須 output node" \
  "_manual-orchestration: recipe ごとの必須 output node を挙げる"
for node in synthesis verdict spec-author planner final-review review-synthesis; do
  assert_contains "$manual_mad" "\`$node\`" \
    "_manual-orchestration: 必須 output node $node を挙げる"
done
assert_contains "$manual_mad" "親が確認" \
  "_manual-orchestration: 親の介入境界を定義する"

# implement と spike の子は同じ作業ツリーへ同時に書く。契約に worktree 隔離と
# 後片付けが無いと、子の書き込みが互いに上書きされ、workspace も残り続ける。
assert_contains "$manual_mad" "isolation" \
  "mad/contract: worktree 隔離の isolation を書く"
assert_contains "$manual_mad" "branch-off" \
  "mad/contract: worktree の mode に branch-off を使う"
assert_contains "$manual_mad" "workspaces.json" \
  "mad/contract: workspace の台帳を run ディレクトリに置く"
assert_contains "$manual_mad" "detached HEAD" \
  "mad/contract: detached HEAD を拒否する"
assert_contains "$manual_mad" "archive_workspace" \
  "mad/contract: 後片付けに archive_workspace を使う"

mad_skill="$(render_template "agent-skills/multi-agent-development/SKILL.md" "claude")"
assert_contains "$mad_skill" "### delivery role map" \
  "mad/delivery: logical duty と実 role の map を示す"
assert_contains "$mad_skill" "manifest の \`delivery_duties\` が正本" \
  "mad/delivery: role map の正本を manifest に固定する"
assert_contains "$mad_skill" "Paseo MCP と native subagent はともに同じ role と \`mad-attempt-v1\` を使う" \
  "mad/delivery: backend 間で成果物契約を変えない"
assert_contains "$mad_skill" "\`spec-reviewer\` / \`plan-reviewer\` | \`reviewer\`" \
  "mad/delivery: reviewer を spec/plan review に再利用する"
assert_contains "$mad_skill" "\`planner\` / \`task-graph-analyzer\` | \`plan-author\`" \
  "mad/delivery: plan-author を task graph に再利用する"
assert_contains "$mad_skill" "\`implementer\` | \`sdd-implementer\`" \
  "mad/delivery: task 実装は SDD implementer を使う"
assert_contains "$mad_skill" "\`review-synthesizer\` | \`review-synthesizer\`" \
  "mad/delivery: review 統合は専用 role を使う"
assert_contains "$mad_skill" "既定観点: 現状と確認済みの事実、制約とリスク、代替案" \
  "mad/research: 既定の 3 観点を定義する"
assert_contains "$mad_skill" "\`perspectives\` で全 3 観点を差し替えられる" \
  "mad/research: ユーザー指定の観点で上書きできる"
assert_contains "$mad_skill" "調査役は \`researcher\`、統合役は \`synthesizer\`" \
  "mad/research: 子の role を明記する"
assert_contains "$mad_skill" "改稿役を起動して成果物を確認し、批評役へ絶対パスを渡し、親が批評を確認して判断する" \
  "mad/refine: 改稿から批評、親判断の順に進める"

for d in private_dot_agents/skills \
         private_dot_config/claude/skills \
         private_dot_config/opencode/skills; do
  assert_eq "$([ -f "$CHEZMOI_SOURCE/$d/multi-agent-development/SKILL.md.tmpl" ] && echo yes || echo no)" \
            "yes" "mad: 配布先に .tmpl がある: $d"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
