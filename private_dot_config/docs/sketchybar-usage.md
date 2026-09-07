# SketchyBar の Claude 使用量を launchd で採取する

SketchyBar の usage ウィジェットは、AI 環境ごとに Claude と Codex の使用率を出す。
週次（7 日）の使用率に加えて、5 時間制限の使用率も出す。
Claude の値は `~/.cache/sketchybar-usage/<環境名>-claude.json` から読む。
このキャッシュを書くのが launchd ジョブの `com.cellfusion.sketchybar-usage-claude` である。

## 何が起きていたか

以前は Claude Code の `statusLine` に指定した `~/.config/claude/statusline.sh` が、
表示のたびに週次の `rate_limits` をキャッシュへ書いていた。
Paseo はエージェントを `--output-format stream-json` の非対話モードで起動する。
`statusLine` は対話 UI の描画時にしか実行されないため、Paseo に移ってから
キャッシュが更新されなくなった。`usage.sh` は 30 分より古いキャッシュを `stale`
として灰色で描くので、使用率が移行前の値で固定される。

`statusline.sh` の書き出しは削除した。launchd ジョブがキャッシュを書く唯一の経路である。
herdr の外で対話セッションを起動すると `AGENT_ENV_SESSION` が先頭環境のままになり、
別の環境の枠へ書く余地があったため、書き手を 1 つに寄せた。

非対話モードで使用量を得る経路を次のとおり調べた。

- フックの標準入力に渡る JSON は、`session_id` や `transcript_path` を持つが
  rate limit を持たない。
- 会話の記録ファイルにも、設定ディレクトリ配下のどのファイルにも、
  使用量は保存されない。
- Paseo も rate limit のイベントをディスクへ残さない。
- `claude -p /usage` は、`/usage` を Claude Code の中で処理して使用量を文字列で返す。
  モデルへのリクエストを出さないので、トークンを消費しない。実測では
  `num_turns` が 0、`total_cost_usd` が 0、所要時間が 0.8 秒である。

`--output-format stream-json --verbose` の出力にも `rate_limit_event` が流れるが、
こちらはモデルへのリクエストを 1 回出す。実測で 1 回あたり 15,000 トークン、
$0.03 かかるため、定期実行の経路としては選んでいない。

## 採取の仕組み

`~/.config/sketchybar/helpers/usage_collect_claude.sh` が採取する。
環境ごとに `CLAUDE_CONFIG_DIR` を切り替えて、次の 3 段を行う。

1. `claude -p /usage` を実行して使用量の文字列を受け取る。
   セッションの保存、MCP サーバー、フックはどれも起動しない指定で呼ぶ。
2. `Current week (all models): 2% used · resets Sep 3 at 7pm (Asia/Tokyo)` の行から、
   週次の使用率とリセット時刻を取り出す。`Current session: 19% used · resets Sep 7 at
   1:20am (Asia/Tokyo)` の行からは、5 時間制限の使用率とリセット時刻を取り出す。
   2 つの行は同じ書式なので、`usage_fields` が両方を扱う。
3. `~/.cache/sketchybar-usage/<環境名>-claude.json` へ
   `{ts, used_pct, resets_at, session_pct, session_resets_at}` を書く。

`Current session:` の行だけが読めなかったときは、週次の値でキャッシュを書き、
`session_pct` と `session_resets_at` のキーを書かない。`session_pct` を持たない
古いキャッシュと同じ形になるため、`provider_claude` が扱う場合分けが 1 つで済む。
週次の行が読めなかったときは、キャッシュを書き換えずに終了ステータス 1 を返す。

Codex の 5 時間制限は採取しない。`usage.sh` の `provider_codex` が、session の
ログの `rate_limits` から `window_minutes` が 10080 未満の窓のうち最も短いものを
その場で読む。

環境名は chezmoi の `[[data.environments]]` から描画時に埋め込む。実行時の
`AGENT_ENV_SESSION` を見ないので、Paseo が provider ごとに設定ディレクトリの変数を
差し替える起動経路でも、環境と値の対応が崩れない。

