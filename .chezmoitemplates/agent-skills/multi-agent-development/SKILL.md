---
name: multi-agent-development
description: >-
  親エージェントが Paseo MCP の子エージェントを組み合わせて手動でオーケストレーションするときに使う。
  spec、plan、implement、review、その 4 つを通す delivery と、観点を分けた作業を対象にする。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 親主導の MAD オーケストレーション

MAD は親が Paseo MCP の agent を起動・監視し、フェーズごとに判断して進める。子同士の本文は会話へ集めず、mode 0600 の run 成果物を介して後段へ渡す。Paseo MCP が利用できないときは開始前に停止し、開始済みの create を別経路へ移さない。

## lifecycle

`research`、`decide`、`debate`、`fanout`、`review`、`triage` は独立 child を並列に起動し、親が全 child の state と handoff を確認してから統合役を起動する。`spec`、`plan`、`implement`、`refine` は親が round と approval を管理する。`delivery` は spec、plan、implement、review、final-review を順に進める。各境界で親だけが user decision、retry、停止を state に記録する。

すべての child は同じ `paseo-mcp` backend、Paseo provider/model discovery、`mad-attempt-v1` artifact contract を使う。作成、待機、停止、workspace 操作は Paseo MCP の機能だけで行う。child の prompt、result、handoff、state は絶対 path で受け渡し、raw response や秘密情報を親の会話や log に出さない。

## delivery role map

実際に起動する role は `implementer`、`task-reviewer`、`re-reviewer`、`final-reviewer` の 4 つである。role 名、prompt、schema、artifact contract は一致させる。レビュー結果は task 単位、fix 単位、branch 全体の順に対応する role が返す。

## 共通手順

1. `tests/manual/paseo-unit-gate.sh require unit2-decision.txt continue` を通し、親が必要な run directory と state を用意する。
2. 配布された `mad-contract.js` で resolved export と provider enumeration を mode 0600 で作る。
3. `paseo-mcp-adapter` の `list-providers`、available provider ごとの `list-models`、snapshot、`generate-paseo-config resolve` の順に実行する。
4. launch を検証して request を作り、mode 0600 の `mcp-create.json` として書く。`assertMadCreateRequestV1` で再検証し、`manual-orchestration-validate --prepare-create` で一回性 marker を取ってから、その 6 key をそのまま `mcp__paseo__create_agent` へ渡して一回だけ create する。marker を取れなければ create しない。adapter に create の経路は無い。
5. accepted response を `{"status":"accepted","childRef":"<safe-id>"}` へ縮約して 0600 の state に保存し、`wait-agent --child-ref <safe-id> --timeout <seconds>` を一回だけ呼んで、縮約済み status だけを 0600 の `wait-evidence.json` と call log に記録する。
6. 各 child の state、result、handoff を検証し、親が採用判断を記録する。

詳細な request、failure、state、role、plan の契約は共通文書を参照する。

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
