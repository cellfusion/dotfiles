# ツール一覧

使っているツールと、その導入経路をまとめる。マニフェストの実体は
`~/.config/install/` にあり、chezmoi のソースは
`private_dot_config/install/` にある。

`chezmoi init` では yabai、skhd、SketchyBar の使用を個別に選べる。設定は
生成された `~/.config/chezmoi/chezmoi.toml` の `[data.windowManager]` に保存される。
選択を変えるには再度 init する前にこの値を編集する。無効にすると新規導入と
設定配布・サービス登録を省くが、既存のインストールや実行中のサービスは停止しない。
SketchyBar を有効にして yabai を無効にした場合だけ `brew services` から起動する。
SketchyBar 無効時は Lua 5.4、SbarLua、helper、top_bar と使用量採取ジョブも省く。

yabai の上余白は `~/.config/yabai/display-padding` が画面ごとに設定する。
内蔵画面の `NSScreen.safeAreaInsets.top` が 0 より大きければノッチありと判断し、
上余白を 0px にする。ノッチなしの内蔵画面と外部画面は、上部の SketchyBar 用に
38px（バー34px + 隙間4px）を確保する。起動時・画面の接続変更時・スペース追加時に再設定する。

## 管理方法

| 経路 | マニフェスト | 実行するスクリプト |
|---|---|---|
| Homebrew 本体 | なし | `run_onchange_after_00-homebrew.sh` |
| Homebrew | `~/.config/install/Brewfile`、`~/.config/install/third-party.txt` | `run_onchange_after_10-brew.sh` |
| native installer（chezmoi・ランタイム・Herdr） | なし（スクリプトに直書き） | `run_onchange_after_20-runtimes.sh` |
| mise | `~/.config/mise/config.toml` | `run_onchange_after_30-mise.sh` |
| native installer（AI CLI） | なし（スクリプトに直書き） | `run_onchange_after_40-ai-clis.sh` |
| cargo | `~/.config/install/cargo-globals.txt` | `run_onchange_after_60-cargo.sh` |
| ビルド・サービス登録 | sketchybar helper のソース、SbarLua の固定コミット | `run_onchange_after_70-macos-services.sh` |
| GitHub 用の鍵生成 | なし（Secure Enclave の状態を見る） | `run_onchange_after_80-secure-enclave-keys.sh` |
| AI 環境ディレクトリ | `~/.config/chezmoi/agent-config.json` の `environments` | `run_onchange_after_90-agent-envs.sh` |

マニフェストを持つスクリプトは、そのハッシュを埋め込んでいる。マニフェストを
書き換えたときだけ `chezmoi apply` で走る。マニフェストを持たない 4 本
（00 / 20 / 40 / 80）は、対象が未導入のときだけ入れる。

実行するのはインストールだけで、既に入っているものの upgrade は行わない。
`brew bundle` は既定で outdated な formula もまとめて upgrade するため、
`--no-upgrade` を付けている。更新したいときは `brew upgrade` を手で回す。

日常 CLI は原則 mise、Homebrew は Git・GNU coreutils・macOS 統合・ライブラリ・
移行経路を確定していないモバイル開発ツールに絞る。自己更新ツールと構築の起点は
native installer に残す。Brewfile から外しても、既存の Brew / npm コピーは削除しない。

手で回すこともできる。

    brew bundle --file ~/.config/install/Brewfile --no-upgrade

non-official tap の formula は Brewfile に載せず `~/.config/install/third-party.txt` に
分けてある。fully-qualified 名で入れると tap と trust が自動で付くため、Homebrew 6 の
tap trust に止められない。手で回すなら次のとおり。

    xargs -n1 brew install < ~/.config/install/third-party.txt

### 一部だけを管理するファイル

ツール自身が実行中に書き換えるファイルは、全体を chezmoi に持たせない。全体を
管理すると、ツールが書き足すたびに `chezmoi diff` が汚れ、`chezmoi apply` で
書き足した内容が消える。chezmoi の `modify_` スクリプトで、保証したい範囲だけを
差し込む。

| ファイル | ツールが書き足すもの | chezmoi が保証する範囲 |
|---|---|---|
| `~/.config/codex/config.toml` | `[projects]` の `trust_level`、MCP サーバー | model、承認設定、sandbox 設定 |
| `~/.config/codex/rules/default.rules` | 承認を永続化したときの `prefix_rule` と `network_rule` | `# chezmoi-managed-begin` と `# chezmoi-managed-end` で囲んだ範囲 |

`default.rules` は Codex の execpolicy である。コマンドの承認を省くかどうかを
`prefix_rule` で決め、`decision` に `allow` / `prompt` / `forbidden` のどれかを取る。
`allow` は承認を省くだけでなく sandbox の外での実行まで許すため、囲みに入れるのは
ファイルの内容を変えない操作と、検証コマンドに限る。

囲みの外に見覚えのない行があれば、承認ダイアログで永続化を選んだときに Codex が
書いたものである。消してよい。囲みの中を手で直しても `chezmoi apply` で戻るので、
変えたいときは `private_dot_config/codex/rules/modify_default.rules.tmpl` を直す。

2 つ目以降の AI 環境は、`~/.config/codex_<environment>/rules` を
`~/.config/codex/rules` への symlink にして実体を共有する。どの環境で承認を
永続化しても、全環境に載る。`config.toml` は `preservedMutable` にあり環境ごとに
実体を持つので、`trust_level` は環境をまたがない。

