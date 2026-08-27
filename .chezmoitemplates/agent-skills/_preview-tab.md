## プレビュー

self-review を通したら、承認 gate を出す**前**にファイルを herdr の別タブで開く。開くかどうかはユーザーに聞かない。

`$HERDR_ENV` が `1` のときだけ実行する。未設定ならこの節を丸ごと飛ばし、そのまま承認 gate へ進む。

```bash
ws=$(herdr pane get "$HERDR_PANE_ID" | jq -r '.result.pane.workspace_id')
pane=$(herdr tab create --workspace "$ws" --cwd "$PWD" --focus | jq -r '.result.root_pane.pane_id')
herdr pane run "$pane" '${EDITOR:-nvim} "<ファイルの絶対パス>"; exit'
```

上の `pane get` → `tab create --workspace` → `pane run` の3コマンドは、1つのプレビュー操作として扱う。stderr または tool error を確認し、初回実行が `PermissionDenied`、`Permission denied`、`Operation not permitted` のいずれかで失敗した場合だけ、Herdr の session socket が sandbox 外にある可能性があるため `[retry-outside-sandbox]` で同じプレビューコマンドを 1 回だけ再実行する。`justification` を書く runtime では、そのコマンドを sandbox の外で実行する理由として「Herdr の現在セッションへ接続し、成果物を新規タブで開くため」と書く。

- 再実行の範囲は、初回にどこまで成功したかで変える。`pane` が空または `null` のとき（`pane get` または `tab create` 自体が失敗した）は `ws` と `pane` を取り直し、3コマンドをやり直す。`pane` に非空の値が取れているとき（`herdr pane run` だけが失敗した）は、その `ws` と `pane` をそのまま使い `herdr pane run` だけを再実行する。`tab create` をやり直すとタブが2つ作られ、1つ目に `; exit` が走らないまま孤立する
- sandbox 外の再実行も失敗した場合、または permission denied 以外で失敗した場合は再試行せず、プレビュー失敗を 1 行で伝えて承認 gate へ進む

- **`--workspace` を必ず付ける。** 省くとユーザーがフォーカスしている workspace にタブが作られ、自分が動いている workspace とは別の場所に開くことがある。workspace ID は `$HERDR_PANE_ID` から `herdr pane get` で引き、`--workspace` に渡す
- エディタは `$EDITOR` を使う。未設定なら `nvim` に落とす。`herdr pane run` に渡す文字列は**シングルクォートで囲み**、`${EDITOR:-nvim}` を pane 側の shell に展開させる。ダブルクォートで囲むと自分の側で展開してしまう
- **末尾の `; exit` を省かない。** これが無いとエディタを終了しても shell が残り、空の pane がタブに残り続ける
- `--focus` を付けてユーザーの視線をプレビュータブへ移す
- パスは絶対パスで渡し、ダブルクォートで囲む
- `herdr tab create` が permission denied 以外で失敗したら（`pane` が空か `null`）、その旨を 1 行で伝えてプレビューなしで承認 gate へ進む。失敗を理由に作業を止めない

タブはユーザーがエディタを終了した時点で閉じる。`; exit` によって、エディタが終わると pane の shell も終わり、pane が消えてタブも消える。**自分から閉じる系のコマンドを呼んではならない。** ユーザーが読んでいる最中や編集中に閉じると入力が失われる。

エディタは編集可で開く。読み取り専用のフラグは付けない。ユーザーはその場で本文を直せる。そのため、**承認 gate の応答を受け取ったら、issue 化・次スキルへの引き継ぎのどれを行う前にも必ずファイルを読み直す。** 自分が書いた内容ではなく、読み直した内容が正となる。読み直して自分の認識と食い違っていたら、その差分を 1-2 行で報告してから続行する。
