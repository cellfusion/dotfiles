# SketchyBar の Claude 使用量を launchd で採取する

SketchyBar の usage ウィジェットは、AI 環境ごとに Claude と Codex の週次使用率を出す。
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
   使用率とリセット時刻を取り出す。
3. `~/.cache/sketchybar-usage/<環境名>-claude.json` へ `{ts, used_pct, resets_at}` を書く。

環境名は chezmoi の `[[data.environments]]` から描画時に埋め込む。実行時の
`AGENT_ENV_SESSION` を見ないので、Paseo が provider ごとに `CLAUDE_CONFIG_DIR`
だけを差し替える起動経路でも、環境と値の対応が崩れない。

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

`usage.sh` の出力は環境ごとに
`<ラベル><TAB>claude<TAB><使用率><TAB><リセット時刻><TAB>ok<TAB><severity>` になる。
`stale` が出るなら採取が失敗している。launchd ジョブの記録は
`~/Library/Logs/sketchybar-usage-claude.err.log` にある。

## いつ消すか

`/usage` の出力の書き方が変わると、`parse_usage` が読めなくなる。ウィジェットは
`stale` へ落ち、`err.log` に「使用量を解釈できなかった」が残る。
Claude Code が非対話モードでも使用量をファイルへ残すようになったら、この仕組みは
不要になる。plist を止めて、`usage_collect_claude.sh`、plist、このドキュメントを
chezmoi のソースから削除する。

```sh
launchctl bootout gui/$(id -u)/com.cellfusion.sketchybar-usage-claude
```