symlink を張る一覧は 1 か所では決まらない。
`~/.local/share/agent-config/config-validator.js` の `SETUP_TABLE` が正本で、
`~/.config/chezmoi/agent-config.json` の `providers.codex.setup.symlinks` が
JSON 文字列として完全一致しないと検証に落ち、`chezmoi apply` が失敗する。
`agent-config.json` は chezmoi の管理外なので、`SETUP_TABLE` を変えたら手で
そろえる。リポジトリ側では `agent-config.sample.json` も更新する。

## 新マシンでの手順

素の macOS の `/usr/bin/git` は Xcode Command Line Tools の stub である。実行すると
GUI のインストールダイアログが出て、入っていなければ `chezmoi init` の clone が
そこで失敗する。先に本体を入れておく。

    xcode-select --install

    sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply cellfusion

これ 1 本で終わる。chezmoi が入り、リポジトリが clone され、apply が走る。
applyの中で上の表のスクリプトが番号順に実行される。

この 1 本目の chezmoi は install script の既定の BINDIR、つまり実行したディレクトリの
`./bin` に置かれる。PATH には載らない。恒久的な chezmoi は apply の中で 20-runtimes が
`~/.local/bin` に入れるので、apply が終わったら `./bin` は消してよい。

各スクリプトは前提が無ければ自分で入れ、入れられなければ非ゼロで落ちる。chezmoi は
非ゼロで終わったスクリプトを実行済みとして記録しないため、落ちたところから次の
apply で再開する。飛ばされて黙って記録される状態にはならない。

途中で落ちたら、表示された原因を直してから `chezmoi apply` をもう一度回す。

Homebrew の導入と cask のインストールで、sudo のパスワードを複数回聞かれる。

## apply 後に手でやること

自動化できないものが 6 つある。

1. **アクセシビリティ権限の付与**（yabai と skhd）。システム設定 → プライバシーと
   セキュリティ → アクセシビリティ で許可する。付与するまでウィンドウ操作と
   ホットキーは効かない
2. **`~/.config/chezmoi/private-data.toml` の配置**。Cloudflare のアカウント ID、AWS プロファイル、
   1Password のパス、再汚染テストの禁止語を持つ。無くても apply は通り、各テンプレートは既定値で
   描画される。Claude／Codex の環境と project rule は下の `agent-config.json` で管理する。
3. **1Password へのサインイン**。AWS の `credential_process` が `op read` を呼ぶ
4. **AquaSKK の導入と入力ソースへの追加**。2026-08-27 に Brewfile から外したので
   apply では入らない。手で入れたうえで、システム設定 → キーボード → 入力ソース で
   AquaSKK を追加し、ログインし直す
5. **GitHub への鍵の登録**。`run_onchange_after_80-secure-enclave-keys.sh` が
   Secure Enclave に認証鍵と署名鍵を作り、公開鍵を 2 つ表示して終わる。
   https://github.com/settings/keys で片方を **Authentication Key**、
   もう片方を **Signing Key** として登録する。この 2 つは別枠なので、
   Key type の選択を間違えると push か Verified のどちらかが通らない。
   秘密鍵は Secure Enclave から出ないため、この登録だけは自動化できない。
   詳細は `~/.config/docs/git-signing.md` にある
6. **SketchyBar の使用量採取ジョブの読み込み**。`chezmoi apply` は
   `~/Library/LaunchAgents/com.cellfusion.sketchybar-usage-claude.plist` を置くだけである。
   次のログインを待たずに有効にするなら
   `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cellfusion.sketchybar-usage-claude.plist`
   を実行する。読み込むまで Claude の週次使用率は更新されない。
   詳細は `~/.config/docs/sketchybar-usage.md` にある

sketchybar のカレンダー表示を使う場合は、フルディスクアクセスの付与も要る。
システム設定 → プライバシーとセキュリティ → フルディスクアクセス に
`~/.config/sketchybar/helpers/event_providers/calendar_events/bin/calendar_events`
を足す。makefile が ad-hoc 署名を打っているので、付与は再ビルドをまたいで保持される。

## OMP の共有設定

`~/.omp/agent/config.yml` は `private_dot_omp/agent/private_config.yml` から mode 0600 で配布する。
全マシンでデフォルト環境の model、TUI、composer、編集・圧縮設定を共有する。
`composer.shape: pi` は OMP の表示スタイル名であり、Pi CLI の導入は不要である。

通常の `omp` 起動は `agent --family=omp` に委譲し、Claude／Codex と同じ環境選択を使う。
設定がある場合、デフォルト環境は native default、それ以外は環境名の OMP profile へ切り替える。
`command omp` や絶対パスからの起動は wrapper を通らず、環境変数も変更しない。
明示的な `--profile` は OMP 本体の機能として使えるが、profile の設定は配布しない。
通常の `omp` と `agent --family=omp` は `PI_FORCE_IMAGE_PROTOCOL=kitty` を既定値にし、
Herdr 内でも画像表示を有効にする。接続先の端末と Herdr の Kitty graphics 対応が必要になる。
明示的な指定は保持するため、無効にする場合は `PI_FORCE_IMAGE_PROTOCOL=off omp` で起動する。
`command omp` や絶対パスでの直接起動には、この既定値は付かない。

認証、`agent.db`、履歴、session、cache、`~/.omp/profiles/` は chezmoi 管理外である。
Herdr／Moshi の拡張は各マシンで導入し、ホスト固有の拡張や認証を設定ファイルと一緒にコピーしない。
新マシンでは OMP 本体を導入し、各 provider に個別にログインする。

OMP の設定画面や `omp config` で変更した内容はローカル設定に保存される。
共有する変更は chezmoi ソースにも反映し、対象限定の `chezmoi diff ~/.omp/agent/config.yml` で確認する。
ソースへ取り込まないローカル変更は、次の明示的な apply で上書きされる。
現在の設定を取り込む場合も、認証情報やマシン固有のパスが追加されていないか確認してから行う。

