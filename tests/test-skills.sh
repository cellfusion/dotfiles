#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

# 移設済みのスキル。
SKILLS="brainstorming writing-plans subagent-driven-development executing-plans systematic-debugging test-driven-development verification-before-completion requesting-code-review receiving-code-review finishing-a-development-branch using-git-worktrees braid"

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

# 承認 gate も共有パーシャルに 1 本だけ置き、各スキルは自前の本文を持たない。
for skill in brainstorming writing-plans; do
  src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/$skill/SKILL.md")"
  assert_contains "$src" 'includeTemplate "agent-skills/_approval-gate.md"' \
    "$skill: 承認 gate を共有パーシャルから取り込む"
  assert_not_contains "$src" "## 承認 gate" "$skill: gate 本文を自前で持たない"
done

# brainstorming の承認 gate は 4 択で、issue 化まで出す。コミットする分岐は無い。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/brainstorming/SKILL.md" "$tool")"
  assert_contains "$out" "## プレビュー" "brainstorming/$tool: プレビュー節が展開される"
  assert_contains "$out" "**承認&継続**" "brainstorming/$tool: 継続する選択肢がある"
  assert_contains "$out" "**承認のみ**" "brainstorming/$tool: ここで終わる選択肢がある"
  assert_contains "$out" "**承認&継続（issue化）**" "brainstorming/$tool: issue 化して継続する選択肢がある"
  assert_contains "$out" "**承認（issue化）**" "brainstorming/$tool: issue 化して終わる選択肢がある"
  assert_contains "$out" "gh repo view" "brainstorming/$tool: issue 選択肢を出し分ける"
  assert_contains "$out" "gh issue create" "brainstorming/$tool: issue 化の手順がある"
  assert_not_contains "$out" "承認・保存" "brainstorming/$tool: コミットする選択肢が無い"
done

# writing-plans の承認 gate は worktree 委譲を含む 3 択で、plan は issue にしない。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/writing-plans/SKILL.md" "$tool")"
  assert_contains "$out" "## プレビュー" "writing-plans/$tool: プレビュー節が展開される"
  assert_contains "$out" "**承認&worktree で委譲**" "writing-plans/$tool: worktree 委譲の選択肢がある"
  assert_contains "$out" "**承認&継続**" "writing-plans/$tool: 継続する選択肢がある"
  assert_contains "$out" "**承認のみ**" "writing-plans/$tool: ここで終わる選択肢がある"
  assert_contains "$out" "## worktree へ委譲する" "writing-plans/$tool: 委譲手順の節が展開される"
  assert_not_contains "$out" "issue化" "writing-plans/$tool: issue 化の選択肢が無い"
  assert_not_contains "$out" "gh issue create" "writing-plans/$tool: plan は issue にしない"
  assert_not_contains "$out" "gh repo view" "writing-plans/$tool: gh の判定を持たない"
  assert_not_contains "$out" "承認・保存" "writing-plans/$tool: コミットする選択肢が無い"
done

# brainstorming の gate には worktree の分岐が出ない。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/brainstorming/SKILL.md" "$tool")"
  assert_not_contains "$out" "worktree" "brainstorming/$tool: worktree の分岐が出ない"
done

