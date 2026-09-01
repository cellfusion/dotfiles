# Paseo の Claude 履歴を symlink で見せる

Paseo で 2 つ目以降の AI 環境の provider を使うと、daemon の再起動後に会話履歴が
UI から消える。`~/.local/bin/paseo-link-claude-history` が、daemon から見える
ディレクトリへ symlink を張って履歴を読めるようにする。

## 何が起きているか

`run_onchange_after_90-agent-envs.sh` は、2 つ目以降の環境について
`~/.paseo/config.json` に `claude-<環境名>` という provider を書く。この provider は
`env.CLAUDE_CONFIG_DIR` に `$XDG_CONFIG_HOME/claude_<環境名>` を持つ。
CLI を起動するときはこの値が使われるので、会話は
`$XDG_CONFIG_HOME/claude_<環境名>/projects/<cwd から作った名前>/<sessionId>.jsonl`
に残る。先頭環境は suffix の無い `$XDG_CONFIG_HOME/claude` を使う。

一方、UI に出す履歴を組み立てる処理は daemon 自身の `CLAUDE_CONFIG_DIR` を見る。
`app.asar` 内の
`@getpaseo/server/dist/server/server/agent/providers/claude/agent.js` の
`resolveHistoryPath` が該当箇所で、provider の `env` を参照していない。

```js
const configDir = process.env.CLAUDE_CONFIG_DIR ?? path.join(os.homedir(), ".claude");
```

呼び出し元の `loadPersistedHistory` は、ファイルが無ければ例外も出さずに戻る。
そのため daemon が入れ替わると、履歴だけが黙って空になる。
CLI は `--resume` で復帰するので、履歴が消えた画面でも会話は続けられる。

upstream の報告は [getpaseo/paseo#2005](https://github.com/getpaseo/paseo/issues/2005)
である。`bug` / `p2` / `triaged` が付いて open のままで、
修正の PR は [#3155](https://github.com/getpaseo/paseo/pull/3155) と
[#3378](https://github.com/getpaseo/paseo/pull/3378) がどちらも open である。
Paseo 0.7.0 で再現することを確認した。

デスクトップアプリでは `agent.js` を直接書き換えられない。
`Info.plist` の `ElectronAsarIntegrity` が `app.asar` の SHA256 を持っており、
書き換えると整合性の検査に落ちる。

## スクリプトの動き

1. `~/.paseo/config.json` を読み、`claude` を `extends` する provider ごとの
   `CLAUDE_CONFIG_DIR` を集める。
2. `~/.paseo/agents/<プロジェクト>/<agentId>.json` から `provider`、`cwd`、
   `persistence.sessionId` を読む。
3. `cwd` からディレクトリ名を作る。英数字以外を `-` に置き換え、200 文字を超えたら
   切って hash を付ける。Paseo 側の `claudeProjectDirSync` と同じ規則である。
4. provider 側の `.jsonl` へ、daemon 側の同じ名前のパスから symlink を張る。
   subagent の履歴が入るディレクトリが並んでいれば、それも張る。

## 使い方

```sh
paseo-link-claude-history                     # 足りない symlink を張る
paseo-link-claude-history --dry-run           # 張らずに結果だけ出す
paseo-link-claude-history --prune             # 参照先が消えた symlink を削除する
paseo-link-claude-history --remove            # 張った symlink を全部削除する
```

`--daemon-config-dir` で daemon 側のディレクトリを指定できる。既定は
`$XDG_CONFIG_HOME/claude` で、`XDG_CONFIG_HOME` が無ければ `~/.config/claude` になる。

## 定期実行

`~/Library/LaunchAgents/com.cellfusion.paseo-link-claude-history.plist` が
5 分ごとに `--quiet --prune` で実行する。ログは
`~/Library/Logs/paseo-link-claude-history.log` に出る。
`--quiet` を付けているので、symlink を張ったときと問題があったときだけ書かれる。

`chezmoi apply` は plist を置くだけである。次のログインで読み込まれる。
すぐ有効にするなら次を実行する。

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cellfusion.paseo-link-claude-history.plist
```

## 前提と副作用

daemon の `CLAUDE_CONFIG_DIR` が先頭環境の `$XDG_CONFIG_HOME/claude` であることを
前提にしている。値は Paseo を起動した環境から受け継ぐので、2 つ目以降の環境の
pane からアプリを起動すると suffix の付いたディレクトリになり、前提が崩れる。
その場合は `--daemon-config-dir` で合わせる。

`$XDG_CONFIG_HOME/claude/projects/` に symlink が増えるため、先頭環境の端末で
`claude --resume` を実行したときのセッション一覧に、他の環境のセッションが混ざる。

## いつ消すか

upstream の修正が入った Paseo に上げたら、この仕組みは不要になる。
plist を止めて symlink を消す。

```sh
launchctl bootout gui/$(id -u)/com.cellfusion.paseo-link-claude-history
paseo-link-claude-history --remove
```

そのうえで `~/.local/bin/paseo-link-claude-history`、plist、このドキュメントを
chezmoi のソースから削除する。