## Claude／Codex の環境設定

`~/.config/chezmoi/agent-config.json` はローカルの環境定義であり、chezmoi 管理外である。
公開 schema と sample は `~/.local/share/agent-config/agent-config.schema.json` と
`~/.local/share/agent-config/agent-config.sample.json` に配布する。
OMP の共有設定とは別で、Claude／Codex の認証・履歴の分離だけに使う。

旧 Paseo 用 version 2 からは、apply 前にローカル定義を version 3 へ変更する。
`defaults.environment`、Claude／Codex の `displayName` と `setup`、`agentRoles`、
`environments` の `providers`、`projectRouting.rules` を残す。
環境ごとの provider 一覧から Pi、opencode、OMP を外し、root `providers` も Claude／Codex だけにする。
`selection`、`singleSelection`、`routingSelection`、`attemptPolicy`、
provider の `backends`、`featureAllowlist`、`environmentVariable`、環境ごとの `selection`、
role の `launchPolicy` は削除する。
公開 sample を参照し、認証や個人の project path を公開ソースへ写さない。

```bash
source_dir="$(chezmoi source-path)"
node "$source_dir/private_dot_local/bin/executable_agent-config" \
  --input "$HOME/.config/chezmoi/agent-config.json" validate
```

この検証は統合済みの新しいソースから実行する。旧配布済み CLI には `validate` が無いため、
apply 前の確認には使わない。apply 後は `agent-config ... validate` で同じ検証を行える。

不正な定義を default にフォールバックさせない。検証が通ってから、明示承認した apply で
Claude／Codex の環境ディレクトリを準備する。`setup` は共有設定への symlink を作り、
既存の認証・履歴を保存する。実体や別の symlink と衝突した場合は停止し、自動上書きしない。


## agent で AI 環境を指定して起動する

`~/.local/bin/agent` は Claude／Codex／OMP の環境選択に対応する。
`~/.config/chezmoi/agent-config.json` を検査し、環境変数を設定して CLI を `exec` する。

```text
agent --family=claude|codex|omp [--environment=<environment>] [--] [args...]
```

設定ファイル（`AGENT_CONFIG` を指定した場合はその path）が無ければ、`--family` の
Claude／Codex／OMP CLI をそのまま起動する。引数と既存の環境変数は引き継ぎ、
`AGENT_ENV` や隔離用の変数は追加・変更しない。この場合、`--environment` は解決できないため
終了コード 2 で失敗する。設定ファイルが不正、または未存在以外の理由で読めない場合も停止する。

`--provider` による旧 Paseo provider ID の起動は廃止した。

全 family は cwd-aware 起動で、環境を explicit `--environment`、親 `AGENT_ENV`、最初に一致した
`projectRouting.rules` rule、`defaults.environment` の順に選ぶ。たとえば
`agent --family=codex --environment=pxgrid` は親や cwd rule と異なる `pxgrid` への明示切替を許す。
ただし、トップレベルの `providers` と選択した environment の `providers` の両方に
対象 family が登録されていなければ起動しない。`--environment` は全 family で使える。

`match.gitRepository` は Git common directory を比較するため、登録した checkout の linked worktree と
その subdirectory でも同じ environment を選ぶ。`match.remoteNamespace` は
`github.com/example-org` のような正規化済み namespace を使い、その配下の全 repository に一致する。
Git 外 cwd、無関係 repository、どの rule にも一致しない cwd は default environment を使う。
Unknown environment、invalid config、ineligible family では default へ落とさず終了コード 2 で失敗する。

正常時は `AGENT_ENV` と family の隔離変数を設定する。Claude は `CLAUDE_CONFIG_DIR`、
Codex は `CODEX_HOME` を使う。OMP はデフォルト環境なら `OMP_PROFILE` を解除し、
それ以外なら選択した環境名を設定する。設定がある場合、継承した `PI_CODING_AGENT_DIR` も解除する。

zsh の bare `claude`、`codex`、`omp` は `agent --family=<family>` へ送る。
`codex update` は native CLI へ送る。`command claude`、absolute executable path、
zsh 設定を読まない process は family wrapper を bypass する。
OMP を有効にするには、`agent-config.json` の `providers` に
`"omp": { "displayName": "OMP", "setup": null }` を追加し、利用する各 environment の
`providers` に `"omp"` を追加する。サンプル設定にもこの登録を含めている。
OMP の profile はネイティブの保存先を使い、`agent-config setup` によるディレクトリ共有は行わない。
`agent --family=omp --environment=lab -- [args...]` は、`lab` が非デフォルト環境なら
OMP の `lab` プロファイルで起動する。`--environment lab` 形式も使える。
設定なしでの明示的なプロファイル指定は `agent --family=omp -- --profile lab` で OMP 本体に渡せる。


## core

| ツール | 用途 |
|---|---|
| git | バージョン管理 |
| gh | GitHub CLI |
| ghq | リポジトリのローカル管理 |
| git-lfs | Git Large File Storage |
| lazygit | git の TUI クライアント |
| worktrunk | git worktree マネージャ（`wt`）。herdr と併用する |
| neovim | エディタ |
| fzf | 曖昧検索 |
| fd | 高速 find |
| ripgrep | 高速 grep |
| bat | シンタックスハイライト付き cat |
| glow | マークダウンを整形して表示するページャ |
| eza | 高機能 ls |
| jq | JSON 処理 |
| television | ファジーファインダー |
| zoxide | 賢い cd |
| herdr | ターミナルマルチプレクサ |

