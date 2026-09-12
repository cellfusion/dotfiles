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
| Paseo プラグイン | `~/.local/share/paseo-plugins/pr-review/` のソース | `run_onchange_after_75-paseo-plugins.sh` |
| GitHub 用の鍵生成 | なし（Secure Enclave の状態を見る） | `run_onchange_after_80-secure-enclave-keys.sh` |
| AI 環境ディレクトリ | `~/.config/chezmoi/agent-config.json` の `environments` | `run_onchange_after_90-agent-envs.sh` |

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
apply の中で上の表の 11 本が番号順に実行される。

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
   描画される。Paseo の AI 環境、tier、provider、model は下の `agent-config.json` へ移す。
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

## Paseo agent config の移行

旧 `~/.config/chezmoi/private-data.toml` にある Paseo の環境・project rule・tier・model・provider の
設定は自動変換しない。秘密、credential、auth、history の値を公開 sample や報告へ写さず、利用者が
`$XDG_CONFIG_HOME/chezmoi/agent-config.json`（`XDG_CONFIG_HOME` 未設定時は
`$HOME/.config/chezmoi/agent-config.json`）へ手で移す。公開 schema と sample は
`~/.local/share/agent-config/agent-config.schema.json` と
`~/.local/share/agent-config/agent-config.sample.json` で確認する。

移行時は次の対応にする。

1. environment の定義は `environments` に移し、`providers` はその environment で eligible な
   provider family の一覧だけにする。root `providers` には全 family の base record を持たせ、
   environment 側の eligibility だけを理由に base record を省略しない。
2. project rule は `projectRouting.rules` に移し、旧設定の優先順のまま上から並べる。明示した
   `--environment` が最優先で、無ければ最初に一致した rule、どれにも一致しなければ
   `defaults.environment` を使う。
3. tier は `tiers` または対象 environment の `tiers` に移す。environment tier があればそれを使い、
   無ければ共通 tier を使う。role の tier と候補の順序も保持する。
4. model と provider の優先順位は各 tier の `candidates` 配列の順序にする。先頭から provider の
   availability、`auto` mode、model、thinking option を確認し、最初に成立した候補を使う。
   `fast` は入力時だけ `light` に正規化されるため、正本には書かない。
5. `claude` と `codex` 以外の provider family は、Paseo の provider record key に現れる literal な
   family 名をそのまま root `providers` の key にする。v1 ではその family の `setup` は `null`、
   `featureAllowlist` は `{}` とし、directory、env、symlink、config は materialize しない。

実 target は直接変更せず、まず `~/.paseo/config.json` の mode 0600 の copy を絶対 path で用意する。
その copy に対して次の順序で確認する。`generate-paseo-config resolve` は正本、project、role、
provenance、匿名 availability snapshot を検査して候補を解決するだけで target は書かない。
global option は subcommand より前に置くため、実際の呼び出しは
`generate-paseo-config --input <absolute-input> --paseo-config <absolute-copy> resolve \
--project <absolute-project> --role <role> --provenance <provenance> --snapshot <absolute-snapshot>` とする。

次に `generate-paseo-config --diff` で copy に対する managed projection だけを確認する。明示的な
copy path を付けた実際の呼び出しは
`generate-paseo-config --input <absolute-input> --paseo-config <absolute-copy> --diff` とする。
差分が意図どおりなら、同じ明示的な copy path に対して試行 write を行う。
`generate-paseo-config --input <absolute-input> --paseo-config <absolute-copy>` の後、
`generate-paseo-config --check` を
`generate-paseo-config --input <absolute-input> --paseo-config <absolute-copy> --check` として実行する。
`--check` が 0 になることを確認するまで実 target へ write しない。0 は一致または成功、1 は差分、
2 は入力・path・schema などの不備、4 は候補が尽きたことを表す。`--diff` と `--check` は target を
書き換えない。

copy の `--check` が 0 になった後、利用者が内容を確認して明示承認した場合だけ、同じ正本に対して
flags なしの `generate-paseo-config --input <absolute-input> --paseo-config <absolute-target>` を
実 target へ実行する。実 target の path を省略して既定値へ向ける手順は書かない。legacy との衝突、
stale な provider・profile・directory は自動削除しない。auth と history の有無を利用者が確認した
うえで、必要な処理を手で行う。最後の `chezmoi apply` も利用者の明示許可がある場合だけ実行する。

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

paseo。複数のコーディングエージェントを走らせる macOS アプリで、`multi-agent-development`
スキルが CLI の `paseo` を PATH に置くことを前提にする。アプリは https://paseo.sh/download
から入れ、`/Applications/Paseo.app` に置く。CLI はアプリに同梱された
`/Applications/Paseo.app/Contents/Resources/bin/paseo` で、`~/.local/bin/paseo` を
そこへの symlink にする。前提バージョンは 0.6.1 以上で、2026-09-02 時点の現マシンは 0.7.0
である。daemon はアプリが持つので、別に入れるものは無い。

`multi-agent-development` スキルの backend は Paseo MCP と native subagent の 2 つである。
親エージェントは run の開始時に Paseo MCP へ届くかを確かめ、届くときは Paseo MCP で子を
起動する。届かないときだけ native subagent へ fallback する。開始済みの子が失敗しても
別 backend へ自動で切り替えない。

