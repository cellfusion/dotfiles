# シークレットの取り扱い

原則として、トークンを平文でファイルに置かない。1Password から取る。

## 方式の使い分け

| 方式 | いつ使うか | 例 |
|---|---|---|
| shell plugin | 対応 CLI を叩くとき（既定） | `wrangler`, `aws`, `stripe` |
| `op run --env-file` | 複数の環境変数をまとめて注入するとき。plugin 未対応のツール | `op run --env-file=.env -- pnpm dev` |
| `op read` | 単発で 1 つの値が欲しいとき | `curl -H "Authorization: Bearer $(op read op://...)"` |
| `op inject` | テンプレートから設定ファイルを生成するとき | `op inject -i config.tpl -o config.json` |

迷ったら shell plugin を使う。値が環境変数にもファイルにも残らないため、最も漏れにくい。

## shell plugin（既定）

`~/.op/plugins.sh` で `wrangler` / `aws` / `stripe` を設定済みである。CLI を叩くだけで認証が挟まる。

対応 CLI かどうかは `op plugin list` で確認する。ディレクトリ単位の割り当て方法は `cloudflare.md` に書いた。

## op run --env-file

`.env` には参照だけを書き、値は書かない。

```
CLOUDFLARE_API_TOKEN=op://Vault/item/field
DATABASE_URL=op://Vault/item/field
```

```bash
op run --env-file=.env -- pnpm dev
```

この `.env` は参照しか含まないのでコミットできる。ただし vault 名と item 名が公開される点は許容する必要がある。

## op read

シェルの 1 行で値が欲しいときだけ使う。変数に代入せずその場で展開し、シェル履歴とプロセス一覧に値を残さない。

## op inject

生成したファイルには平文の値が入る。`.gitignore` に追加し、使い終わったら削除する。

## やってはいけないこと

- `export CLOUDFLARE_API_TOKEN=<値>` を zshrc や `herdr-sessions/*.zsh` に書く。これらは chezmoi 管理下なので git に入る。
- `.env` に実際の値を書く。
- `wrangler secret put` の値をコマンドライン引数に直書きする。シェル履歴に残る。
- エージェントが `op read` の結果を応答本文に出力する。値がセッションログに残る。