# 委譲手順は共有パーシャルに 1 本だけ置く。
handoff="$(render_template "agent-skills/_worktree-handoff.md" "claude")"
assert_contains "$handoff" "## worktree へ委譲する" "_worktree-handoff: 節の見出しがある"
assert_contains "$handoff" "HERDR_ENV" "_worktree-handoff: herdr 環境かを判定する"
assert_contains "$handoff" "herdr worktree create" "_worktree-handoff: worktree を workspace として作る"
assert_contains "$handoff" '--workspace "$HERDR_WORKSPACE_ID"' "_worktree-handoff: 自分の workspace を渡す"
assert_contains "$handoff" "--no-focus" "_worktree-handoff: ユーザーの視線を奪わない"
assert_contains "$handoff" "herdr agent start" "_worktree-handoff: 委譲先の Claude を起動する"
assert_contains "$handoff" "herdr agent prompt" "_worktree-handoff: 初回の指示を送る"
assert_contains "$handoff" "subagent-driven-development" "_worktree-handoff: 実行方式を指定する"
assert_contains "$handoff" "絶対パス" "_worktree-handoff: plan を絶対パスで渡す"
assert_contains "$handoff" "閉じない" "_worktree-handoff: 委譲元の pane を閉じない"
assert_not_contains "$handoff" "dangerously-skip-permissions" "_worktree-handoff: 無人起動しない"

# writing-plans は委譲手順を共有パーシャルから取り込み、自前の本文を持たない。
src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/writing-plans/SKILL.md")"
assert_contains "$src" 'includeTemplate "agent-skills/_worktree-handoff.md"' \
  "writing-plans: 委譲手順を共有パーシャルから取り込む"
assert_not_contains "$src" "herdr worktree create" "writing-plans: 委譲手順の本文を自前で持たない"

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

# SDD のエスカレーションは model 上書きではなく agent の切り替えで表す。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "$tool")"
  assert_contains "$out" "sdd-implementer-think" "sdd/$tool: 昇格用 agent を指す"
  assert_not_contains "$out" 'model: opus' "sdd/$tool: model 上書きを指示しない"
  assert_contains "$out" "[deterministic-loop]" "sdd/$tool: 論理名で経路を書く"
done

# Claude 版だけが workflow 経路を既定にする。
claude_out="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "claude")"
assert_contains "$claude_out" "Workflow" "sdd/claude: Workflow を指す"

codex_out="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "codex")"
assert_contains "$codex_out" "利用不可" "sdd/codex: 手動経路へ落ちる"

# [deterministic-loop] を持たないツールには手動経路が既定として出て、
# Workflow 固有の記述（存在しないスクリプトや引数名）が 1 つも残らない。
for tool in codex opencode; do
  out="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "$tool")"
  assert_contains "$out" "手動経路（既定）" "sdd/$tool: 手動経路が既定として出る"
  assert_not_contains "$out" "手動経路（フォールバック）" "sdd/$tool: 手動経路をフォールバック扱いしない"
  assert_not_contains "$out" "sdd-task.js" "sdd/$tool: workflow スクリプト名が残っていない"
  assert_not_contains "$out" "sdd-final-review.js" "sdd/$tool: 最終レビュー workflow 名が残っていない"
  assert_not_contains "$out" "scriptPath" "sdd/$tool: workflow の引数名が残っていない"
  assert_not_contains "$out" "workflow" "sdd/$tool: 小文字の workflow 表記が残っていない"
  assert_not_contains "$out" "Workflow" "sdd/$tool: Workflow ツールを指さない"
done

# scripts のパスは全ツールで ~/.agents/skills 側を指す。
assert_contains "$codex_out" ".agents/skills/subagent-driven-development/scripts" \
  "sdd/codex: scripts は共有パスを叩く"
assert_not_contains "$codex_out" ".config/claude/skills/subagent-driven-development/scripts" \
  "sdd/codex: 旧 scripts パスが残っていない"

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

# _worktree-handoff は step 3/4 を 1 ブロックに統合し、失敗時の片付けを step 2-4 に限定する。
assert_contains "$handoff" '$out' "_worktree-handoff: create の応答を bash 変数で受ける"
assert_not_contains "$handoff" '### 4. 応答から' "_worktree-handoff: step 4 が独立した節として残っていない"
assert_contains "$handoff" "タイムアウトは失敗ではない" "_worktree-handoff: timeout を失敗扱いしない"
assert_contains "$handoff" "step 2〜4" "_worktree-handoff: 片付けの対象を限定する"
assert_contains "$handoff" "初回指示の到達は未確認である" "_worktree-handoff: step 5 以降は worktree を消さず報告する"

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

