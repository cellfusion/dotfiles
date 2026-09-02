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

# skill 本文に示す 3 つの最小 JSON schema 例を実際に parse し、canonical summary の
# identity・verdict・finding 集合が相互に一致することを検証する。
metadata_sample="$(printf '%s\n' "$skill" | sed -n '/^`metadata.json`:/,/^```$/p' | sed '1d; /^```json$/d; /^```$/d')"
findings_sample="$(printf '%s\n' "$skill" | sed -n '/^`findings.json`:/,/^```$/p' | sed '1d; /^```json$/d; /^```$/d')"
checks_sample="$(printf '%s\n' "$skill" | sed -n '/^`checks.json` の最小形は次である。$/,/^```$/p' | sed '1d; /^```json$/d; /^```$/d')"
for sample_name in metadata findings checks; do
  sample="${sample_name}_sample"
  assert_eq "$(printf '%s\n' "${!sample}" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" \
    "yes" "pr-review schema: ${sample_name}.json の例が JSON として妥当"
done
schema_consistent="$(jq -n -e \
  --argjson metadata "$metadata_sample" \
  --argjson findings "$findings_sample" \
  --argjson checks "$checks_sample" \
  '
    ($metadata.prNumber == $findings.prNumber and $findings.prNumber == $checks.prNumber)
    and ($metadata.repository == $findings.repository and $findings.repository == $checks.repository)
    and ($metadata.baseRefOid == $findings.baseRefOid and $findings.baseRefOid == $checks.baseRefOid)
    and ($metadata.headRefOid == $findings.headRefOid and $findings.headRefOid == $checks.headRefOid)
    and ($metadata.mergeBaseOid == $findings.mergeBaseOid and $findings.mergeBaseOid == $checks.mergeBaseOid)
    and ($metadata.verdict == $findings.verdict and $findings.verdict == $checks.verdict)
    and ($metadata.findingCount == $findings.findingCount and $findings.findingCount == $checks.findingCount)
    and ($metadata.findingIds == $findings.findingIds and $findings.findingIds == $checks.findingIds)
    and ($findings.findingCount == ($findings.findings | length))
    and ($findings.findingIds == ($findings.findings | map(.id)))
    and (($findings.findings | map(.id) | unique | length) == $findings.findingCount)
    and ($findings.findings | all(.priority | IN("P0", "P1", "P2", "P3")))
    and ($findings.findings | all(.confidence | IN("high", "medium", "low")))
  ' >/dev/null && echo yes || echo no)"
assert_eq "$schema_consistent" "yes" "pr-review schema: 3 JSON の identity と finding 集合が一致する"

# 共通 skill は引数・入口と実行経路を定義する。
assert_contains "$skill" "name: pr-review" "pr-review: frontmatter の name が一致する"
assert_contains "$skill" "/pr-review" "pr-review: slash command の入口がある"
assert_contains "$skill" "PR_NUMBER" "pr-review: PR 番号を変数として扱う"
assert_contains "$skill" "^[1-9][0-9]*$" "pr-review: 正の整数だけを受け付ける"
assert_contains "$skill" "gh pr view" "pr-review: GitHub CLI で PR を取得する"
assert_contains "$skill" "GitHub" "pr-review: GitHub 専用であることを明示する"
assert_contains "$skill" "git fetch" "pr-review: 固定 SHA がローカルに無い場合も取得する"
assert_contains "$skill" "MERGE_BASE" "pr-review: PR の merge-base から差分を作る"
assert_contains "$skill" "context/diff.patch" "pr-review: 固定 diff package を作る"
assert_contains "$skill" "context/pr-body.md" "pr-review: PR 本文を未信頼データとして保存する"
assert_contains "$skill" "AGENT_CWD" "pr-review: agent の cwd を PR worktree から隔離する"
assert_contains "$skill" 'isolation: "local"' "pr-review: Paseo agent workspace を neutral local にする"
assert_contains "$skill" 'cwd "$AGENT_CWD"' "pr-review: Herdr agent pane を neutral cwd で起動する"
assert_contains "$skill" "自動ロードされない" "pr-review: PR 側 instruction の runtime 自動ロードを防ぐ"
assert_contains "$skill" "instruction_root" "pr-review: cwd の親も instruction 注入対象から除外する"

