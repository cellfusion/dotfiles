#!/bin/bash
# SessionStart hook (matcher: "startup|clear|compact")
# 開発ワークフロースキルのルーターを注入する。
# compact 復帰時は CLAUDE.md の最重要ルール要約も追加する。

set -uo pipefail

INPUT=$(cat)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty')

ROUTER=$(cat <<'ROUTER_EOF'
<開発ワークフロー>
応答・調査・確認質問より先に、該当するスキルを起動する。1% でも該当しそうなら起動する。起動したら「<skill> を使う」と宣言し、スキルにチェックリストがあれば 1 項目 1 todo にする。

依頼の種類 → 最初に起動するスキル
- 新機能・変更・「作りたい」「追加したい」 → brainstorming
- バグ・不具合・「動かない」「直らない」 → systematic-debugging
- 実装プランが既にある → subagent-driven-development（subagent が使えないときだけ executing-plans）
- 実装が終わった・マージしたい → finishing-a-development-branch
- 完了・修正済み・テスト通過を主張する直前 → verification-before-completion
- コードレビューの指摘を受け取った → receiving-code-review

process 系スキル（上記）が先、実装系スキル（frontend-design 等）は後。
「単純な質問だから」「先に状況を調べてから」「今回は大げさだから」は起動しない理由にならない。
CLAUDE.md とユーザーの明示指示はスキルより優先する。

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