# SDD の sdd-run 経路。3 ツールすべてに出る（controller がどのツールでも bash から叩けるため）。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "$tool")"
  assert_contains "$out" "sdd-run 経路" "$tool: sdd-run 経路の節がある"
  assert_contains "$out" "HERDR_ENV" "$tool: 起動条件を書いている"
  assert_contains "$out" "sdd-run" "$tool: orchestrator を指している"
  assert_contains "$out" "routing.json" "$tool: エンジンの決め方を指している"
done

# 経路の優先順位。HERDR_ENV=1 の claude では sdd-run 経路と [deterministic-loop] の
# 両方の条件が成立するので、どちらが優先するかが書かれていないと実行のたびに変わる。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "$tool")"
  assert_contains "$out" "この節が他のすべての経路に優先する" "$tool: sdd-run 経路の優先を明示する"
done
assert_contains "$claude_out" "HERDR_ENV\` が \`1\` でないときの既定" \
  "sdd/claude: [deterministic-loop] は HERDR_ENV=1 でないときの既定"
assert_not_contains "$claude_out" "[deterministic-loop] が使えるならそちらが既定" \
  "sdd/claude: 既定を名乗る経路が 2 つにならない"

# sdd-run 経路では worktree の作成・セットアップ・片付けを自動化する。
sdd_claude="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "claude")"
assert_not_contains "$sdd_claude" "1 タスクだけの波でも worktree を作る" \
  "SDD: 単独波でも worktree を作るという旧規則が残っていない"
assert_contains "$sdd_claude" "worktrunk" "SDD: worktree は worktrunk が作る"
assert_contains "$sdd_claude" "wt remove --no-delete-branch" "SDD: worktree の片付けは wt が行う"

# implementer は波の中で全体スイートを回さない。並行するとタスク数だけ重複する。
impl_prompt="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/prompts/sdd-implementer.md")"
assert_contains "$impl_prompt" "全体のスイートは回しません" \
  "implementer: タスク中は focused test だけにする"

# sdd-run 経路と HERDR_ENV 未設定経路の手順を保持する。
sdd="$(render_template "agent-skills/subagent-driven-development/SKILL.md" "claude")"
assert_contains "$sdd" "scripts/sdd-run --plan" "SDD: sdd-run を呼ぶ"
assert_contains "$sdd" "git worktree add" "SDD: 未設定経路の worktree 作成手順がある"
assert_contains "$sdd" "git merge --no-ff" "SDD: 未設定経路のマージ手順がある"
assert_contains "$sdd" "git worktree remove" "SDD: 未設定経路の worktree 片付け手順がある"
assert_contains "$sdd" "git branch -d" "SDD: 未設定経路のブランチ片付け手順がある"
assert_not_contains "$sdd" "herdr 経路" "SDD: 旧 herdr 経路表記が残っていない"
assert_contains "$sdd" "NEEDS_ATTENTION" "SDD: 返り値の裁定を書く"
assert_contains "$sdd" "CONFLICT" "SDD: マージ衝突の扱いを書く"
assert_not_contains "$sdd" "herdr worktree create" "SDD: worktree の作成手順を controller に書かせない"
assert_not_contains "$sdd" "herdr pane split" "SDD: pane の手順を controller に書かせない"
assert_not_contains "$sdd" "anchor-pane" "SDD: 廃止した引数が残っていない"
assert_contains "$sdd" "worktrunk" "SDD: worktree は worktrunk が作ると書く"

# braid の呼び方は共有パーシャルに 1 本だけ置く。
braid_inv="$(render_template "agent-skills/_braid-invocation.md" "claude")"
assert_contains "$braid_inv" "## braid の呼び方" "_braid-invocation: 節の見出しがある"
assert_contains "$braid_inv" "command -v braid" "_braid-invocation: braid が PATH にあるか確かめる"
assert_contains "$braid_inv" "git rev-parse --is-inside-work-tree" \
  "_braid-invocation: cwd が git リポジトリか確かめる"
