# Cloudflare のマルチアカウント運用

複数の Cloudflare アカウントを使い分けている。切り替えは 2 つのレイヤーで行う。

| レイヤー | 決めること | 設定の単位 |
|---|---|---|
| 1Password shell plugin | どの API トークンで認証するか | プロジェクトディレクトリ |
| `CLOUDFLARE_ACCOUNT_ID` | どのアカウントを操作するか | herdr セッション |

両方が揃って初めて意図したアカウントに繋がる。片方だけ切り替えると、トークンとアカウント ID が食い違って `wrangler` が認証エラーを返す。

## 1. 認証（1Password shell plugin）

`~/.op/plugins.sh` で `wrangler` は `op plugin run -- wrangler` にエイリアスされている。トークンを環境変数に置かず、コマンドを実行するたびに 1Password から取る。

プロジェクトごとに使うトークンを割り当てる。

```bash
cd <プロジェクトのルート>
op plugin init wrangler
# 「Use automatically when in this directory or subdirectories」を選ぶ
```

これでそのディレクトリと配下では該当アカウントのトークンが自動で使われる。

- 割り当て済みの item は `~/.op/plugins/used_items/wrangler.json` に記録される。
- `op plugin inspect wrangler` と `op plugin clear wrangler` は対話 IO を要求するため、エージェントの Bash ツールからは実行できない。ユーザーに `! op plugin inspect wrangler` の実行を依頼する。

## 2. 対象アカウント（AI 環境）

`CLOUDFLARE_ACCOUNT_ID` と `WRANGLER_HOME` を AI 環境（`$HERDR_SESSION`）単位で
切り替える。定義は `~/.config/chezmoi/private-data.toml` の `[[data.environments]]` に
あり、配列の先頭が primary である。

| 環境 | CLOUDFLARE_ACCOUNT_ID の出どころ | WRANGLER_HOME |
|---|---|---|
| 先頭（primary） | `[[data.environments]]` 1 つ目の `cloudflareAccountId` | `~/.config/.wrangler` |
| 2 つ目以降 | それぞれの `cloudflareAccountId` | `~/.config/.wrangler-<session>` |

`WRANGLER_HOME` を分けているのは、wrangler のログイン状態やキャッシュがアカウント間で
混ざらないようにするためである。

配布されたファイルは `~/.config/zsh/agent-environments.zsh` にある。その元は chezmoi
ソースの `private_dot_config/zsh/agent-environments.zsh.tmpl` で、アカウント ID も
環境名もテンプレートには直書きせず `private-data.toml` から埋める。環境の追加手順は
`herdr.md` を読む。

## 新しいアカウントを足す

1. 1Password に API トークンの item を作る。
2. そのアカウントで使うプロジェクトディレクトリに移動し、`op plugin init wrangler` を実行する。
3. `~/.config/chezmoi/private-data.toml` の対象の `[[data.environments]]` ブロックに
   `cloudflareAccountId` を書く。新しい環境ごと足すならブロックを 1 つ増やす。
   ここはリポジトリの外なので、ID も環境名もリポジトリに入らない。
4. `chezmoi init` を実行して `chezmoi.toml` を再生成する。
5. `chezmoi apply` はユーザーが実行する。

## デプロイ前の確認

```bash
echo $CLOUDFLARE_ACCOUNT_ID
wrangler whoami
```

`wrangler whoami` は 1Password の認証（Touch ID）を要求する。エージェントの Bash ツールから実行すると生体認証のプロンプトで止まるため、ユーザーに `!` 付きで実行してもらう。
