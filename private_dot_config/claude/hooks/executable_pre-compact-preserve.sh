#!/bin/bash
# PreCompact hook
# Compact実行前に、要約時に保持すべき重要ルールをコンテキストに注入する。
# これにより圧縮後の要約にルールが含まれやすくなる。

cat <<'PRESERVE'
📌 COMPACT PRESERVATION NOTICE — 以下のルールは要約に必ず含めてください:

- Chezmoi管理: ~/.config配下は直接編集禁止。必ずchezmoi source (~/.local/share/chezmoi/) 側を編集。chezmoi applyはユーザー許可必須。
- Spec-Firstワークフロー: Planning → Documentation → Implementation → Testing の順序厳守。
- リサーチプロトコル: 事実確認にはWebSearch必須。複数ソースでクロスチェック。Sources:セクション必須。
- コミット: 小さく論理的な単位でコミット。
- Relay タスク管理: セッション中の作業タスクIDを保持。コミット時にtask_add_link。完了時にtask_complete(summary+verification_steps+artifacts)でreviewに遷移。
PRESERVE

exit 0