# メタデータを隔離より先に固定し、Paseo/Herdr/native/git の経路を定義する。
assert_contains "$skill" "baseRefOid" "pr-review: isolation 前に base SHA を固定する"
assert_contains "$skill" "headRefOid" "pr-review: isolation 前に head SHA を固定する"
assert_contains "$skill" "headRepository" "pr-review: fork の head repository も取得する"
assert_contains "$skill" "checkout-pr" "pr-review: Paseo の checkout-pr mode を使う"
assert_contains "$skill" "create_workspace" "pr-review: Paseo workspace を作る"
assert_contains "$skill" "list_profiles" "pr-review: Paseo の agent profile を毎回確認する"
assert_contains "$skill" "create_agent" "pr-review: Paseo の agent を起動する"
assert_contains "$skill" "archive_workspace" "pr-review: Paseo workspace を成功時だけ archive する"
assert_contains "$skill" "gh pr checkout" "pr-review: worktree 内で PR を checkout する"
assert_contains "$skill" "--detach" "pr-review: head SHA を detached checkout に固定する"
assert_contains "$skill" "herdr agent start" "pr-review: Herdr の agent start を使う"
assert_contains "$skill" "herdr agent prompt" "pr-review: Herdr の agent prompt を使う"
assert_contains "$skill" "git worktree add" "pr-review: native 非対応時の git worktree 経路がある"
assert_contains "$skill" "git worktree remove" "pr-review: native git worktree の cleanup がある"
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
assert_contains "$skill" "metadata.json" "pr-review: metadata.json を保存する"
assert_contains "$skill" "findings.json" "pr-review: findings.json を保存する"
assert_contains "$skill" "checks.json" "pr-review: checks.json を保存する"
assert_contains "$skill" "agent別" "pr-review: agent 別中間成果物を保存する"
assert_contains "$skill" 'pr-$PR_NUMBER-$HEAD_OID' "pr-review: PR 番号と head SHA で成果物を分離する"
assert_contains "$skill" '"P0"' "pr-review: finding の P0 を定義する"
assert_contains "$skill" '"P1"' "pr-review: finding の P1 を定義する"
assert_contains "$skill" '"P2"' "pr-review: finding の P2 を定義する"
assert_contains "$skill" '"P3"' "pr-review: finding の P3 を定義する"
assert_contains "$skill" "confidence" "pr-review: finding の確信度を保存する"
assert_contains "$skill" "impact" "pr-review: finding の影響を保存する"
assert_contains "$skill" "inline" "pr-review: inline 可否を保存する"
assert_contains "$skill" "specialistReviews" "pr-review: 専門レビュー結果を構造化する"
assert_contains "$skill" "not_run" "pr-review: 未実行の専門レビューを記録する"
assert_contains "$skill" "全 JSON" "pr-review: JSON ごとに revision identity を持たせる"
assert_contains "$skill" "base SHA と head SHA" "pr-review: 成果物に base/head SHA を含める"
assert_contains "$skill" "findingCount" "pr-review: finding 件数を全成果物で一致させる"
assert_contains "$skill" "findingIds" "pr-review: finding ID を全成果物で一致させる"
assert_contains "$skill" "agentWorkspaceId" "pr-review: Paseo agent workspace の所有情報を保存する"

# PR 側の指示を実行せず、base 側の指示と利用可能な専門 skill を使う。
assert_contains "$skill" "base 側" "pr-review: base 側の指示を使う"
assert_contains "$skill" "PR 側" "pr-review: PR 側の指示を信頼しない"
assert_contains "$skill" "専門スキル" "pr-review: 実行時に利用可能な専門スキルを使う"
assert_contains "$skill" "公式資料" "pr-review: 公式資料を根拠にする"
assert_contains "$skill" "Flutter" "pr-review: Flutter/Dart を検出する"
assert_contains "$skill" "Swift" "pr-review: Swift を検出する"
assert_contains "$skill" "Kotlin" "pr-review: Kotlin を検出する"
assert_contains "$skill" "TypeScript" "pr-review: TypeScript を検出する"
assert_contains "$skill" "React" "pr-review: React を検出する"
assert_contains "$skill" "Rust" "pr-review: Rust を検出する"
assert_contains "$skill" "Clean Architecture" "pr-review: Clean Architecture を実採用時だけ確認する"
assert_contains "$skill" "一律強制しない" "pr-review: architecture を一律強制しない"
assert_contains "$skill" "OWASP" "pr-review: security lens の根拠を示す"
assert_contains "$skill" "concurrency" "pr-review: concurrency/performance lens の条件がある"
assert_contains "$skill" "API/type" "pr-review: API/type lens の条件がある"
assert_contains "$skill" "stack-specific" "pr-review: stack-specific lens の条件がある"
assert_contains "$skill" "テスト" "pr-review: tests lens の条件がある"
assert_contains "$skill" "依存インストール" "pr-review: 依存インストールを自動実行しない"
assert_contains "$skill" "deploy" "pr-review: deploy を自動実行しない"