## 開発ツール

mise / bun / uv / rustup / chezmoi / herdr は native installer、go と下記 CLI は mise が管理する。
それぞれの節を見る。

| ツール | 用途 |
|---|---|
| sccache | ビルドキャッシュ |
| awscli | AWS CLI |
| grpcurl | gRPC 用 curl |

## macOS 専用

| ツール | 用途 |
|---|---|
| coreutils | GNU coreutils |
| yabai | タイリングウィンドウマネージャ |
| skhd | ホットキーデーモン |
| borders | ウィンドウ枠の強調表示 |
| lua@5.4 | sketchybar の起動に必要（sketchybarrc の shebang が指している） |
| sketchybar | カスタムメニューバー |
| SbarLua | Lua 5.4 用 SketchyBar モジュール（公式 commit 固定でビルド） |
| ghostty (cask) | ターミナルエミュレータ |
| 1password-cli (cask) | 1Password CLI |
| finicky (cask) | デフォルトブラウザ振り分け |
| font-hack-nerd-font (cask) | Nerd Font |
| font-sf-mono (cask) | SF Mono フォント |
| font-sf-pro (cask) | SF Pro フォント |
| sf-symbols (cask) | SF Symbols アプリ |

## モバイル・ネイティブ開発

| ツール | 用途 |
|---|---|
| cocoapods | iOS/macOS 依存管理 |
| ios-deploy | iOS 実機へのインストール・デバッグ |
| libimobiledevice | iOS デバイス通信ライブラリ |
| xcodegen | Xcode プロジェクト生成 |
| xcode-build-server | Xcode ビルドサーバー（LSP 連携） |
| apktool | APK の逆コンパイル・再構築 |
| jadx | Android の逆コンパイラ |
| kdoctor | Kotlin/Native 開発環境の診断 |
| gradle | Android/JVM ビルドツール |

## native installer

自己更新を持つツール、または Homebrew 版が別ビルドになるツールは brew に寄せない。
未導入のときだけ入れて、更新は各ツールに任せる。chezmoi / mise / bun / uv / rustup / herdr は
`run_onchange_after_20-runtimes.sh` が、claude / codex は
`run_onchange_after_40-ai-clis.sh` が入れる。

chezmoi の install script の既定の BINDIR は `./bin`（実行時のカレントディレクトリ
配下）である。`-b` を渡さないと、`.zshenv` が PATH に載せる `~/.local/bin` には入らない。

| ツール | 導入 | 理由 |
|---|---|---|
| chezmoi | `sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"` | 新マシンの起点になる。20-runtimes が未導入のときだけ入れる。brew 版を併せて入れると 2 本になる |
| mise | `curl https://mise.run \| sh` | Homebrew 版は別ビルドで、公式の最適化されたリリースバイナリではない |
| bun | `curl -fsSL https://bun.sh/install \| bash` | `bun upgrade` で自己更新する |
| uv | `curl -LsSf https://astral.sh/uv/install.sh \| UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh` | `uv self update` で自己更新する。installer に shell 設定を書き換えさせない |
| rustup | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh -s -- -y --no-modify-path` | brew 版は keg-only で toolchain を持たない |
| herdr | `curl -fsSL https://herdr.dev/install.sh \| sh` | 公式 checksum 検証付き installer。native 配布だけ `herdr update` で更新する |
| claude | `curl -fsSL https://claude.ai/install.sh \| bash` | 自己更新を持つ |
| codex | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | 自己更新を持つ |

claude と codex を brew に寄せない理由はもう 1 つある。Homebrew の `claude-code`
cask は stable チャネルを追う一方、アプリ内の更新通知は latest チャネルを見るため、
cask に未着のバージョンを「更新あり」と表示する状態が起きる。

rustup に `--no-modify-path` を渡すのは、PATH の管理を `~/.config/zsh/.zshenv` と
`.chezmoitemplates/install/preamble` に一本化するためである。rustup 自身に shell の
設定ファイルを書き換えさせない。

導入済み判定は PATH 上の同名コマンドではなく、native installer の実際の保存先を確認する。
`~/.local/bin` の chezmoi / mise / uv / herdr、`$BUN_INSTALL/bin/bun`、
`$CARGO_HOME/bin/rustup` が正本である。更新も正本を使い、Brew 版を self-update しない。
chezmoi は `chezmoi upgrade`、mise は `mise self-update`、rustup は `rustup self update` で更新する。

### zsh の初期化とシステム設定

`~/.zshenv` は `ZDOTDIR` を選び、`~/.config/zsh/.zshenv` を明示的に読む。
zsh は読み込み中に `ZDOTDIR` が変わっても、変更先の `.zshenv` を読み直さない。
この手順で Android・Rust・Deno・AWS の参照先と `.NET` user tools の PATH を、
非対話シェルにも設定する。回帰検査は `bash tests/test-zsh-bootstrap.sh`。

1Password のプラグイン、ghcup、uv の環境ファイルは、読み取り可能な場合だけ読み込む。
`tv`、`zoxide`、`mise`、`wt`、Kiro の shell integration はコマンドがある場合だけ初期化する。
1Password の SSH agent socket が無いマシンでは、既存の `SSH_AUTH_SOCK` を維持する。

`/etc/zshenv` で `ZDOTDIR` を無条件に上書きしない。既存マシンに残っている代入は
管理者権限で除く。`/etc/paths.d/dotnet-cli-tools` の `~/.dotnet/tools` も
path_helper では展開されないため、バックアップを `/etc/paths.d` の外へ保存して除く。
user tools の正しい PATH は chezmoi の `.zshenv` で管理する。

