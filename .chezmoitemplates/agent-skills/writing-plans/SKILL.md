---
name: writing-plans
description: >-
  承認済み spec から実装計画を作るとき、MAD の plan recipe へ plan 作成と review を委譲する。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD plan の入口

親は本文を作らない。承認済み spec の絶対パスを MAD の `plan` recipe に渡す。子の `plan-author` が
`_cellfusion/plans/` の正規 plan を作り、`plan-reviewer` が実装可能性、検証、依存関係を review する。
親は backend 選択、状態遷移、子の制御、ユーザーの approval gate だけを担う。

`plan` recipe の手順は `multi-agent-development` スキルが持つ。run ディレクトリの作り方、
backend の選び方、子の起動、state と handoff の契約はそこに書いてある。
MAD の `plan` を開始する前に `~/.agents/skills/multi-agent-development/SKILL.md` を読み込む。

## 実行

1. `~/.agents/skills/_shared/scripts/cellfusion-workdir` を実行してから MAD の `plan` を開始し、入力には
   承認済み spec の絶対パスだけを渡す。
2. 子は plan と review の絶対パスを `handoff.json` に残す。親は plan 本文、タスク分解、依存関係を
   自分で作成・修正しない。
3. plan review が `ok` になったら、親は採用 attempt と `handoff.json` の正規 plan パスを確認する。
4. 親は plan approval request を [ask-user] で relay し、承認待ちを `waiting_for_user` に記録する。
5. 承認後は MAD の `implement` recipe へ plan、spec、既存 ledger の絶対パスだけを handoff する。

子の review が失敗、成果物が欠落、または判断が未解決なら実装を開始しない。親は state と handoff を
確認して再指示・再実行・停止を裁定する。
