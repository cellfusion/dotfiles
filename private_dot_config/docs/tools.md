# ツール一覧

使っているツールと、その導入経路をまとめる。マニフェストの実体は
`~/.config/install/` にあり、chezmoi のソースは
`private_dot_config/install/` にある。

## 管理方法

| 経路 | マニフェスト | 実行するスクリプト |
|---|---|---|
| Homebrew 本体 | なし | `run_onchange_after_00-homebrew.sh` |
| Homebrew | `~/.config/install/Brewfile`、`~/.config/install/third-party.txt` | `run_onchange_after_10-brew.sh` |
| native installer（chezmoi・ランタイム） | なし（スクリプトに直書き） | `run_onchange_after_20-runtimes.sh` |
| mise | `~/.config/mise/config.toml` | `run_onchange_after_30-mise.sh` |
| native installer（AI CLI） | なし（スクリプトに直書き） | `run_onchange_after_40-ai-clis.sh` |
| npm | `~/.config/install/npm-globals.txt` | `run_onchange_after_50-npm-globals.sh` |
| cargo | `~/.config/install/cargo-globals.txt` | `run_onchange_after_60-cargo.sh` |
| ビルド・サービス登録 | sketchybar helper のソース | `run_onchange_after_70-macos-services.sh` |
| GitHub 用の鍵生成 | なし（Secure Enclave の状態を見る） | `run_onchange_after_80-secure-enclave-keys.sh` |
| AI 環境ディレクトリ | `~/.config/chezmoi/private-data.toml` の `[[data.environments]]` | `run_onchange_after_90-agent-envs.sh` |

マニフェストを持つスクリプトは、そのハッシュを埋め込んでいる。マニフェストを
書き換えたときだけ `chezmoi apply` で走る。マニフェストを持たない 4 本
（00 / 20 / 40 / 80）は、対象が未導入のときだけ入れる。

実行するのはインストールだけで、既に入っているものの upgrade は行わない。
`brew bundle` は既定で outdated な formula もまとめて upgrade するため、
`--no-upgrade` を付けている。更新したいときは `brew upgrade` を手で回す。

手で回すこともできる。

    brew bundle --file ~/.config/install/Brewfile --no-upgrade

non-official tap の formula は Brewfile に載せず `~/.config/install/third-party.txt` に
分けてある。fully-qualified 名で入れると tap と trust が自動で付くため、Homebrew 6 の
tap trust に止められない。手で回すなら次のとおり。

    xargs -n1 brew install < ~/.config/install/third-party.txt

## 新マシンでの手順

素の macOS の `/usr/bin/git` は Xcode Command Line Tools の stub である。実行すると
GUI のインストールダイアログが出て、入っていなければ `chezmoi init` の clone が
そこで失敗する。先に本体を入れておく。

    xcode-select --install

    sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply cellfusion

これ 1 本で終わる。chezmoi が入り、リポジトリが clone され、apply が走る。
apply の中で上の表の 10 本が番号順に実行される。

この 1 本目の chezmoi は install script の既定の BINDIR、つまり実行したディレクトリの
`./bin` に置かれる。PATH には載らない。恒久的な chezmoi は apply の中で 20-runtimes が
`~/.local/bin` に入れるので、apply が終わったら `./bin` は消してよい。

各スクリプトは前提が無ければ自分で入れ、入れられなければ非ゼロで落ちる。chezmoi は
非ゼロで終わったスクリプトを実行済みとして記録しないため、落ちたところから次の
apply で再開する。飛ばされて黙って記録される状態にはならない。

途中で落ちたら、表示された原因を直してから `chezmoi apply` をもう一度回す。

Homebrew の導入と cask のインストールで、sudo のパスワードを複数回聞かれる。

## apply 後に手でやること

自動化できないものが 5 つある。

1. **アクセシビリティ権限の付与**（yabai と skhd）。システム設定 → プライバシーと
   セキュリティ → アクセシビリティ で許可する。付与するまでウィンドウ操作と
   ホットキーは効かない
2. **`~/.config/chezmoi/private-data.toml` の配置**。AI 環境の定義（`[[data.environments]]`）、
   Cloudflare のアカウント ID、AWS プロファイル、1Password のパス、再汚染テストの禁止語を
   持つ。無くても apply は通り、各テンプレートは既定値で描画される。AI 環境については
   「claude と codex を持つ `default` 環境 1 つ」が既定値になる
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