login shell の `JAVA_HOME` は `.zprofile` が `mise where java` から取得する。
Android Studio の導入場所や Homebrew の Java に固定しない。対話シェルでは
既存の `mise activate zsh` も有効になる。

## mise 管理

node / python / java / pnpm / deno / go と日常 CLI を mise で管理し、Brewfile には載せない。
`run_onchange_after_30-mise.sh` はグローバル設定のディレクトリから install する。
呼び出し元 project の設定や `--bump` は使わない。

| ツール | バージョン | 用途 |
|---|---|---|
| python | 3.13 | Python ランタイム |
| node | 26.10 | Node.js ランタイム |
| pnpm | 10.16.1 | Node.js パッケージマネージャ |
| java | 25 | JVM ランタイム |
| deno | 2.5 | Deno ランタイム |
| go | 1.26 | Go ランタイム |

### 日常 CLI

以下はすべて `latest` を追う。バージョン範囲を持つランタイムとは更新方針が異なる。

| backend | ツール |
|---|---|
| Aqua | gh、ghq、git-lfs、lazygit、Neovim、fzf、fd、ripgrep、bat、glow、jq、television、zoxide、sccache、AWS CLI、grpcurl |
| GitHub release | worktrunk（`wt`） |
| Cargo | eza（macOS 向けの配布バイナリがないため rustup の toolchain でビルド） |
| npm | wrangler、firebase-tools、mcp-hub |

`~/.local/bin` の各 CLI は `mise-tool` への symlink である。CLI だけを解決して exec するため、
SketchyBar など PATH が狭い process でも起動でき、全 runtime の activation は不要になる。
pnpm / deno / go は既存の専用 launcher、rustup は native `$CARGO_HOME/bin/rustup` を選ぶ。
project ごとの mise 設定は尊重する。

npm CLI は `mise where` が返す専用 install root の `bin` を使い、選択された Node の
`bin` だけを PATH の先頭に追加する。`mise which --tool` は他の有効 tool も検索し、
Node に残った旧 npm グローバルを拾うため、npm CLI の解決には使わない。
Python の PATH と親の JAVA_HOME は変更しない。AWS CLI は `symlink_bins = true` で
同梱 Python を `mise activate` / `mise exec` の PATH にも公開しない。

### 更新と移行

`mise upgrade` は指定されたバージョン範囲を維持する。`pnpm = "10.16.1"` は完全固定なので、
通常の upgrade では進まない。`--bump` は config.toml を書き換えるため、chezmoi の実 target に
定期ジョブから使わず、範囲変更は source で行う。定期更新ジョブはまだ配布していない。

既存マシンでは、移行前に native mise を `~/.local/bin/mise self-update` で更新する。
2025.12.13 では gh 2.102.0 の attestation 応答を読み取れず導入に失敗し、
隔離環境の mise 2026.10.2 では検証を有効にしたまま導入できた。検証を無効化しない。

CLI の導入・version・シェル連携と、GUI / 非対話 process からの起動を確認してから
既存 Brew / npm コピーの削除を判断する。apply でパッケージの uninstall は行わない。
旧 npm グローバルのマニフェストと専用 installer は廃止した。

## cargo 管理

直接 cargo install するツールは無い。マニフェスト `~/.config/install/cargo-globals.txt` は
コメント行だけで、`run_onchange_after_60-cargo.sh` は何も入れない。eza は mise の Cargo backend が管理する。

## PR本文の作成と承認

`create-pr` は、ブランチ全体の差分・履歴・関連資料を調べ、変更の種類に合うタイトルと
PR本文を作る。不具合修正では発生条件・原因・修正前後・回帰確認、新機能では利用者の
課題・利用方法・設計理由・制約を中心に説明する。API、UI、リファクタリング、性能、
データ移行、設定・CI、依存関係、文書・テストにも対応し、混在する変更は必要な観点を組み合わせる。

APIの変更では、影響する各エンドポイントの意図、必要な入力、成功・主要なエラーレスポンスの
例、認証・互換性を記載する。仕様のみの変更と実装済みの動作を区別し、不明な意図や未実行の
確認結果を補って書かない。

「create-pr を使って、このブランチのPR本文を作って」と依頼する。これはシェルコマンドではない。
OMP／Codexには `~/.agents/skills/create-pr/`、Claude Codeには
`~/.config/claude/skills/create-pr/` を同じテンプレートから配る。

本文は原則 `~/.local/state/create-pr/runs/<run>/<revision>/body.md` に保存する。
同じ場所の `context.json` にタイトル・作成先・base/headのSHA・本文ハッシュ、
`evidence.md` に根拠と確認状況を残す。表示した版について明示的に作成を承認するまでは、
draftを含めてPRを作成しない。「本文はOK」と「PRを作成」は別の判断であり、保存のみも選べる。
本文・タイトル・作成先・SHAなどが変わったら再確認する。commit・push・fork・既存PRの編集、
添付アップロード・merge・chezmoi applyは別の許可が必要。

スキルはエージェントへの手順であり、公開を技術的に遮断する仕組みではない。
ホスト側の権限確認は有効にしておく。`finishing-a-development-branch` のpush/PR経路でも、
push後にこの本文確認・承認の手順を通す。

## 技術文章レビュー

`technical-writing-review` は、GitHub の PR 本文・コメント、README、設計説明、手順を
書く・推敲する・レビューするときに使う。日本語を中心に、可読性、読者に必要な説明、
構成と図表を3つの読み取り専用サブエージェントで並列に確認し、親が指摘を統合する。
コード差分の正しさを調べる `pr-review` とは別用途である。

