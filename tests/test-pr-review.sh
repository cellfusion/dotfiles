#!/usr/bin/env bash
# pr-review skill の共有契約を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

skill_path="$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/pr-review/SKILL.md"
command_path="$CHEZMOI_SOURCE/private_dot_config/claude/commands/pr-review.md"

# 共有本体・3 ツールの wrapper・Claude の入口を作る。
for path in \
  "$skill_path" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/pr-review/SKILL.md.tmpl" \
  "$CHEZMOI_SOURCE/private_dot_config/claude/skills/pr-review/SKILL.md.tmpl" \
  "$CHEZMOI_SOURCE/private_dot_config/opencode/skills/pr-review/SKILL.md.tmpl" \
  "$command_path"; do
  assert_eq "$([ -f "$path" ] && echo yes || echo no)" "yes" \
    "pr-review: 必須ファイルがある: ${path#"$CHEZMOI_SOURCE/"}"
done

skill="$(render_template "agent-skills/pr-review/SKILL.md" "codex" 2>/dev/null || true)"

# 共通 skill は引数・入口と実行経路を定義する。
assert_contains "$skill" "name: pr-review" "pr-review: frontmatter の name が一致する"
assert_contains "$skill" "/pr-review" "pr-review: slash command の入口がある"
assert_contains "$skill" "PR_NUMBER" "pr-review: PR 番号を変数として扱う"
assert_contains "$skill" "^[1-9][0-9]*$" "pr-review: 正の整数だけを受け付ける"
assert_contains "$skill" "gh pr view" "pr-review: GitHub CLI で PR を取得する"
assert_contains "$skill" "GitHub" "pr-review: GitHub 専用であることを明示する"

# 隔離経路は Paseo/Herdr/native/git の順に存在することを固定する。
assert_contains "$skill" "Paseo" "pr-review: Paseo 経路がある"
assert_contains "$skill" "HERDR_ENV" "pr-review: Herdr 経路の判定がある"
assert_contains "$skill" "herdr worktree" "pr-review: Herdr worktree 経路がある"
assert_contains "$skill" "native" "pr-review: native worktree 経路がある"
assert_contains "$skill" "git worktree" "pr-review: git worktree の経路がある"

# 一次レビュー、差分リスクに応じた専門レビュー、成果物の契約を固定する。
assert_contains "$skill" "一次レビュー" "pr-review: 一次レビューを行う"
assert_contains "$skill" "差分リスク" "pr-review: 差分リスクを評価する"
assert_contains "$skill" "専門レビュー" "pr-review: リスクに応じて専門レビューを追加する"
assert_contains "$skill" "routing.json" "pr-review: 専門レビューの routing を参照する"
assert_contains "$skill" "Markdown" "pr-review: Markdown 成果物を保存する"
assert_contains "$skill" "JSON" "pr-review: JSON 成果物を保存する"
assert_contains "$skill" "親リポジトリ" "pr-review: 成果物を親リポジトリへ保存する"

# PR 側の指示を実行せず、base 側の指示と利用可能な専門 skill を使う。
assert_contains "$skill" "base 側" "pr-review: base 側の指示を使う"
assert_contains "$skill" "PR 側" "pr-review: PR 側の指示を信頼しない"
assert_contains "$skill" "専門スキル" "pr-review: 実行時に利用可能な専門スキルを使う"
assert_contains "$skill" "公式資料" "pr-review: 公式資料を根拠にする"

# レビュー agent は読み取りとコメント投稿だけを行う。GitHub の review 操作は使わない。
assert_contains "$skill" "commit" "pr-review: commit 禁止を明示する"
assert_contains "$skill" "push" "pr-review: push 禁止を明示する"
assert_contains "$skill" "approve" "pr-review: approve 禁止を明示する"
assert_contains "$skill" "request-changes" "pr-review: request-changes 禁止を明示する"
assert_not_contains "$skill" "gh pr review --approve" "pr-review: approve 操作を実行しない"
assert_not_contains "$skill" "gh pr review --request-changes" "pr-review: request-changes 操作を実行しない"

# 投稿前の確認・SHA 再検証と、成功時だけの後始末を固定する。
assert_contains "$skill" "[ask-user]" "pr-review: 投稿前にユーザー確認を取る"
assert_contains "$skill" "baseRefOid" "pr-review: base SHA を取得する"
assert_contains "$skill" "headRefOid" "pr-review: head SHA を取得する"
assert_contains "$skill" "再検証" "pr-review: 投稿前に SHA を再検証する"
assert_contains "$skill" "comments" "pr-review: issue comment API を使う"
assert_contains "$skill" "投稿成功時" "pr-review: 投稿成功時だけ cleanup する"
assert_contains "$skill" "片付け" "pr-review: worktree の片付け条件を定義する"

# Claude command は入口だけを提供し、本体の手順を重複させない。
command="$(cat "$command_path" 2>/dev/null || true)"
assert_contains "$command" "agent-skills/pr-review/SKILL.md" "pr-review command: 共有本体を読む"
assert_contains "$command" '$ARGUMENTS' "pr-review command: 引数を共有本体へ渡す"
assert_not_contains "$command" "gh pr view" "pr-review command: GitHub 手順を重複させない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
