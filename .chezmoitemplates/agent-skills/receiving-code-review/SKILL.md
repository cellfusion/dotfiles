---
name: receiving-code-review
description: >-
  コードレビューの指摘を評価し、必要な修正を MAD の review / implement recipe に委譲するときに使う。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD review の入口

親は本文を作らない。レビュー指摘、requirements、review package、対象成果物の絶対パスを MAD の `review`
recipe に渡す。子が指摘をコードベース・テスト・既存決定と突き合わせ、採用、却下、追加調査の根拠を
成果物に残す。親は backend 選択、状態遷移、子の制御、ユーザー gate だけを担う。

## 実行

1. MAD の `review` を開始する。子は分析結果と採用した指摘の絶対パスを `handoff.json` に残す。
   親は指摘の技術評価や返信本文を作らない。
2. 子が不明瞭な指摘、ユーザーの決定との衝突、または複数の妥当な remediation を報告した場合だけ、
   親は [ask-user] で decision request を relay し、run を `waiting_for_user` に記録する。
3. 親は state、採用 attempt、handoff だけを確認する。失敗や成果物欠落を隠して実装へ進めない。
4. 採用された修正が必要なら、根拠・review package・対象パスを MAD の `implement` recipe へ絶対パスで
   handoff する。子が TDD、debug、再 review を担う。

レビューの内容を会話上の同調や反論で消費せず、採用 attempt の成果物を正本にする。
