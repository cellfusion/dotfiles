#!/bin/bash
# SessionStart hook (matcher: "startup|clear|compact")
# 開発ワークフロースキルのルーターを注入する。
# compact 復帰時は CLAUDE.md の最重要ルール要約も追加する。

set -uo pipefail

INPUT=$(cat)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty')

ROUTER=$(cat <<'ROUTER_EOF'
<開発ワークフロー>
依頼を読んで、必要なスキルだけを起動する。スキルの起動を応答、調査、確認質問の前提にしない。起動したスキルが明示的な宣言を求める場合だけ宣言する。

依頼の種類 → 基本経路
- 明確で局所的な変更 → 直接調査・実装する。設計の選択が残る場合だけ brainstorming
- 実装経路・作業クラス・委譲方法が不明 → task-routing
- 意図や挙動が未確定な変更 → task-routing。必要なら brainstorming
- 複数層にまたがる設計変更 → task-routing → brainstorming。必要なら writing-plans
- バグ・不具合・「動かない」「直らない」 → 根本原因が未確定なら systematic-debugging
- 実装プランが既にある → 小さければ executing-plans。並列性や独立した review が必要なら multi-agent-development
- 実装が終わった・マージしたい → finishing-a-development-branch
- 完了・修正済み・テスト通過を主張する直前 → verification-before-completion
- コードレビューの指摘を受け取った → receiving-code-review

brainstorming、writing-plans、multi-agent-development はすべての変更に必要ではない。親エージェントが依頼の明確さ、リスク、作業量から経路を選ぶ。CLAUDE.md とユーザーの明示指示はこの案内より優先する。

subagent として起動された場合、この指示は無視する。
</開発ワークフロー>
ROUTER_EOF
)

COMPACT_REMINDER=$(cat <<'COMPACT_EOF'
<compact 後のリマインダー>
compact 要約の曖昧な記述より CLAUDE.md の明示指示が常に優先する。

1. chezmoi 管理: ~/.config 配下を直接編集しない。~/.local/share/chezmoi/ 側を編集する。編集前に chezmoi diff で未反映分を確認する。chezmoi apply はユーザーの明示許可なしに実行しない
2. ドキュメント先行: 仕様変更を伴うなら docs/ を実装より先に更新する
3. リサーチ: 事実・最新情報は WebSearch で裏を取り、末尾に Sources: を付ける
4. コミット: Conventional Commits、1 コミット 1 論理変更
5. 応答は常体で簡潔に。末尾に English Expression を付ける
</compact 後のリマインダー>
COMPACT_EOF
)

if [[ "$SOURCE" == "compact" ]]; then
  CONTEXT="${ROUTER}"$'\n\n'"${COMPACT_REMINDER}"
else
  CONTEXT="$ROUTER"
fi

jq -n --arg ctx "$CONTEXT" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0
