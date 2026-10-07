# リサーチを保存・参照する

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

## 配布と適用

本体は `.chezmoitemplates/agent-skills/research/SKILL.md` にあり、既存の共有テンプレート方式で次へ配布する。

- `~/.agents/skills/research/SKILL.md`
- `~/.config/claude/skills/research/SKILL.md`

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