実行に失敗した環境のキャッシュは書き換えない。前の値が残るため、ウィジェットは
30 分後に `stale` へ落ちる。失敗した環境があると、終了ステータスが 1 になる。

launchd ジョブは 900 秒ごとに実行する。

### リセット時刻の解釈

`/usage` の出力には年が無く、分がちょうどのときは分も省かれる（`7pm`）。
`epoch_of` が次のとおり補って epoch 秒にする。

- 分が無ければ `:00` を足し、`%b %e %I:%M%p %Y` の 1 つの書式で読む。
  `date -j` は書式に無い項目を実行時刻で埋めるため、書式を推測で試すと
  分が実行時刻の分になる。
- 秒は書式に入れられないので、epoch を 60 秒単位へ丸めて落とす。
- 年は今年として解釈する。週次のリセットは常に 7 日以内の未来にあるため、
  1 日より過去になったときだけ翌年として解釈し直す。

## 有効にする

`chezmoi apply` は plist を置くだけである。次のログインで読み込まれる。
すぐ有効にするなら次を実行する。

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cellfusion.sketchybar-usage-claude.plist
```

## 確認する

手で 1 回実行して、キャッシュが更新されるかを見る。

```sh
~/.config/sketchybar/helpers/usage_collect_claude.sh
~/.config/sketchybar/helpers/usage.sh
```

`usage.sh` の出力は環境ごとに 9 項目のタブ区切りになる。順に
`<ラベル>`、`claude` か `codex`、週次の使用率、週次のリセット時刻、
`ok` か `stale` か `error` の status、週次の severity、5 時間の使用率、
5 時間のリセット時刻、5 時間の severity である。値が無い項目は `-` になる。
`stale` が出るなら採取が失敗している。launchd ジョブの記録は
`~/Library/Logs/sketchybar-usage-claude.err.log` にある。

## 色の決め方

severity は `crit` が赤、`warn` が黄、`ok` が緑、`none` が灰である。

- バーのラベル（`14%`）と popup の右の列は、週次の severity で色を決める。
  判定は `usage.sh` の `pace_of` が行い、経過時間に対して使用率が先行しているかを見る。
- バーのアイコン（Claude と Codex の記号）と popup の左の列は、5 時間の severity で
  色を決める。判定は `usage.sh` の `level_of` が行う。使用率が 80 以上なら `crit`、
  50 以上なら `warn`、それ以外は `ok` である。status が `ok` でないときと、
  使用率が空か非数値のときは `none` になる。

`level_of` は `pace_of` と違い、使用率が 5% 未満でも `none` にしない。5 時間の窓では
使い始めに使用が集中するため、経過時間との比較ではなく使用率そのもので判定する。

5 時間の使用率が取れないときは、アイコンだけが灰になり、ラベルは週次の色を持つ。
`session_pct` を持たない古い Claude のキャッシュと、5 時間の窓を持たない Codex の
ログがこれに当たる。

## 表示の操作

バーの項目（環境ラベル・agent の項目・区切り）のどれをクリックしても、詳細表示の
popup が開閉する。マウスを外しても閉じないので、読んでいる途中で消えることがない。
クリックのたびに `usage.sh` を呼び直すため、開いた直後は前回の値が出て、
そのあと新しい値へ差し替わる。

popup は環境ごとの見出し行と、その下の agent 行で組む。agent 行は左の列に
5 時間制限（使用率と残り時間）、右の列に週次（使用率とリセット日時）を出す。

## いつ消すか

`/usage` の出力の書き方が変わると、`parse_usage` が読めなくなる。ウィジェットは
`stale` へ落ち、`err.log` に「使用量を解釈できなかった」が残る。
Claude Code が非対話モードでも使用量をファイルへ残すようになったら、この仕組みは
不要になる。plist を止めて、`usage_collect_claude.sh`、plist、このドキュメントを
chezmoi のソースから削除する。

`Current session:` の書き方だけが変わったときは、5 時間の値が `-` になり、
バーのアイコンが灰になる。週次の表示はそのまま残る。

```sh
launchctl bootout gui/$(id -u)/com.cellfusion.sketchybar-usage-claude
```
