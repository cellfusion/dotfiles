---
name: multi-agent-development
description: >-
  複数のエージェントを組み合わせた作業を Paseo のレシピで実行するときに使う。
  観点を分けた調査、候補案の生成と採点、立場を分けた賛否、項目ごとの並行処理、
  多観点レビューが対象。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Paseo のレシピを実行する

MAD は役割ごとに Paseo の provider を選び、複数のエージェントを並行・直列に組み合わせて
走らせる。走っているエージェントは Paseo の daemon が持つので、後から `paseo ls` と
Paseo アプリで追える。

**中核**: 作業が同梱レシピの形にはまるなら MAD を使う。はまらないなら従来どおり subagent を
使う。

## どのレシピにはまるか

| レシピ | 何に使うか | 必須引数 | 省略可能引数 |
|---|---|---|---|
| `research` | 観点を分けた調査と統合 | `topic` | `perspectives`, `researcher_role`, `synthesizer_role` |
| `decide` | 候補案の生成と採点 | `problem` | `approaches`, `criteria`, `candidate_role`, `judge_role` |
| `debate` | 立場を分けた賛否と裁定 | `proposal` | `positions`, `advocate_role`, `judge_role` |
| `fanout` | 同じ作業を項目ごとに並行 | `items`, `task` | `worker_role`, `synthesizer_role` |
| `review` | 多観点レビューと統合 | `requirements`, `review_file` | `perspectives`, `reviewer_role`, `final_reviewer_role` |
| `triage` | 不具合の原因の並行検証と裁定 | `symptom` | `angles`, `researcher_role`, `judge_role` |
| `implement` | 単発の実装とレビューのループ | `requirements` | `implementer_role`, `reviewer_role`, `max_rounds`, `branch`, `base` |
| `spike` | 別方針の並行実装と選択 | `requirements` | `approaches`, `criteria`, `implementer_role`, `judge_role`, `base` |
| `refine` | 草稿の批評と改稿のループ | `file`, `goal` | `max_rounds`, `writer_role`, `critic_role` |

表と実際の引数が食い違ったら、`mad-run <recipe> --dry-run` の出力が正である。

## write 役を含むレシピ

`implement` と `spike` は worktree を作り、その中で実装させてコミットさせる。
`refine` は cwd の中で対象ファイルを書き換える。

- `implement` と `spike` を呼ぶ前に、作業ツリーと index が clean であることを確かめる。
  実装は別の worktree で行うが、`base` は呼んだ場所の現在のブランチになる
- HEAD が detached だと `implement` と `spike` は 2 で終わる。`paseo` は
  `--base HEAD` を受け付けない
- run が終わっても worktree とブランチは残る。取り込みは利用者が行い、
  片付けは `mad-runs clean` で行う
- `refine` は worktree を作らない。対象が `_cellfusion/` の草稿になることが多く、
  `_cellfusion/` は git 追跡外なので branch-off で作った worktree には現れない
- write 役が worktree の外に書かない保証は、役割のプロンプトの指示だけである。
  `mad-route` は `manifests.json` の `access` を provider の mode に対応させるが、
  claude の `write` が対応する `bypassPermissions` は許可の確認を出さないモードであり、
  書き込めるパスの制限ではない。仕事のリポジトリで使うかどうかは利用者が判断する
- `refine` は対象ファイルの控えしか run ディレクトリに残さない。writer が同じ
  ディレクトリの別のファイルを書き換えた場合、`_cellfusion/` は git 追跡外なので
  復元できない。`refine` を呼ぶ前に対象ディレクトリを退避する

## 役割と provider

役割から provider を決めるのは `mad-route` である。`~/.agents/agent-defs/paseo-routing.json`
が役割ごとの候補の優先順を持ち、使えない provider があれば次の候補を使う。仕事先のリポジトリで
別アカウントの provider を使う指定は `paseo-project-routing.json` が持ち、git の remote か
リポジトリのパスで引く。

どの provider が選ばれたかは `mad-run <recipe> --dry-run` で確かめられる。

## はまらないとき

どのレシピの形にもはまらないなら MAD を使わない。従来どおり subagent を立てる。

## 例

```bash
MAD=~/.agents/skills/multi-agent-development/scripts/mad-run
"$MAD" research --arg 'topic=どの方式で生死を判定するか'
"$MAD" decide --arg 'problem=run store の置き場所をどこにするか'
"$MAD" fanout --arg 'items=["a.ts","b.ts","c.ts"]' --arg 'task=型定義を洗い出す'
"$MAD" implement --arg 'requirements=_cellfusion/plans/x.md'
"$MAD" triage --arg 'symptom=テストが CI でだけ落ちる'
```

{{ includeTemplate "agent-skills/_mad-invocation.md" . }}
