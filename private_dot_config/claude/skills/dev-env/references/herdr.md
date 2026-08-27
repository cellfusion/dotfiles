# herdr セッション別の環境変数

herdr は全ペインの環境に `$HERDR_SESSION` を注入する。zsh はその値を見てセッション固有の環境変数を読み込む。

## 読み込みの順序

`~/.config/zsh/.zshrc` に以下がある。

```zsh
[[ -r "$XDG_CONFIG_HOME/zsh/agent-environments.zsh" ]] && source "$XDG_CONFIG_HOME/zsh/agent-environments.zsh"
```

`agent-environments.zsh` は chezmoi が生成する 1 ファイルで、全環境の定義を持つ。
`$HERDR_SESSION` に一致する環境を適用し、一致しなければ先頭環境（primary）へ落とす。
herdr の外（`$HERDR_SESSION` 未設定）も先頭環境になる。どちらの場合も警告は出ない。

## 環境の定義

定義は `~/.config/chezmoi/private-data.toml` の `[[data.environments]]` にある。
リポジトリの外なので、環境名も Cloudflare のアカウント ID も git に入らない。

```toml
[[data.environments]]
    session = "default"
    label   = "P1"
    agents  = ["claude", "codex"]
    cloudflareAccountId = "..."
```

| フィールド | 意味 |
|---|---|
| `session` | `HERDR_SESSION` の値。ディレクトリ名のサフィックスにもなる |
| `label` | sketchybar の使用率ウィジェットに出る表示名 |
| `agents` | `"claude"` / `"codex"` の部分集合 |
| `cloudflareAccountId` | `CLOUDFLARE_ACCOUNT_ID` の値。省略すると export しない |

**配列の先頭が primary** で、primary だけがサフィックスの無いディレクトリを使う。

| 環境 | Claude | Codex | Wrangler |
|---|---|---|---|
| 先頭 | `~/.config/claude` | `~/.config/codex` | `~/.config/.wrangler` |
| 2 つ目以降 | `~/.config/claude_<session>` | `~/.config/codex_<session>` | `~/.config/.wrangler-<session>` |

切り替えている変数は `CLAUDE_CONFIG_DIR`、`CODEX_HOME`、`WRANGLER_HOME`、
`CLOUDFLARE_ACCOUNT_ID` と、解決結果を伝える `AGENT_ENV_SESSION` / `AGENT_ENV_AGENTS`
である。

`agents` に無いツールは、変数を持たないうえに同名の zsh 関数で覆われる。実行すると
警告を出して非ゼロで終わり、primary にもツール既定にも落ちない。

## 環境を追加する

1. `~/.config/chezmoi/private-data.toml` に `[[data.environments]]` を 1 ブロック足す。
2. `chezmoi init` を実行して `chezmoi.toml` を再生成する。
3. `chezmoi apply` はユーザーが実行する。2 つ目以降の AI 環境ディレクトリは
   `run_onchange_after_90-agent-envs.sh` が作る。
4. 反映には新しいシェルが必要である。起動済みのペインには効かない。

## 旧 claude_secondary / codex_secondary からの移行

2 つ目の環境は以前 `~/.config/claude_secondary` と `~/.config/codex_secondary` という
固定名のスロットだった。`[[data.environments]]` で名前を付けると、ディレクトリ名は
`~/.config/claude_<session>` に変わる。**apply の前に中身を移す。**

```sh
mv ~/.config/claude_secondary ~/.config/claude_<session>
mv ~/.config/codex_secondary  ~/.config/codex_<session>
```

移さずに apply すると、新しい名前のディレクトリが空で作り直され、旧スロットに残った
認証情報（claude の `.claude.json`、codex の `auth.json`）と履歴（claude の
`projects/` `todos/` `history.jsonl`、codex の `sessions/`）は旧スロットに取り残される。
`.chezmoiremove` が消すのは chezmoi が配った symlink（`agents` / `commands` / `skills` /
`hooks` / `CLAUDE.md` / `settings.json` / `AGENTS.md`）だけなので、移し忘れても
ランタイム状態は失われない。

移した後、`chezmoi diff` または `chezmoi apply --dry-run --verbose` で削除対象を
確かめてから apply する。

## 注意

- ここに書けるのは公開してよい値だけである。chezmoi 管理下なので git に入り、リポジトリは public である。環境を特定する値（環境名、Cloudflare のアカウント ID など）は `~/.config/chezmoi/private-data.toml` の `[[data.environments]]` に置き、テンプレートからはループ変数として参照する。API トークンはどちらにも置かない（`secrets.md` を読む）。
- `claude -p` や `claude --resume` で起動した場合も `$HERDR_SESSION` は継承される。
- alt+c の新規タブランチャ（`~/.config/herdr/launch-claude-tab.sh`）も `agents` を見て、claude を持たない環境ではタブを作らずに終わる。判定は `AGENT_ENV_AGENTS` ではなく `$HERDR_SESSION` から行う。`type = "shell"` のキーコマンドは herdr サーバが detached で起動するため、focus 中の pane ではなくサーバの環境を継承し、サーバの `AGENT_ENV_*` はサーバを起動したシェル（＝先頭環境）の値だからである。
- 現在のセッションは `echo $HERDR_SESSION` で確認する。空なら default だけが読まれている。
