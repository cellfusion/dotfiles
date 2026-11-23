# Rex で使えるエージェントの役割

役割は Rex や hc の設定ではなく、chezmoi の `.chezmoitemplates/agent-skills/role-*/SKILL.md` で管理します。
chezmoi で対象のスキルを配置した後、Rex で起動したエージェントの中から呼び出せます。呼び出し自体は新しいタブや worktree を作りません。

| エージェント | 呼び出し例 | 配置先 |
|---|---|---|
| OMP | `/skill:role-review この差分を読み取り専用でレビューして` | `~/.agents/skills/` |
| Pi | `/skill:role-review この差分を読み取り専用でレビューして` | `~/.agents/skills/` |
| Claude Code | `/role-review この差分を読み取り専用でレビューして` | `~/.config/claude/skills/`（この構成の `CLAUDE_CONFIG_DIR` 配下） |
| Codex | `$role-review この差分を読み取り専用でレビューして` | `~/.agents/skills/` |

`role-` は、同名の組み込みコマンドや用途が異なる既存スキルとの衝突を避けるための接頭辞です。

| スキル | 用途 |
|---|---|
| `role-review` | 差分や PR を読み取りレビュー。投稿・承認はしない |
| `role-security-review` | 信頼境界や認可などのリスクを読み取りレビュー |
| `role-plan-auditor` | 計画の要件・依存関係・検証・承認を監査 |
| `role-implement` | 指定範囲を実装し、担当する利用経路を確認 |
| `role-debug` | 症状を切り分け、修正を依頼された場合だけ変更 |
| `role-research` | コード・仕様・運用を調査して報告。Vault への保存は前提にしない |
| `role-question` | 読み取り・検索ツールで質問に回答 |
| `role-ui` | UI を改善し、可能なら実画面で操作を確認 |

スキルの「読み取り専用」は作業上の指示であり、ツールや OS の権限制限ではありません。
特に `role-question` を明示的に呼んでも、実行中のエージェントからシェルツールが消えるわけではありません。

## Rex で別のエージェントを起動する

新しいセッションで使うエージェントは `~/.agents/AGENTS.md` の **Agent Selection** に従って選びます。端末操作には `rex` スキルを参照し、起動後に必要な `role-*` スキルを呼び出します。

旧 hc テンプレートは配布しません。OMP 内で作業を分担するだけなら、新しい Rex タブを開かず `task` を使います。

`pr-review` は別経路です。SHA を固定した PR レビュー、隔離 checkout、確認範囲を記録した成果物が
必要なときに使います。現在の差分をさっと見たいときは `role-review` で十分です。
