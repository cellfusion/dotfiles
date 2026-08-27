# GitHub の承認ゲートと Secure Enclave 鍵

GitHub へ外部反映される操作に Claude Code の承認ゲートを掛け、push 認証とコミット署名を
macOS の Secure Enclave 鍵で行う。秘密鍵は Secure Enclave から出ず、エクスポートできない。

chezmoi ソース側のパスを各節に書いてあるので、変更するときはそこを編集する。

**このファイルが記録である理由。** `~/.ssh/config` と `~/.config/git/config` は chezmoi
管理外で、`chezmoi apply` では入らない。2026-01-22 まで有効だったコミット署名は、
`~/.config/git/config` が何かの拍子に書き直された際に設定を失って止まり、
誰も気付かないまま 2026-03-19 以降のコミットが unsigned になっていた。管理下にあれば
`chezmoi apply` で戻っていた。同じことを繰り返さないために、手で入れる内容をここに全部写す。

## apply 後の手順

`chezmoi apply` が終わった時点で、鍵の生成までは自動で済んでいる。残りは 4 つある。

### 1. 鍵ができていることを確かめる

```bash
sc_auth list-ctk-identities
ls -la ~/.ssh/id_github_auth ~/.ssh/id_github_auth.pub \
       ~/.ssh/id_github_sign ~/.ssh/id_github_sign.pub
```

`github-auth` と `github-sign` の 2 本があり、`Prot` が `none`、`Key Type` が
`p-256-ne` であること。stub file が 4 つあること。

無ければ `.chezmoiscripts/run_onchange_after_80-secure-enclave-keys.sh.tmpl` が
走っていない。`chezmoi apply` をもう一度回す。

### 2. GitHub に公開鍵を 2 つ登録する

apply の最後に公開鍵が表示されている。見失ったら次で出せる。

```bash
echo '--- Authentication Key として登録 ---'; cat ~/.ssh/id_github_auth.pub
echo '--- Signing Key として登録 ---';        cat ~/.ssh/id_github_sign.pub
```

https://github.com/settings/keys で「New SSH key」を 2 回行う。

**Key type の選択を間違えないこと。** Authentication Key と Signing Key は別枠である。
認証鍵を Signing Key として登録すると push が通らず、署名鍵を Authentication Key として
登録すると Verified が付かない。

`gh` CLI では登録できない。トークンに `admin:public_key` と `admin:ssh_signing_key` の
scope が無く、scope を広げると平文トークンの権限が増えてこの構成の目的に反する。

### 3. ssh と git の設定を入れる

下の「ssh の設定」と「git の設定」の全文を、それぞれのファイルに書く。
どちらも chezmoi 管理外なので apply では入らない。

### 4. 動作を確かめる

下の「動作確認」を上から順に実行する。

## 承認ゲート

ソース: `private_dot_config/claude/private_settings.json.tmpl`

`permissions.ask` に次を入れてある。GitHub へ外部反映される操作が対象である。

```json
"ask": [
  "Bash(git push *)",
  "Bash(gh pr create *)",
  "Bash(gh pr merge *)",
  "Bash(gh release create *)",
  "Bash(gh api *)",
  "Bash(gh repo delete *)",
  "Bash(gh issue create:*)"
]
```

`ask` ルールは `bypassPermissions` を含むどのモードでも auto-approve されない。
ランチャーの `--dangerously-skip-permissions` を外さずにゲートが効く。
ルールの評価順は deny、次に ask、次に allow である。より具体的な allow ルールが
同じ呼び出しに一致していても、ask に一致すればプロンプトが出る。

適用先は 2 つある。`~/.config/claude/settings.json` は chezmoi 管理下なので apply で入る。
`~/.claude/settings.json` は管理外なので、`CLAUDE_CONFIG_DIR` を設定しないセッションを
使うなら手で同じ `ask` を入れる。

`Bash(gh api *)` は読み取りの呼び出しにも一致する。`gh api` の書き込みだけを狙う
ルールは `-X POST` と `--method POST` と `-f key=value` の 3 つの形を取りうるため
確実に書けない。広いルールを選んで摩擦を受け入れている。

止められない経路がある。`env` は wrapper の strip 対象に入らないため `env git push` は
一致しない。read（`git clone` と `git fetch`）は対象外である。別 pane で人間が打つ
コマンドは Claude Code を通らない。

## 鍵の作成

ソース: `.chezmoiscripts/run_onchange_after_80-secure-enclave-keys.sh.tmpl`

`chezmoi apply` の最後に走り、無ければ作る。冪等なので何度走らせてもよい。

```bash
sc_auth create-ctk-identity -l github-auth -k p-256-ne -t none
sc_auth create-ctk-identity -l github-sign -k p-256-ne -t none
```

`-ne` は non-exportable を意味する。`-t none` は使用のたびの生体認証を要求しない設定で、
これにより incoming ssh セッションからも使える。母艦へ ssh して作業する運用では
これが必須になる。Touch ID を要求する `-t bio` にすると、外出先から署名も push も
できなくなる。

