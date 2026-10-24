# 調査と設計判断を保存・参照する

`research` スキルは、作業ディレクトリに依存せず調査結果を `~/docs/research` に Markdown で保存する。保存済みの調査を探すだけの依頼では、ファイルを変更しない。

## 使い方

エージェントに次のように依頼する。

- 「research を使って ripgrep の固定文字列検索を調べて保存して」
- 「research を使って保存済みの ripgrep の調査を探して」

調査時は既存ノートを検索し、同じ問いなら再利用または更新する。結果には調査日と出典を残し、保存先の絶対パスを返す。index は作らず、既存の `~/notes` は移動しない。

手動で検索する場合:

```bash
rg -n -i -F -e '検索語' -g '*.md' -- "$HOME/docs/research"
```

`-F` は検索語を正規表現として解釈しない指定。終了コード 1 は一致なし、2 はエラー。重複確認ではエラーを「ノートなし」と扱わない。`-q` は一致があるとエラーでも 0 になることがあるため、この確認には使わない。

## プロジェクトの設計判断をADRに残す

`architecture-decision-records` スキルは、後から変更理由を確認する必要がある重要な判断を、プロジェクト内のADR（Architecture Decision Record）に残す。調査結果や作業計画を丸ごと移すものではない。

| 文書 | 保存する内容 | 保存先 |
| --- | --- | --- |
| 調査原本 | 問い、出典、知見と限界 | `~/docs/research` |
| spec・実装計画 | 要件、作業順序、受け入れ条件 | 各スキルの既存の外部保存先 |
| ADR | 判断の背景・制約、決定と理由、実際の代替案、正負の影響 | 対象プロジェクト内 |
| レビュー証拠・監査ログ | 検証結果、固定資料、実行記録 | 各スキルの既存の外部保存先 |

既存のADR保存先・命名・言語・書式を優先する。未導入なら `docs/adr/NNNN-short-title.md` を使う。既存資料の移動や過去判断の一括生成はしない。ADRは外部の会話やローカルの計画ファイルを読めなくても理解できる本文にする。

依頼例:

- 「既存ADRを確認して、この永続化方式の変更案を検討して」
- 「この判断をプロジェクト内のADR草案として残して。まだ未承認」
- 「承認した設計判断をADRに記録して」
- 「このADRを置き換える案を作り、承認前は旧判断を有効なままにして」

永続データ、公開API、セキュリティ境界、主要技術、重要な非機能トレードオフが主な対象。既存設計に沿う局所修正や機械的変更には不要。調査・計画だけの依頼から、勝手にプロジェクト内ファイルを作らない。

独自の状態表記があるプロジェクトでは、その表記を尊重する。既定の状態は次のとおり。

| 状態 | 意味・記録条件 |
| --- | --- |
| `Proposed` | 未決の提案 |
| `Accepted` | 既存の権限ルールに沿って承認された判断。決定日と承認根拠を残す |
| `Superseded` | 承認済みの後継判断に置き換えられた旧ADR |
| `Rejected` | 正式に却下された提案。理由とともに保持する |

同じ判断の明示承認を重ねて求めず、実装完了だけを承認とみなさない。`Accepted` は実装済み・マージ済みを意味しない。判断を変更するときは新ADRを作り、後継の承認前は旧判断を有効なままにする。承認後に状態と相互リンクを更新し、以前の判断内容を保持する。

設計・計画・実行・委任・レビューの各スキルから共通ADRスキルを参照する。子は判断候補を返し、採番・承認反映・置換は親が所有する。限定レビューには、差分に出ない関連ADRも含めて、固定した本文と、各ADRの出典・状態を示す対応表を渡す。未コミット草案はコミット版と区別し、cwd制限によるコピー先にも資料と読取許可パスを揃える。

## 配布と適用

本体は `.chezmoitemplates/agent-skills/research/SKILL.md` にあり、既存の共有テンプレート方式で次へ配布する。

- `~/.agents/skills/research/SKILL.md`
- `~/.config/claude/skills/research/SKILL.md`

ADRスキルの本体は `.chezmoitemplates/agent-skills/architecture-decision-records/`。次の両経路へ `SKILL.md` と `references/adr-template.md` を配布する。

- `~/.agents/skills/architecture-decision-records/`
- `~/.config/claude/skills/architecture-decision-records/`

`brainstorming`、`design-checkpoint-review`、`writing-plans`、`executing-plans`、`multi-agent-development`、`requesting-code-review` の共通テンプレートから接続する。これらの編集はchezmoiのソースで行い、展開済みファイルを直接変更しない。

スキルの自動選択はエージェント側の発見方式に依存する。スキル名の指定だけでは、配布先を見ていない起動には届かない。

Claude Code は、このリポジトリの環境切替を使って起動するか、配布先に合わせて明示する。

```bash
CLAUDE_CONFIG_DIR="$HOME/.config/claude" claude
```

`CLAUDE_CONFIG_DIR` がない素の起動は既定の `~/.claude` を見る。認証も設定ディレクトリごとに異なるため、対象環境の認証が期限切れなら、その環境でログインを更新する。スキル側で認証情報をコピーしない。

別の認証済み Claude 環境を使い続ける場合は、設定ディレクトリを切り替えず、依頼に `~/.config/claude/skills/research/SKILL.md` の絶対パスを含めて明示的に読ませる。非対話の参照検証では、そのスキルディレクトリと `~/docs/research` への読取権限も与える。

Codex の非対話実行で調査を保存する場合は、通常の sandbox を維持したまま保存先を許可する。参照だけなら `read-only` でよい。

```bash
codex exec --skip-git-repo-check -s workspace-write \
  --add-dir "$HOME/docs/research" \
  'research を使って調査して保存して'
```

`~/notes` には同名のローカルスキルが残っているため、そこで使う場合は共有スキルの絶対パスも指定し、取り違えを避ける。

worktree の変更は、chezmoi のメインソースに取り込んでから対象の diff を確認する。`chezmoi apply` は明示承認後に対象パスだけへ行う。調査ノート自体は chezmoi の配布対象ではない。スキルは Git の初期化・コミット・push を行わない。
