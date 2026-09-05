---
name: brainstorming
description: >-
  新機能・変更を始める前に、MAD の spec recipe へ調査・設計・spec 作成を委譲するときに使う。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD spec の入口

親は本文を作らない。ユーザーの目的、既知の制約、既存成果物の絶対パスを MAD の `spec` recipe に渡す。
子が必要な調査、設計案、spec、self-review を行う。親は backend 選択、状態遷移、子の制御、および
ユーザーとの decision / approval gate だけを担う。

## 実行

1. `~/.agents/skills/_shared/scripts/cellfusion-workdir` を実行してから
   `_cellfusion/orchestration/<run-id>/` を作り、MAD の共通契約に従って backend を一度だけ選ぶ。
2. MAD の `spec` を開始する。子は `handoff.json` に調査成果物と正規 spec の絶対パスを残す。
3. 子が判断を求めたときだけ、親は decision request を [ask-user] で relay し、run を
   `waiting_for_user` に記録する。親は設計案や spec 本文を会話へ転記・作成しない。
4. spec review が `ok` になったら、親は `handoff.json` の採用 attempt と正規 spec の絶対パスを確認する。
5. 親は spec approval request を [ask-user] で relay する。承認後は MAD の `plan` recipe へ spec の
   絶対パスだけを handoff する。未承認のまま実装へ進めない。

子の失敗、成果物欠落、または未解決の判断がある場合は後段を開始しない。MAD の state と handoff を
確認して再指示・再実行・停止を裁定する。