OMP／Codex 向けの `~/.agents/skills` と Claude Code の `~/.config/claude/skills` に、
同じ本体とレビュー用 references を配る。
明示的に使いたい場合は「technical-writing-review を使って、この PR 本文を書いて」
などと依頼する。執筆依頼ではレビュー後の原稿、レビュー依頼では引用付きの指摘を返す。
スキルの description に執筆時の発動条件を記載しているが、自動選択を常に保証するものではない。

短いコメントに不要な背景や図を要求せず、API 名・条件・否定・元の語調を保持する。
根拠のない性能値や確認結果は創作せず、確認事項として分離する。図表は理解を助ける場合だけ、
種類・必要な要素・掲載位置を提案する。子が失敗した場合は不足した観点を明示する。
スキルの選択だけでは、GitHub への投稿やファイルの書き換えは許可されない。

## 手動インストール

マニフェストに載せていないが使っているもの。

AquaSKK。2026-08-27 に Brewfile から外した。辞書は `~/.config/skk` にあり、chezmoi の
管理外である。

## Herdr・OMPの開発ワークフロー

メインの実行環境はmainMBP。GhosttyでHerdrを開き、OMP、Neovim、LazyGit、Tuicrを使う。
subMBPはGhostty／Herdr／Tailscaleを使い、`herdr --remote`でmainMBP側へ接続する。
Android端末にはMoshiを使う。接続元へ認証や履歴を複製しない。

- メイン作業はdefaultブランチからHerdrのworktree＋workspaceを作成する。
- 同一リポジトリの通常の委譲はOMP内で済ませる。
- 別リポジトリの変更は、そのリポジトリのHerdr workspaceの担当へ依頼する。
  適合するidle担当を再利用し、いなければ対象workspaceでOMPをno-focus起動する。
- 独立対話、ユーザー介入、別CLIエージェントにもHerdrの別paneを使う。
- 書き込み分離だけならWorktrunkで子worktreeを作り、Herdrには表示しない。
- worktreeの所有権、統合状態、終了手順は[worktrees.md](worktrees.md)に従う。

`task-routing` と `multi-agent-development` はこの区分を使う。
エージェントの権限や model 設定を、端末を分けるためだけに変更しない。

`agent-communication` は宛先確認、依頼・質問・補足の受け渡しと返答の照合を担当する。
共通手順は `~/.agents/skills/agent-communication/SKILL.md`、OMP／Herdrの操作資料は
同ディレクトリの `references/` にあり、Claude側にも同じテンプレートから配る。
workspace名だけで選ばず、実際のrepository／cwd／agent sessionと作業範囲を確認する。
作業中の別担当へ割り込まず、依頼IDを返答と照合する。idleやtimeoutだけで完了・未送信と判断しない。
担当は各repositoryを検証し、親は契約の一致と結合動作を確認する。
渡すのは必要な契約と担当範囲だけで、会話全体・認証情報は渡さない。
同じ文脈の再利用で重複調査を避けるが、トークン削減量は保証しない。

native role は Claude Code、Codex へ同じ role catalog から配る。
Claude Code は `~/.config/claude/agents`、Codex は `$CODEX_HOME/agents` を使う。

MAD の route 記録は OMP 内部委譲／Herdr CLI の backend だけを新規に受け付ける。
集計器は移行前の既存ログも読み取るが、退役 backend での新しい記録は拒否する。

### ツールの入口

| 入口 | 動作 |
|---|---|
| `lazygit` / `Alt-g` | 現在の作業場所でLazyGit。ショートカットは全画面popup |
| `tuicr` / `Alt-a` | 現在の作業場所でTuicr。ショートカットは全画面popup |
| `pr-review [--environment herdr\|orca\|paseo] [--quick] <番号またはURL>` | 実行環境を選び、固定PR base SHAの隔離checkoutと専用OMPを起動 |
| `agent-usage` / `Ctrl-b → u` | アカウント使用枠を確認。ショートカットは操作待ちのpopup |

汎用agent-launcherは廃止し、別エージェントは必要な場面でHerdrから直接起動する。
既存のClaude新tab起動、ファイル選択、zoxide、スクラッチ端末は維持する。

### PRレビュー

実行環境は `--environment` の明示指定を優先し、未指定なら現在のhostを判定する。
host不明・複数一致・必須能力不足では環境作成前に停止する。Orcaへ暗黙にfallbackしない。
Herdrを選ぶ場合はHerdr管理下から実行し、現在のリポジトリ、または
`--repo-path <絶対path>` で指定したローカルリポジトリを使う。URLのrepositoryと照合する。

```bash
pr-review --environment herdr --no-focus 123
pr-review --environment herdr --repo-path /path/to/repo --quick https://github.com/owner/repo/pull/123
pr-review --environment orca --project my-project 123
```

Orcaの `--project` は登録プロジェクトの表示名完全一致、または `id:<repoId>`。
URLだけでもOrca登録済みプロジェクトを検索できる。未登録・複数一致は作成前に停止する。
Orca登録IDをHerdrへ流用しない。Paseoは既知だが未対応の環境として、
run directory・checkout・sessionを作る前に `unsupported-environment` で停止する。
エージェントから呼ぶときは `--no-focus` を付ける。