stub file は `ssh-keygen -K -w /usr/lib/ssh-keychain.dylib` で書き出す。書き出す
ファイル名は選べず、カレントディレクトリに `id_ecdsa_sk_rk` として置かれる。この
名前は鍵の SSH application から決まるが、Secure Enclave の identity はどれも
application が `ssh:` なので、identity が 2 つ以上あると必ず同じ名前に衝突する。
2 本目以降で `id_ecdsa_sk_rk already exists. Overwrite (y/n)?` を聞かれ、断ると
ssh-keygen は exit 255 で終わる。

そのためスクリプトは identity の本数だけ `ssh-keygen -K` を回す。k 回目の実行では
最初の k-1 回の Overwrite に `y` と答え、残りを空行で断ることで、k 本目の鍵だけを
その実行の一時ディレクトリに残す。最後に fingerprint で label と突き合わせて
`~/.ssh/` へ改名する。断った実行は必ず失敗で終わるため、成否は exit status では
なく書き出されたファイルの有無で判定している。

回答の経路が 2 つある点に注意がいる。Overwrite は常に stdin から読まれるが、PIN と
passphrase は `read_passphrase` が読むため、制御端末があれば `/dev/tty` から、
無ければ stdin から読まれる。両方を stdin に流すと、端末の有無で回答の対応がずれる。
`chezmoi apply` は端末付きで走るので、これを踏むと PIN と passphrase が端末に出て
Overwrite の回答が 1 つずれ、同じ鍵が 2 回書き出される。スクリプトは空文字を返す
`SSH_ASKPASS` を `SSH_ASKPASS_REQUIRE=force` で強制して PIN と passphrase の経路を
固定し、stdin は Overwrite の回答専用にしている。

stub file に秘密鍵は含まれない。参照と key handle だけである。

秘密鍵が取り出せないことは次で確かめられる。

```bash
sc_auth export-ctk-identity -h <hash> -f out.p12 -p <pass>
# → Error: ... is hardware bounded and cannot be exported
```

## ssh の設定

`~/.ssh/config` に書く。**chezmoi 管理外なので手で入れる。**

ファイル先頭付近、`Host *` ブロックより**前**に置く。ssh は最初に一致した設定を
優先するため、`Host *` の `IdentityAgent`（1Password）に先を越されないようにする。

```
Host github.com
	IdentityAgent none
	IdentitiesOnly yes
	IdentityFile ~/.ssh/id_github_auth
	SecurityKeyProvider /usr/lib/ssh-keychain.dylib
```

SSH remote のまま動くので、リポジトリの remote URL を書き換える必要は無い。

1Password の `Github` 鍵は GitHub から削除しない。この経路が使えない場面の退路として残す。

## git の設定

`~/.config/git/config` に書く。**chezmoi 管理外なので手で入れる。**

```gitconfig
[user]
	signingkey = ~/.ssh/id_github_sign.pub
[gpg]
	format = ssh
[gpg "ssh"]
	program = ~/.local/bin/git-ssh-sign
[commit]
	gpgsign = true
[tag]
	gpgsign = true
```

`gpg.ssh.program` にラッパーを指定する理由がある。Secure Enclave の鍵で署名するには
`SecurityKeyProvider` が要るが、`ssh-keygen` は ssh_config を読まないため環境変数でしか
渡せない。ラッパー経由なら git config だけで完結し、環境変数が無いシェルからでも署名
できる。該当するのは `chezmoi apply` 前の既存 pane、zsh 以外のシェル、cron である。

ラッパーの実体は chezmoi 管理下にある。ソースは
`private_dot_local/bin/executable_git-ssh-sign`、配布先は `~/.local/bin/git-ssh-sign`。

**`commit.gpgsign = true` は最後に立てる。** 全リポジトリに即座に効くので、署名が
壊れていると全コミットが失敗する。下の動作確認の 3 番まで通してから書き足す。

`dot_zshrc` にも `SSH_SK_PROVIDER` を置いてあるが、これは手動の `ssh-add -K` や `ssh`
のためで、git の署名はラッパー経由なので依存しない。

## 動作確認

上から順に実行する。期待と違ったら次へ進まない。

**1. 認証鍵で GitHub に通る**

```bash
ssh -o BatchMode=yes -T git@github.com
```

期待: `Hi <ユーザー名>! You've successfully authenticated, ...`

`Permission denied (publickey)` なら、GitHub 側で Authentication Key として登録できて
いない。Key type を間違えて Signing Key で登録していないか確認する。

**2. SSH remote の push が 1Password なしで通る**

```bash
GIT_SSH_COMMAND="ssh -o IdentityAgent=none -o IdentitiesOnly=yes \
  -i ~/.ssh/id_github_auth -o SecurityKeyProvider=/usr/lib/ssh-keychain.dylib" \
  git push --dry-run origin HEAD
```

期待: 成功する。ここで使うのは署名鍵ではなく認証鍵の `id_github_auth` である。

