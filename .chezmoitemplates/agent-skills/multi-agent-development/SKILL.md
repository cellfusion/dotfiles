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

`research`、`decide`、`debate`、`fanout`、`review`、`triage` は独立 child を並列に起動し、親が全 child の state と handoff を確認してから統合役を起動する。`spec`、`plan`、`implement`、`refine` は親が round と approval を管理する。`delivery` は spec、plan、implement、review、final-review を順に進める。各境界で親だけが user decision、retry、停止を state に記録する。task の review/fix は `--prepare-review` を通す bounded loop（round `0` の初回 review、round `1` から `3` の fix と re-review）であり、admission なしの再実行や hotfix node の追加をしない。

すべての child は同じ `paseo-mcp` backend、Paseo provider/model discovery、`mad-attempt-v1` artifact contract を使う。作成、待機、停止、workspace 操作は Paseo MCP の機能だけで行う。child の prompt、result、handoff、state は絶対 path で受け渡し、raw response や秘密情報を親の会話や log に出さない。

## 実行path

配布済みのscriptは`~/.agents/skills/multi-agent-development/scripts`にあるため、`PATH`や`~/.local/bin`に依存しない。MAD開始時に次を設定し、`AGENT_CONFIG`は未設定ならchezmoiの正本へfallbackする。

```bash
MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"
MAD_SHARE="${MAD_SHARE:-$HOME/.local/share/agent-config}"
AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"
MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter"
MAD_VALIDATE="$MAD_SCRIPTS/manual-orchestration-validate"
MAD_PLAN_VALIDATE="$MAD_SCRIPTS/paseo-plan-dependency-validate"
MAD_GENERATOR="${MAD_GENERATOR:-$HOME/.local/bin/agent-config}"
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"
PASEO_UNIT_GATE="${PASEO_UNIT_GATE:-$PROJECT_ROOT/tests/manual/paseo-unit-gate.sh}"
```

`tests/manual/paseo-unit-gate.sh` はこの repository の checkout 専用である。`PASEO_UNIT_GATE`が実在する場合だけ使い、別repositoryで存在しなければそのmigration gateを実行しない。

## delivery role map

実際に起動する role は `implementer`、`task-reviewer`、`re-reviewer`、`final-reviewer` の 4 つである。role 名、prompt、schema、artifact contract は一致させる。レビュー結果は task 単位、fix 単位、branch 全体の順に対応する role が返す。

## 共通手順

1. `PASEO_UNIT_GATE`が実在するこのrepositoryだけ、`bash "$PASEO_UNIT_GATE" require unit2-decision.txt continue` を通し、親が必要な run directory と state を用意する。別repositoryでは固有のgateを使う。
2. 配布された `mad-contract.js` で resolved export と provider enumeration を mode 0600 で作る。
3. `"$MAD_ADAPTER"` の `list-providers`、available provider ごとの `list-models`、snapshot、`agent-config resolve` の順に実行する。
4. launch を検証して request を作り、mode 0600 の `mcp-create.json` として書く。`assertMadCreateRequestV1` で再検証し、`"$MAD_VALIDATE" --prepare-create` で一回性 marker を取ってから、その 6 key をそのまま `mcp__paseo__create_agent` へ渡して一回だけ create する。marker を取れなければ create しない。adapter に create の経路は無い。
5. accepted response を `{"status":"accepted","childRef":"<safe-id>"}` へ縮約して 0600 の state に保存し、`"$MAD_ADAPTER" wait-agent --child-ref <safe-id> --timeout <seconds>` を一回だけ呼んで、縮約済み status だけを 0600 の `wait-evidence.json` と call log に記録する。
6. 各 child の state、result、handoff を検証し、親が採用判断を記録する。

review/fix の scope 外で見つけた重要事項は、同じ loop を延長せず observations に保持して最終 gate で一度だけ user decision を求める。scope 拡張は新しい run で行う。

詳細な request、failure、state、role、plan の契約は共通文書を参照する。

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
