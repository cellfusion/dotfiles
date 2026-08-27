---
name: braid
description: >-
  複数のエージェントを組み合わせた作業を braid のレシピで実行するときに使う。
  観点を分けた調査、候補案の生成と採点、立場を分けた賛否、項目ごとの並行処理、
  多観点レビュー、実装とレビューのループが対象。/braid で手動起動も可能。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# braid のレシピを実行する

braid は役割ごとに engine（codex / claude）を選び、複数のエージェントを並行・直列に組み合わせて
走らせる。run store が状態を持つので、後から `braid ls` と TUI で追える。

**中核**: 作業が同梱レシピの形にはまるなら braid を使う。はまらないなら従来どおり subagent を
使う。

## どのレシピにはまるか

| レシピ | 何に使うか | 必須引数 | 省略可能引数 |
|---|---|---|---|
| `research` | 観点を分けた調査と統合 | `topic` | `perspectives`, `researcher_role`, `synthesizer_role` |
| `decide` | 候補案の生成と採点 | `problem` | `approaches`, `criteria`, `candidate_role`, `judge_role` |
| `debate` | 立場を分けた賛否と裁定 | `proposal` | `positions`, `advocate_role`, `judge_role` |
| `fanout` | 同じ作業を項目ごとに並行 | `items`, `task` | `worker_role`, `synthesizer_role` |
| `review` | 多観点レビューと統合 | `requirements`, `review_file` | `perspectives`, `reviewer_role`, `final_reviewer_role` |
| `implement` | 単発の実装とレビューループ | `requirements` | `implementer_role`, `reviewer_role`, `max_rounds` |
| `waves` | 段階的な並行実装 | `waves`, `spec_dir` | `implementer_role`, `reviewer_role`, `re_reviewer_role`, `escalate_from`, `escalate_tier`, `escalate_engine`, `max_rounds` |

`implement` と `waves` は write 役を含む。作業ツリーか index が clean でなければ braid が実行を
拒否する。

## はまらないとき

どのレシピの形にもはまらないなら braid を使わない。従来どおり subagent を立てる。レシピで表せない
構成がどうしても必要になったときだけ `.rhai` を書く。

## 例

```bash
braid run research --arg topic='flock と pid のどちらで生死を判定するか'
braid run decide --arg problem='run store の置き場所をどこにするか'
braid run fanout --arg items='["a.ts","b.ts","c.ts"]' --arg task='型定義を洗い出す'
```

{{ includeTemplate "agent-skills/_braid-invocation.md" . }}