`origin` が HTTPS のリポジトリでは `GIT_SSH_COMMAND` が効かず、credential helper 経由に
なってこの確認にならない。その場合は remote 名の代わりに SSH URL を直接書く。

```bash
GIT_SSH_COMMAND="ssh -o IdentityAgent=none -o IdentitiesOnly=yes \
  -i ~/.ssh/id_github_auth -o SecurityKeyProvider=/usr/lib/ssh-keychain.dylib" \
  git push --dry-run git@github.com:<owner>/<repo>.git HEAD
```

**3. ラッパー経由で署名できる**

`commit.gpgsign` を立てる前にここを通す。

```bash
p="$(mktemp)"; echo test > "$p"
env -u SSH_SK_PROVIDER -u SSH_AUTH_SOCK \
  ~/.local/bin/git-ssh-sign -Y sign -n git -f ~/.ssh/id_github_sign "$p"
head -1 "$p.sig"
```

期待: `-----BEGIN SSH SIGNATURE-----` が出る。環境変数を外した状態で通ることが、
ラッパーが効いている証拠である。

**4. コミットに署名が付く**

```bash
d="$(mktemp -d)"; cd "$d"; git init -q; echo x > a.txt; git add a.txt
git commit -m "test: signing"
git cat-file commit HEAD | grep -c 'BEGIN SSH SIGNATURE'
cd /; rm -rf "$d"
```

期待: `1` が出る。`git log --format=%G?` は `allowed_signers` を設定していないため
`N` か `U` になるが、GitHub 側の Verified 判定には影響しない。

**5. GitHub 上で Verified が付く**

コミットを 1 つ push して、GitHub の画面で Verified バッジを見る。
付かない場合は理由を読む。

```bash
gh api 'repos/<owner>/<repo>/commits?per_page=1' --jq '.[0].commit.verification'
```

GitHub は署名検証に `ssh_data` を使う。その既定は `user_presence_required: true` だが、
Apple の `ssh-keychain.dylib` は `-t none` の鍵でも user presence フラグを立てるため
（署名のフラグバイトは `0x21`）、Verified になる。

**6. 承認ゲートが効く**

新しく Claude Code のセッションを開いて確かめる。**起動中のセッションは設定を起動時に
読むため、途中で入れたルールは反映されない。**

Claude Code に `git push --dry-run` と `gh api /user` を実行させ、どちらでも承認
プロンプトが出ること。`git status && git push --dry-run` のような複合コマンドでも、
push 側でプロンプトが出ること。

## 鍵の更新

identity には作成から 1 年の有効期限がある。

```bash
sc_auth list-ctk-identities   # Valid To 列を見る
```

期限が来たら次の手順を踏む。

1. 古い identity を消さずに、新しい label で鍵を作る
2. `ssh-keygen -K -w /usr/lib/ssh-keychain.dylib` を一時ディレクトリで走らせ、
   fingerprint で見分けて新しい stub を `~/.ssh/` に置く。identity が複数ある間は
   上記のファイル名衝突が起きるので、手で回すなら Overwrite の答え方で 1 本ずつ
   取り出す。`.chezmoiscripts/run_onchange_after_80-secure-enclave-keys.sh.tmpl`
   を走らせるほうが確実である
3. GitHub に新しい公開鍵を登録する（Authentication と Signing の 2 つ）
4. `~/.ssh/config` と `~/.config/git/config` のパスを新しい stub に向ける
5. 上の「動作確認」を通す
6. 通ってから GitHub 上の古い公開鍵を削除し、`sc_auth delete-ctk-identity -h <hash>`
   で古い identity を消す

過去のコミットの Verified 表示は、古い公開鍵を削除しても維持される。

## 鍵を失ったとき

Secure Enclave の鍵はバックアップも移行もできない。端末の故障や初期化で失われる。
そのときは GitHub 上の該当する公開鍵を削除し、新しい端末で作り直して登録する。

端末を増やす場合も同じで、端末ごとに鍵を作って追加登録する。Authentication Key と
Signing Key はどちらも複数登録でき、signing key の数に上限は無い。

母艦の Herdr セッションへ ssh して作業する運用なら、git の操作は母艦上で走るため
持ち運び端末に鍵は要らない。持ち運び端末でローカルにコミットする場合だけ作る。

## トレードオフ

`-t none` なので、この端末上のどのプロセスでも鍵を使える。人間の承認は挟まらない。
**防げるのは鍵の持ち出しであって、鍵の使用ではない。**

認証鍵の危険は鍵の盗難ではなく、鍵ができることである。全プライベートリポジトリを
`git clone` できる状態が常時ある。承認ゲートは push と `gh` の書き込みだけを対象に
しており、read は止めない。

それでも平文トークンより優れている。`~/.config/gh/hosts.yml` の OAuth トークンは
ファイルを読むだけで持ち出せて、他のマシンからでも期限なしで使え、`repo` scope は
REST API にも届く。Secure Enclave の鍵は持ち出せず、git の read / write だけで、
1 年で期限が切れる。