Paseo MCP で起動した子は CLI からも見える。`paseo ls` が一覧と状態を出し、
`paseo inspect <agent-id>` が 1 つの子の詳細を出し、`paseo logs <agent-id>` が活動履歴を
出し、`paseo wait <agent-id>` が idle になるまで待つ。止めるときは `paseo stop <agent-id>`
が実行中の子に割り込み、`paseo delete <agent-id>` が割り込んでから子を消す。
native subagent で起動した子は Paseo の一覧に現れないので、親は run ディレクトリの
`state.json` だけで状態を判断する。

`~/.agents/skills/subagent-driven-development/scripts/` のうち、MAD の `implement` recipe で
親が呼ぶのは `sdd-workspace`、`task-waves`、`task-brief`、`review-package` である。
`run-registry` と `agent-backend` は、親が起動した子が呼ぶ。どのスクリプトを誰が呼ぶかと、
実行基盤の呼び出し手順は `multi-agent-development` スキルの「implement の実行基盤」にある。

`task-worktree` と `sdd-run` は `implement` の子の手順に入らない。worktree を作るのは親であり、
波の進行と裁定は親が共通契約の state で管理するためである。`sdd-task` は MAD を通さずに 1 task を
headless で回すときの入口であり、`implement` の子は使わない。この 3 つと Workflow の定義は、
MAD を通さない経路のために残してある。撤去したのは旧 MAD の shell runner とレシピだけである。

`implement` と `spike` は node ごとに worktree を作る。作った workspace は run ディレクトリ
直下の `workspaces.json` が持つ。run を終えたら `mcp__paseo__archive_workspace`（CLI では
`paseo workspace archive <id>`）で片付ける。archive に失敗した workspace がある run
ディレクトリは、台帳を失うと対応が追えなくなるため消さない。

実 backend で 1 度通す手順は `tests/manual/mad-orchestration-smoke.sh` にある。
`research` レシピの 3 子並列、統合前の親の gate、統合、観測方法、停止方法を扱う。
実機と課金を伴うので `tests/run-tests.sh` の対象には入れていない。
`--dry-run` で手順だけを読める。

旧 asset の削除へ進む前に、`tests/manual/mad-representative-run.sh` で Paseo の代表
MAD run を 1 回通す。`--run` は外側から `MAD_REPRESENTATIVE_RUN_APPROVED=1` を
明示したときだけ discovery、launch、create、plan、implement、review、fix を実行し、
成功時に `$PASEO_MIGRATION_EVIDENCE_DIR/representative-decision.txt` へ
`approved-success` を atomic に記録する。未承認または途中失敗なら `DECISION_REQUEST_PATH`
へ decision request を残し、後続 phase と削除を行わない。

実機を使わず保存済み証跡を検査する場合は、次の verify-only 経路を使う。これは
承認変数を読まず、adapter を呼ばない。

    bash tests/test-paseo-mad.sh
    bash tests/manual/mad-representative-run.sh --verify-only \
      --evidence-dir "$PWD/tests/fixtures/agent-config/mad/representative-ok"

fixture の mode は Git が保存しないため、単体で検査するときは `find` で列挙した証跡を
`chmod 600` にしてから実行する。証跡には credential、auth/history、raw response、
remote URL を入れない。

### Paseo プラグイン pr-review

サイドバーの「PR レビュー」からプロジェクトと PR を選ぶと、worktree の workspace を
1 つ作って `/pr-review <番号>` の agent を起動する。PR が `CLAUDE.md`、`CLAUDE.local.md`、
`AGENTS.md` のいずれかの名前のファイルか、`.claude` か `.agents` の配下を、リポジトリの
どの階層であれ変更している場合は、base から分岐した worktree に切り替え、workspace の
title の先頭に `[base]` を付ける。レビューする agent が PR 側の指示を受け取らない
ようにするためである。

プラグインは trusted・unsandboxed なコードである。daemon 側のコードは daemon マシンの
ファイル・プロセス・認証情報・ネットワークに触れられる。有効化は手で行う。

1. Paseo の Settings → Plugins → Enable plugins を開く
2. `chezmoi apply` を実行する。`run_onchange_after_75-paseo-plugins.sh` が
   `paseo plugin install` を実行する
3. `paseo plugin ls` で `pr-review` が `running` になっていることを確認する

Enable plugins より先に `chezmoi apply` を実行した場合、`run_onchange_after_75-paseo-plugins.sh`
は「プラグインが無効なので飛ばす」で終わり、chezmoi はそれを実行済みとして記録する。
以後スクリプトの内容が変わるまで再実行されないので、有効にした後で次を手で 1 回実行する。

```bash
paseo plugin install "$HOME/.local/share/paseo-plugins/pr-review"
```

レビューに使う provider は、Paseo daemon の `process.env.AGENT_ENV` に応じて選ぶ。
`default` なら無印 provider、それ以外なら `claude-<AGENT_ENV>` を優先し、無ければ
`claude` にフォールバックする。環境名付き provider は `~/.paseo/config.json` の
`agents.providers` に存在するものだけを使う。

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