# レビュー agent は読み取りとコメント投稿だけを行う。GitHub の review 操作は使わない。
assert_contains "$skill" "commit" "pr-review: commit 禁止を明示する"
assert_contains "$skill" "push" "pr-review: push 禁止を明示する"
assert_contains "$skill" "approve" "pr-review: approve 禁止を明示する"
assert_contains "$skill" "request-changes" "pr-review: request-changes 禁止を明示する"
assert_not_contains "$skill" "gh pr review" "pr-review: GitHub review CLI を実行しない"
assert_not_contains "$skill" "gh pr review --approve" "pr-review: approve 操作を実行しない"
assert_not_contains "$skill" "gh pr review --request-changes" "pr-review: request-changes 操作を実行しない"

# 投稿前の確認・SHA 再検証と、成功時だけの後始末を固定する。
assert_contains "$skill" "[ask-user]" "pr-review: 投稿前にユーザー確認を取る"
assert_contains "$skill" "baseRefOid" "pr-review: base SHA を取得する"
assert_contains "$skill" "headRefOid" "pr-review: head SHA を取得する"
assert_contains "$skill" "再検証" "pr-review: 投稿前に SHA を再検証する"
assert_contains "$skill" 'pulls/$PR_NUMBER/reviews' "pr-review: Pull Request Reviews API を使う"
assert_contains "$skill" 'event: "COMMENT"' "pr-review: review event を COMMENT に固定する"
assert_contains "$skill" "comments" "pr-review: inline comments を payload に含める"
assert_contains "$skill" 'body: (' "pr-review: inline comment ごとの body を生成する"
assert_contains "$skill" 'side: "RIGHT"' "pr-review: inline comment の side を head 側に固定する"
assert_contains "$skill" '--arg commit_id "$HEAD_OID"' "pr-review: review payload の commit_id を固定する"
assert_contains "$skill" "--method POST" "pr-review: review comment は POST する"
assert_contains "$skill" "COMMENT" "pr-review: 投稿モードを COMMENT に固定する"
assert_contains "$skill" "投稿失敗" "pr-review: 投稿失敗時は成果物を保持する"
assert_contains "$skill" "SHA 不一致" "pr-review: SHA 不一致時は成果物を保持する"
assert_contains "$skill" "確認拒否" "pr-review: 確認拒否時は成果物を保持する"
assert_contains "$skill" "投稿成功時" "pr-review: 投稿成功時だけ cleanup する"
assert_contains "$skill" "片付け" "pr-review: worktree の片付け条件を定義する"
assert_contains "$skill" "HEAD と status" "pr-review: agent 前後の worktree 不変性を検証する"
assert_contains "$skill" 'REVIEW_WORKTREE` へ `cd` しない' "pr-review: current agent を PR worktree に移動しない"
assert_not_contains "$skill" "using-git-worktrees の setup" "pr-review: worktree skill の setup をそのまま実行しない"
assert_not_contains "$skill" "git worktree prune" "pr-review: ユーザー管理 worktree 全体を prune しない"
assert_contains "$skill" "通常の review worktree では実行せず" "pr-review: PR コード実行を通常 worktree で行わない"
assert_contains "$skill" "network disabled" "pr-review: targeted check の network を無効化する"

# revision 固定・確認・POST・cleanup の順序を検証する。
metadata_line="$(printf '%s\n' "$skill" | grep -n 'PR_JSON=$(gh pr view' | head -1 | cut -d: -f1)"
isolation_line="$(printf '%s\n' "$skill" | grep -n '^### Paseo$' | head -1 | cut -d: -f1)"
ask_line="$(printf '%s\n' "$skill" | grep -n '^成果物と投稿本文を作ったら' | head -1 | cut -d: -f1)"
post_line="$(printf '%s\n' "$skill" | grep -n '^response=$(gh api --method POST' | head -1 | cut -d: -f1)"
cleanup_line="$(printf '%s\n' "$skill" | grep -n '^投稿成功と comment URL' | head -1 | cut -d: -f1)"
assert_eq "$([ -n "$metadata_line" ] && [ -n "$isolation_line" ] && [ "$metadata_line" -lt "$isolation_line" ] && echo yes || echo no)" \
  "yes" "pr-review: metadata取得がisolationより先にある"
assert_eq "$([ -n "$ask_line" ] && [ -n "$post_line" ] && [ -n "$cleanup_line" ] && [ "$ask_line" -lt "$post_line" ] && [ "$post_line" -lt "$cleanup_line" ] && echo yes || echo no)" \
  "yes" "pr-review: 確認後POST、成功後cleanupの順序を守る"

# Claude command は入口だけを提供し、本体の手順を重複させない。
command="$(cat "$command_path" 2>/dev/null || true)"
assert_contains "$command" "agent-skills/pr-review/SKILL.md" "pr-review command: 共有本体を読む"
assert_contains "$command" '$ARGUMENTS' "pr-review command: 引数を共有本体へ渡す"
assert_not_contains "$command" "gh pr view" "pr-review command: GitHub 手順を重複させない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
