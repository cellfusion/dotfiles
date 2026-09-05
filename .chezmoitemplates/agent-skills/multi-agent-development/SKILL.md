---
name: multi-agent-development
description: >-
  親エージェントが複数の子エージェントを組み合わせて手動でオーケストレーションするときに使う。
  観点を分けた調査、候補案の生成と採点、立場を分けた賛否、項目ごとの並行処理、
  多観点レビューが対象。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 親主導の MAD オーケストレーション

MAD は親エージェントが子エージェントを起動・監視し、フェーズごとに判断して進める。子同士の
本文は会話へ集めず、共通契約で定めた run 成果物を介して後段へ渡す。

**中核**: 作業が MAD のレシピの形にはまるなら、親が並列化・統合・介入を管理する。はまらない
作業では従来どおり単独の subagent を使う。

## どのレシピにはまるか

| レシピ | 何に使うか | 必須引数 | 省略可能引数 |
|---|---|---|---|
| `research` | 観点を分けた調査と統合 | `topic` | `perspectives`, `researcher_role`, `synthesizer_role` |
| `decide` | 候補案の生成と採点 | `problem` | `approaches`, `criteria`, `candidate_role`, `judge_role` |
| `debate` | 立場を分けた賛否と裁定 | `proposal` | `positions`, `advocate_role`, `judge_role` |
| `fanout` | 同じ作業を項目ごとに並行 | `items`, `task` | `worker_role`, `synthesizer_role` |
| `review` | 多観点レビューと統合 | `requirements`, `review_file` | `perspectives`, `reviewer_role`, `final_reviewer_role` |

どのレシピも読み取りだけを行う。ファイルを書き換えるレシピはまだ無い。

レシピごとの親主導手順と介入点はこのスキルで定義する。役割や backend の選択は、共通契約に
従って親が実行開始時に行う。

## MAD に適さないとき

どのレシピの形にもはまらないなら MAD を使わず、従来どおり subagent を立てる。

## 旧方式

既存の `mad-run` と shell recipe は互換性のために残す。手動方式から旧方式へ自動的に切り替えず、
旧方式を明示的に使う場合だけ `_mad-invocation.md` の手順を参照する。

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
