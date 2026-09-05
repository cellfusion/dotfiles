---
name: verification-before-completion
description: >-
  完了・修正済み・テスト通過を主張する前に、MAD の review recipe で子の検証記録を確認するときに使う。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD review の入口

親は本文を作らない。主張する状態、要件、検証コマンド、対象成果物の絶対パスを MAD の `review` recipe に
渡す。子が新しい検証を実行し、終了コードと出力を読み、要件カバレッジを確認して検証記録を作る。
親は backend 選択、状態遷移、子の制御、ユーザー gate だけを担う。

`review` recipe の手順は `multi-agent-development` スキルが持つ。run ディレクトリの作り方、
backend の選び方、子の起動、state と handoff の契約はそこに書いてある。
MAD の `review` を開始する前に `~/.agents/skills/multi-agent-development/SKILL.md` を読み込む。

## 完了条件

1. MAD の `review` を開始する。子は検証コマンド、出力、要件ごとの根拠、失敗の有無を正規成果物へ残し、
   絶対パスを `handoff.json` に記録する。
2. 親は採用 attempt の state と handoff を確認する。親は成功を推測・宣言せず、検証本文や出力を作らない。
3. 検証対象、失敗の扱い、または受け入れ基準にユーザー判断が必要な場合だけ [ask-user] で relay し、
   `waiting_for_user` に記録する。
4. 新しい検証記録が要求を裏付け、最終 review が `ok` のときだけ、その絶対パスを MAD の `delivery`
   handoff に記録する。失敗・欠落・未解決なら `failed` または `unresolved` として停止する。

修正が必要なら、検証記録と review の絶対パスを MAD の `implement` recipe へ渡す。子が TDD の RED/GREEN
と必要な再検証を担う。