assert_contains "$braid_inv" "--dry-run --json" "_braid-invocation: 本実行の前に dry-run を通す"
assert_contains "$braid_inv" "braid cancel" "_braid-invocation: 停止の手段を書く"
assert_contains "$braid_inv" "braid status" "_braid-invocation: run の追い方を書く"
assert_contains "$braid_inv" "リトライしない" "_braid-invocation: 失敗を再試行しない"
assert_not_contains "$braid_inv" "target/release/braid" "_braid-invocation: 開発中のパスを書かない"

# レシピごとの必須引数。表の drift を検出するため、レシピ名だけでなく引数名も assert する。
required_args_for() {
  case "$1" in
    research) echo "topic" ;;
    decide) echo "problem" ;;
    debate) echo "proposal" ;;
    fanout) echo "items task" ;;
    review) echo "requirements review_file" ;;
    implement) echo "requirements" ;;
    waves) echo "waves spec_dir" ;;
  esac
}

# braid スキルはレシピ 7 本を表に持ち、呼び方は共有パーシャルから取り込む。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/braid/SKILL.md" "$tool")"
  for recipe in research decide debate fanout review implement waves; do
    assert_contains "$out" "\`$recipe\`" "braid/$tool: レシピ $recipe が表にある"
    for arg in $(required_args_for "$recipe"); do
      assert_contains "$out" "\`$arg\`" "braid/$tool: $recipe の必須引数 $arg が表にある"
    done
  done
  assert_contains "$out" "## braid の呼び方" "braid/$tool: 呼び方の節が展開される"
done

braid_src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/braid/SKILL.md")"
assert_contains "$braid_src" 'includeTemplate "agent-skills/_braid-invocation.md"' \
  "braid: 呼び方を共有パーシャルから取り込む"
assert_not_contains "$braid_src" "command -v braid" "braid: 呼び方の本文を自前で持たない"

# SDD 外の単発レビューは review package をリポジトリ内に作り、braid の review レシピを呼ぶ。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/requesting-code-review/SKILL.md" "$tool")"
  assert_contains "$out" "_cellfusion/reviews/" "rcr/$tool: package をリポジトリ内に作る"
  assert_contains "$out" "braid run review" "rcr/$tool: review レシピを呼ぶ"
  assert_contains "$out" "--arg requirements=" "rcr/$tool: requirements 引数を渡す"
  assert_contains "$out" "--arg review_file=" "rcr/$tool: review_file 引数を渡す"
  assert_contains "$out" "## braid の呼び方" "rcr/$tool: 呼び方の節が展開される"
  assert_not_contains "$out" "mktemp -t review" "rcr/$tool: /tmp に package を作らない"
  assert_not_contains "$out" 'requirements=<' "rcr/$tool: bash ブロックの中で < をリダイレクトにしない"
  assert_contains "$out" "SDD の中では従来経路" "rcr/$tool: SDD 内の経路は変えない"
  assert_contains "$out" "cellfusion-workdir" "rcr/$tool: reviews を cellfusion-workdir 経由で作る"
done

rcr_src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/requesting-code-review/SKILL.md")"
assert_contains "$rcr_src" 'includeTemplate "agent-skills/_braid-invocation.md"' \
  "rcr: 呼び方を共有パーシャルから取り込む"

# 3 つの配布先すべてに .tmpl がある。
for d in private_dot_agents/skills \
         private_dot_config/claude/skills \
         private_dot_config/opencode/skills; do
  assert_eq "$([ -f "$CHEZMOI_SOURCE/$d/braid/SKILL.md.tmpl" ] && echo yes || echo no)" \
            "yes" "braid: 配布先に .tmpl がある: $d"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
