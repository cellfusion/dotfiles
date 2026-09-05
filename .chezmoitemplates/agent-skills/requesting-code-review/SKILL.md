---
name: requesting-code-review
description: >-
  作業の区切り、実装後、merge 前のコードレビューを MAD の review recipe に委譲するときに使う。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD review の入口

親は本文を作らない。requirements、review package、対象成果物の絶対パスを MAD の `review` recipe に渡す。
子の観点別 `reviewer` が並列に評価し、`review-synthesizer` または `final-reviewer` が採用可能な指摘を
統合する。親は backend 選択、状態遷移、子の制御、ユーザー gate だけを担う。

## 実行

1. review package を正規 `_cellfusion/reviews/` または SDD ledger に作り、その絶対パスを入力にする。
   親は diff や要件を会話へ転記してレビュー本文を作らない。
2. MAD の `review` を開始する。各子は findings と統合 review の絶対パスを `handoff.json` に残す。
3. 親は各 attempt の state と統合前 handoff を確認する。失敗 review、成果物欠落、重要な要件変更が
   あれば統合を完了にせず、再指示・再実行・停止を裁定する。
4. 要件変更または remediation の優先順位にユーザー判断が必要な場合だけ [ask-user] で relay し、
   `waiting_for_user` に記録する。
5. 採用 attempt の最終 review 成果物だけを後段の MAD `implement` または `delivery` phase へ絶対パスで
   handoff する。

Critical または Important を自分で直さない。修正が必要なら該当成果物を MAD の `implement` recipe へ
渡し、子の TDD と再 review を通す。