レビュー手順は共通にし、環境操作は `pr-review/environments/` のadapterで切り替える。
Orcaではバージョン一致ガイドに従い、worktreeのsetupを `skip` にする。
環境ごとの起動でも `--session-dir` と `autoResume: false` で私有sessionを使い、
実際のpane/terminal・agent・cwdを照合してから要求を送る。
送信受理・実行開始・レビュー完了は別の証拠で確認する。
Orcaの `turn_started` を他環境のreceiptに読み替えず、開始未確認なら `accepted` として報告する。
Herdr経路はWorktrunkの `--no-hooks` でcheckoutを作り、そのpathをHerdr workspaceに開く。
checkout ownerは `worktrunk`、実行環境は `herdr`。prompt応答は受理のみを証明する。
ローカルmacOS/Linuxのbash/zshで、シェルの入力待ちを確認してから短い私有setup scriptを
読み込ませる。setupのtoken ACKを確認するまではOMPを開始しない。
OMPは最初の要求までsessionファイルを保存しないため、起動前は私有親directoryとlive identityを
検証し、prepared実行では保存済みsessionファイルの所有者・0600権限も必須にする。

レビュー用worktreeはPRのbase SHAから作る。head側の指示ファイルをOMP起動時に読み込ませない。
準備済み情報と固定base/headを専用OMPへ渡し、同じ環境内でレビューを続ける。
成果物とworkspaceは保持し、GitHubへの投稿は明示確認後に行う。
起動失敗やtimeoutで、別環境を自動作成したり既存環境を削除したりしない。

prepared contextはversion 3。実行環境、checkout owner、対話環境のIDを分けて記録する。
runtime・adapter・参照文書はrun内へ保存し、再開時に配布元の別版へ切り替えない。
旧version 2のrunは保持するが新runtimeでは受け付けない。継続にはそのrunの旧snapshotを使う。

開始時に、実際の branch・SHA・base checkout の場所と、レビュー対象の固定 base/head SHA を
分けて表示する。cwd が base でも head のソースは固定 Git blob から読めるが、その cwd で
head のテスト・ビルドは実行しない。実行できない項目や権限不足は、開始時から明示する。
head へ checkout して解消しようとしない。

私有 run の trusted `runtime.js` が `inspect-context`、`prepare-coverage`、
`read-source`、`render-summary`、`validate-review` を提供する。`prepare-coverage` は固定 merge-base から
head までの全 changed file を `coverage.json` に列挙する。`read-source` の `base` は
比較元の merge-base、`head` は固定 head を指し、実行中の base checkout とは区別する。
取得範囲は `context/source-reads.jsonl`、本文は `context/source-evidence/` に残る。
全体の探索には、同じ処理が保存する `context/base-tree.json` と `context/head-tree.json`
（固定 tree の全 path・mode・type・object ID）を使う。未変更ファイルや gitlink も一覧に残る。
取得しただけでは精読の証明にならないため、出力が省略された範囲は分割して実際に読む。

追加ファイルの base 側、削除ファイルの head 側は存在しないものとして扱う。同じ path が
ディレクトリに変わっても、その tree を file blob として扱わない。rename は旧 path と新 path
で比較し、純粋な移動や diff の context 行を inline finding の変更行として扱わない。
旧 path がディレクトリになった場合も、配下の別ファイルの追加行を rename 先の根拠にしない。
Git の引用付き path を復元し、対象 head path の diff section 内だけで追加行を検証する。

各ファイルを精読・機械比較・理由付き除外・未確認に分類し、未変更の caller や依存先も
必要に応じて追う。重要な挙動は before/after、到達経路、静的確認か実行確認かを記録する。
メジャー依存更新や非同期 lifecycle の変更は高リスクとして扱う。finding では新規回帰と
既存不具合・意図した変更を区別し、公式仕様、静的解析、既存 CI、ローカル再現の根拠と
限界を混同しない。同一セッションで観点を切り替えた逐次確認を、独立レビューとは呼ばない。

finding の CI／local 根拠と挙動の `executed` は、固定 head の `targetSha` を持つ
同種 check の `pass` または `fail` を参照する。`executed` は実行済みの意味であり、
成功の意味ではない。`not_run` は実行根拠にならず、PR script の実行を義務付けるものでもない。
委譲は `none` または `omp-internal` とし、summary route は完了 lens の
`independent` > `sequential` > `primary` の順で決める。完了 lens がなければ `primary` とする。

JSON 成果物を構成した後、`render-summary <prepared-context.json>` の JSON 応答から
`markdown` を取得し、`<!-- pr-review-summary:start -->` から
`<!-- pr-review-summary:end -->` までの block 全体を `review.md` に一度だけ挿入する。
分類件数・除外・未読、実際の checkout と対象 SHA、plan/profile、委譲・lens route、
check 結果と制限は canonical 成果物から生成する。block を手書きで変更せず、元の成果物を
変更したら再生成する。runtime の export は `renderSummary(file, cwd?, env?)`。

render は承認や検証完了ではない。最終報告前と投稿前に `validate-review` で identity、
証跡・範囲、coverage、finding、check、plan、metadata の pr/revision/review/workspace/delegation、
report の整合を検査する。canonical block は唯一かつ生成結果と完全一致させ、
`Verdict: ...`、`Coverage: complete|partial` の該当値と canonical finding heading も保持する。
未確認が残る場合は partial とし、profile を full にせず、PASS も出さない。具体的な指摘が
なければ BLOCKED、根拠のある指摘があれば制限付きの NEEDS_ATTENTION とする。complete でも
除外や静的確認の限界は残り、整合検査の成功は全不具合の発見や実行時の正しさ、任意の文章の
真偽を保証しない。投稿には検証済みの block を含む本文を使い、明示確認と stale 拒否を維持する。

Claude command の管理元は `private_dot_config/claude/commands/pr-review.md.tmpl`。
共通 skill を展開して配布するため、テンプレート式を含む通常の `.md` として保存しない。