sketchybar のカレンダー表示を使う場合は、フルディスクアクセスの付与も要る。
システム設定 → プライバシーとセキュリティ → フルディスクアクセス に
`~/.config/sketchybar/helpers/event_providers/calendar_events/bin/calendar_events`
を足す。makefile が ad-hoc 署名を打っているので、付与は再ビルドをまたいで保持される。

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
| eza | 高機能 ls |
| jq | JSON 処理 |
| television | ファジーファインダー |
| zoxide | 賢い cd |
| herdr | ターミナルマルチプレクサ |
| opencode | AI コーディングエージェント |

## 開発ツール

mise / bun / uv / rustup / chezmoi は native installer、go は mise が管理する。
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
未導入のときだけ入れて、更新は各ツールに任せる。chezmoi / mise / bun / uv / rustup は
`run_onchange_after_20-runtimes.sh` が、claude / codex は
`run_onchange_after_40-ai-clis.sh` が入れる。

chezmoi の install script の既定の BINDIR は `./bin`（実行時のカレントディレクトリ
配下）である。`-b` を渡さないと、`.zshenv` が PATH に載せる `~/.local/bin` には入らない。

| ツール | 導入 | 理由 |
|---|---|---|
| chezmoi | `sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"` | 新マシンの起点になる。20-runtimes が未導入のときだけ入れる。brew 版を併せて入れると 2 本になる |
| mise | `curl https://mise.run \| sh` | Homebrew 版は別ビルドで、公式の最適化されたリリースバイナリではない |
| bun | `curl -fsSL https://bun.sh/install \| bash` | `bun upgrade` で自己更新する |
| uv | `curl -LsSf https://astral.sh/uv/install.sh \| sh` | `uv self update` で自己更新する |
| rustup | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh -s -- -y --no-modify-path` | brew 版は keg-only で toolchain を持たない |
| claude | `curl -fsSL https://claude.ai/install.sh \| bash` | 自己更新を持つ |
| codex | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | 自己更新を持つ |
| opencode | Homebrew（`anomalyco/tap/opencode`） | 自己更新を持たないので brew に置く |

claude と codex を brew に寄せない理由はもう 1 つある。Homebrew の `claude-code`
cask は stable チャネルを追う一方、アプリ内の更新通知は latest チャネルを見るため、
cask に未着のバージョンを「更新あり」と表示する状態が起きる。

rustup に `--no-modify-path` を渡すのは、PATH の管理を `~/.config/zsh/.zshenv` と
`.chezmoitemplates/install/preamble` に一本化するためである。rustup 自身に shell の
設定ファイルを書き換えさせない。

## mise 管理

node / python / java / pnpm / deno / go は mise で管理し、Brewfile には載せない。

| ツール | バージョン | 用途 |
|---|---|---|
| python | 3.13 | Python ランタイム |
| node | 22.19 | Node.js ランタイム |
| pnpm | 10.16.1 | Node.js パッケージマネージャ |
| java | 25 | JVM ランタイム |
| deno | 2.5 | Deno ランタイム |
| go | 1.26 | Go ランタイム |

## npm グローバル

| ツール | 用途 |
|---|---|
| wrangler | Cloudflare Workers の CLI |
| firebase-tools | Firebase CLI |
| mcp-hub | MCP サーバーのハブ |

## cargo 管理

現在は 1 つも無い。マニフェスト `~/.config/install/cargo-globals.txt` は
コメント行だけで、`run_onchange_after_60-cargo.sh` は何も入れない。

## 手動インストール

マニフェストに載せていないが使っているもの。

AquaSKK。2026-08-27 に Brewfile から外した。辞書は `~/.config/skk` にあり、chezmoi の
管理外である。

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

### brew と native installer の二重インストール

`mise` / `bun` / `uv` / `rustup` は Homebrew と native installer の両方で入っており、
brew 版は使われていない。Brewfile からは外したので新マシンでは入らないが、現マシンの
brew 版は残っている。

    brew uninstall mise bun uv rustup

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

**`chezmoi` はこのコマンドに含めていない。** 現マシンの chezmoi は brew 版しか無く
（`~/.local/bin/chezmoi` は存在しない）、そのまま消すと chezmoi が使えなくなる。
先に native installer で入れ、`which chezmoi` が `~/.local/bin/chezmoi` を指すことを
確かめてから brew 版を消す。`-b` を落とすと既定の `./bin` に入り、PATH に載らない。

    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    hash -r
    which chezmoi
    brew uninstall chezmoi

削除するときの例。

    npm uninstall -g corepack
    rm ~/.local/bin/coderabbit