PRレビューはHerdrまたは明示選択したOrcaのadapterで起動する。
以前のOrca設定・OMP拡張やPaseo transportは復活させない。
Paseo、Pi、opencodeの旧設定配布・起動連携は退役した。
`.chezmoiremove` は以前配布した個別ファイルと旧Orca OMP拡張を回収する。
Orca専用の `orca-cli` と `computer-use` スキルは撤去する。Orca adapterの操作契約は
選択したCLI自身のバージョン一致ガイドで確認し、撤去済みスキルに依存しない。
旧アプリの撤去には明示承認が必要。chezmoi はアプリのアンインストールを行わない。
認証・会話履歴・作業リポジトリは残し、保存データを一括削除しない。
Paseo の履歴採取ジョブが稼働している場合は、削除対象を apply する前に
`launchctl bootout gui/$(id -u)/com.cellfusion.paseo-link-claude-history` で停止する。

### アカウント使用枠

使用率、リセット時刻、取得時刻、情報源と鮮度を確認する。
同じアカウントを複数エージェントが使う場合は共有枠であり、数値を合算しない。
OMPは複数providerを使えるため、OMP固有の枠とは表示しない。
取得できない値を0%にしない。古いキャッシュは最新値として表示しない。
制限窓の長さが保存されていない旧キャッシュでは、長さを推測しない。

収集器の管理元は`paseo_usage_plugin`リポジトリ。通常はOMPの使用枠と既存のnative
Claude／Codexキャッシュを表示し、`agent-usage --refresh`で使用枠だけを強制更新する。
`--cache-only`はnativeキャッシュのみを読み、providerへ問い合わせない。

更新には`--limits-only --force`と能力照会に対応した新しい収集器が必要。
旧収集器は未知の引数を無視して履歴処理を始めるため、ヘルプ照会も含めて実行しない。
新しい収集器では、Paseo側で無効なnativeプロファイルも読めるが、providerの有効化、
履歴・SQLite・アーカイブ処理、モデル呼び出し、認証情報の更新・コピーは行わない。
キャッシュは私有の`~/.cache/agent-usage/account-limits/limits.json`へ分離する。

収集器の配備前に検証する場合は、ビルド済みbundleを明示する。

```sh
AGENT_USAGE_HOME=/tmp/account-quota-check \
  agent-usage --refresh --json --collector /absolute/path/to/dist/collector.cjs
```

収集器の配備やlaunchd変更は、dotfilesのapplyとは別に判断する。
認証切れ・無効化済みOAuthは`auth-required`、制限応答は`rate-limited`と表示する。
失敗時は最後に取得できた値と取得時刻を保持し、最新値へ置き換えない。
認証切れの場合は対象環境でサインインが必要で、認証情報を別環境へ自動コピーしない。
セッション別トークン・費用集計はこの入口の対象外。

## 削除候補

過去の作業で入ったまま使っていないもの。**削除は自動化しない。**
消すかどうかは手で判断する。

Homebrew と cargo 経由の候補は 2026-08-26 に削除を実行した。ここに残っているのは
npm グローバルと `~/.local/bin` に手で置いたものだけである。

### AI CLI
coderabbit (~/.local/bin), openclaw (npm),
@github/copilot (npm), @zed-industries/claude-code-acp (npm),
@zed-industries/codex-acp (npm), generator-code (npm)

### 重複
corepack (npm, mise の pnpm 管理と重複)

### 既存の Brew コピーの整理

native / mise に割り当てたツールは Brewfile に載せない。既存の Brew コピーは
apply だけでは削除しない。日常 CLI の移行対象は上の「mise 管理」にある。
先に代替の保存先・version・動作と復元資材を確認し、対象を承認してから削除する。
他の Brew パッケージの依存としての Python / OpenJDK / library は残す。

    HOMEBREW_NO_AUTOREMOVE=1 brew uninstall bun mise uv rustup deno go pnpm chezmoi herdr

`~/.bun/bin/bin` も、`BUN_INSTALL` の設定ミスでできた二重構造である。`.zshrc` を
直したので参照されなくなった。

    rm -rf ~/.bun/bin/bin

### Brewfile から外した cask（2026-08-27）

`swiftformat-for-xcode` / `dotnet-sdk` / `gcloud-cli` / `aquaskk` と、formula の
`switchaudio-osx` を外した。新マシンでは入らないが、現マシンには残っている。

**`gcloud-cli` は uninstall しないこと。** `google-cloud-sdk` と同一の cask なので、
消すと gcloud ごと失う。過去に一度そうなっている。

`switchaudio-osx` は `sketchybar/items/widgets/volume.lua` が、`aquaskk` は
`sketchybar/items/ime.lua` が参照している。新マシンでは本体が無い状態になる。

### Brewfile から外したもの

2026-08-27 に Brewfile から外した。新マシンでは入らないが、現マシンには残っている。
`nowplaying-cli` は macOS 26 で MediaRemote が塞がれていて動かない。残りは設定からも
スクリプトからも参照されず、他の formula の依存にもなっていない。

    brew uninstall nowplaying-cli hunk semgrep sevenzip chafa watchman \
      hyperfine mint lazydocker git-filter-repo automake mkcert cloudflared \
      cmake ninja zig protobuf pandoc ffmpeg

chezmoi の Brew コピーを除く前には `~/.local/bin/chezmoi --version` で native の実体を
確認する。install script を使う場合は `-b "$HOME/.local/bin"` を指定する。
既定の `./bin` に入っただけでは、native の恒久的な保存先を満たさない。

削除するときの例。

    npm uninstall -g corepack
    rm ~/.local/bin/coderabbit
