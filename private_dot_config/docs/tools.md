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
そろえる。リポジトリ側では `agent-config.sample.json` と
`tests/fixtures/agent-config/` の各ファイルもそろえる。
`tests/test-codex-rules.sh` が、この一致を検証する。

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
2. project rule は `projectRouting.rules` に移し、旧設定の優先順のまま上から並べる。environment は
   4 段で決まる。1 段目は明示した `--environment` である。2 段目は親の AI 環境名である。
   3 段目は最初に一致した rule である。どれにも当たらなければ `defaults.environment` を使う。
   親の AI 環境名は `AGENT_ENV` だけを読む。`AGENT_ENV_SESSION` は参照しない。`AGENT_ENV` が
   未設定または空文字なら 2 段目を飛ばす。
   親の AI 環境名が `environments` に無い名前のときは、`resolve` が終了コード 2 で終わり
   stdout に JSON を出さない。
3. 候補は `selection` の 16 枠に移す。枠の key は `<duty>.<complexity>` であり、duty は
   `author`、`implement`、`review`、`synthesize`、複雑度は `simple`、`routine`、`complex`、`critical` である。
   16 枠すべてを必須とする。環境ごとの上書きは `environments.<環境>.selection` に枠単位で書き、
   書かなかった枠は共通の `selection` を使う。role の `duty` と候補の順序も保持する。
4. model と provider の優先順位は各枠の `candidates` 配列の順序にする。先頭から provider の
   `backends` に `paseo` が含まれること、availability、`auto` mode、model、thinking option を確認し、
   最初に成立した候補を使う。
5. `claude` と `codex` 以外の provider family は、Paseo の provider record key に現れる literal な
   family 名をそのまま root `providers` の key にする。v1 ではその family の `setup` は `null`、
   `featureAllowlist` は `{}` とし、directory、env、symlink、config は materialize しない。

実 target は直接変更せず、まず `~/.paseo/config.json` の mode 0600 の copy を絶対 path で用意する。
この移行手順でも、先に次の絶対 path を設定する。

```bash
MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"
MAD_SHARE="${MAD_SHARE:-$HOME/.local/share/agent-config}"
AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"
MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter"
MAD_VALIDATE="$MAD_SCRIPTS/manual-orchestration-validate"
MAD_PLAN_VALIDATE="$MAD_SCRIPTS/paseo-plan-dependency-validate"
MAD_REVIEW_BUNDLE="$MAD_SCRIPTS/review-bundle"
MAD_GENERATOR="${MAD_GENERATOR:-$HOME/.local/bin/agent-config}"
```

`MAD_SCRIPTS`配下の4 scriptは`PATH`に依存しない。`AGENT_CONFIG`は`~/.local/share/agent-config`ではなく、chezmoiの正本を指す。
`tests/manual/paseo-unit-gate.sh` はこの repository の checkout 専用である。他のrepositoryでは
そのrepository固有のgateを使い、無ければこのmigration gateを実行しない。

その copy に対して次の順序で確認する。`"$MAD_GENERATOR" resolve` は正本、project、role、
provenance、匿名 availability snapshot を検査して候補を解決するだけで target は書かない。
global option は subcommand より前に置くため、実際の呼び出しは
`"$MAD_GENERATOR" --input <absolute-input> --paseo-config <absolute-copy> resolve \
--project <absolute-project> --role <role> --provenance <provenance> --snapshot <absolute-snapshot>` とする。

次に `"$MAD_GENERATOR" write-paseo --diff` で copy に対する managed projection だけを確認する。明示的な
copy path を付けた実際の呼び出しは
`"$MAD_GENERATOR" --input <absolute-input> --paseo-config <absolute-copy> write-paseo --diff` とする。
差分が意図どおりなら、同じ明示的な copy path に対して試行 write を行う。
`"$MAD_GENERATOR" --input <absolute-input> --paseo-config <absolute-copy> write-paseo` の後、
`"$MAD_GENERATOR" write-paseo --check` を
`"$MAD_GENERATOR" --input <absolute-input> --paseo-config <absolute-copy> write-paseo --check` として実行する。
`--check` が 0 になることを確認するまで実 target へ write しない。0 は一致または成功、1 は差分、
2 は入力・path・schema などの不備、4 は候補が尽きたことを表す。`--diff` と `--check` は target を
書き換えない。

copy の `--check` が 0 になった後、利用者が内容を確認して明示承認した場合だけ、同じ正本に対して
flags なしの `"$MAD_GENERATOR" --input <absolute-input> --paseo-config <absolute-target> write-paseo` を
実 target へ実行する。実 target の path を省略して既定値へ向ける手順は書かない。legacy との衝突、
stale な provider・directory は自動削除しない。auth と history の有無を利用者が確認した
うえで、必要な処理を手で行う。最後の `chezmoi apply` も利用者の明示許可がある場合だけ実行する。

## agent で AI 環境を指定して起動する

`~/.local/bin/agent` は AI 環境を指定して AI CLI を起動するラッパーである。

    agent --provider=<provider-id> [引数...]

`<provider-id>` は `~/.config/chezmoi/agent-config.json` から materialize した id で、
Paseo の provider record の key と同じ名前空間にある。既定環境の provider id は
provider family の名前そのもの（`claude`）、それ以外の環境は `<family>-<環境名>`
（`claude-lab`）である。

ラッパーは `AGENT_ENV` に環境名を設定し、family の `setup.configDirectoryEnv` の key
（`CLAUDE_CONFIG_DIR`、`CODEX_HOME`）へ `setup.directoryPattern` を展開した絶対 path を
設定してから、family と同じ名前のコマンドを `exec` で起動する。`setup` が `null` の
family（`opencode`、`pi`）では設定ディレクトリの変数を設定しない。自分のプロセスを
残さないので、`paseo provider diagnostic` がコマンドを起動して version と auth を読む
経路でも使える。

正本は `AGENT_CONFIG`（未設定なら `${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json`）
から読む。`--provider` が無い、値が空、重複している、正本に無い id を渡した、正本を
読めない、のいずれでも終了コード 2 で終わり、使える provider id の一覧を stderr に出す。
`--` 以降の引数は family のコマンドへそのまま渡す。

zsh は解決できた AI 環境の変数だけを設定する。`AGENT_ENV` も `HERDR_SESSION` も
定義済みの環境名でないシェルでは `claude` と `codex` が関数で塞がれるので、その場合は
このラッパーで起動する。

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

`multi-agent-development` の backend は Paseo MCP だけである。Paseo MCP が利用できないときは
run を開始せず、利用者へ状況を報告する。開始済みの子が失敗しても別 backend へ切り替えない。

Paseo MCP で起動した子は CLI からも見える。`paseo ls` が一覧と状態を出し、
`paseo inspect <agent-id>` が 1 つの子の詳細を出し、`paseo logs <agent-id>` が活動履歴を
出す。MAD 親は raw activity を受け取らず、adapter の `wait-agent --child-ref <safe-id> --timeout <seconds>`
だけを通じて `paseo wait <agent-id> --timeout <seconds> --json` を一回実行し、検証済みの
`idle`、`timeout`、`error` status だけを受け取る。止めるときは `paseo stop <agent-id>` が
実行中の子に割り込み、`paseo delete <agent-id>` が割り込んでから子を消す。

実行は `"$MAD_ADAPTER"` の `list-providers`、provider ごとの `list-models`、0600 の
availability snapshot、`"$MAD_GENERATOR" resolve`、0600 の `mcp-create.json`、
`"$MAD_VALIDATE" --prepare-create`、親による `mcp__paseo__create_agent` 一回、
accepted childRef に対する `"$MAD_ADAPTER" wait-agent` 一回の順に進める。
create の transport は公式 MCP tool だけであり、adapter は create の subcommand を持たない。
Paseo CLI の `run` は `settings.features` を渡す option を持たないので、CLI を create に使わない。
`--prepare-create` は request と attempt state と call log を検証してから、0600 の
`mcp-create.prepared` を `O_EXCL` で作る。marker を取れた呼び出しだけが create を呼べるので、
2 つの親が同時に検証を通っても create は一回で止まる。
wait の raw response は adapter が `{status}` へ縮約し、attempt には 0600 の `wait-evidence.json` と
sanitized call log だけを残す。各 JSON 成果物は run の attempt directory にだけ置く。
snapshot と launch と `mcp-create.json` が検証できない場合、及び marker を取れない場合、create を呼ばない。

review/fix は task ごとに `max_rounds` を 4（round 0 の初回 review、round 1 から 3 の fix/re-review）へ固定する。
review/fix child を create する前に `"$MAD_VALIDATE" --prepare-review` を通し、
同じ task の scope file と admission marker を使う。scope 外の重要事項は observations に保持し、
review/fix 中に新しい fix/review や hotfix node を起動しない。最終 gate で一つの decision request に
まとめてユーザーへ確認し、scope 拡張は新しい run として開始する。
observations は `--write-review-observations` で atomic 0600 に保存し、
`--check-review-observations` で最終 gate 前に検査する。

レビュー役へ渡す review package は `"$MAD_REVIEW_BUNDLE"` が組み立て、attempt の
`review-package.diff` に mode 0600 で置く。1 行目の `# Review package: <base>..<head>` は
40 桁の sha 2 つであり、レビュー役が正しい範囲を見たかを機械的に確認する手掛かりになる。
レビュー結果を採用する前に `--check-review-package` で範囲を照合し、
`--check-review-verdict` で verdict と findings の整合を確かめる。
round 0 の結果を採用したら `cannotVerify` を 1 件ずつ解消して
`<run-dir>/review-cannot-verify/<task>.json` に記録し、`--open-review-findings` で
`<run-dir>/review-open-findings/<task>-round-1.json` を作り、
`--check-review-cannot-verify` で記録と一覧の対応を検査する。
round `N` の再レビューの結果からは `--advance-review-findings` で round `N+1` の一覧を作る。
未解決の指摘を親が散文で引き継がない。

`--dry-run` は保存済み fixture だけを使い、実 MCP の create と `chezmoi apply` を実行しない。
実 create は利用者が代表 run を明示承認した場合だけ行う。rollback は create 前なら request と
snapshot を破棄し、create 後なら Paseo の子を archive して run の state に判断を残す。keybindings
はこの移行で変更しないため `private_dot_config/docs/keybindings.md` を更新しない。

`implement` と `spike` は node ごとに worktree を作る。作った workspace は run ディレクトリ
直下の `workspaces.json` が持つ。run を終えたら `mcp__paseo__archive_workspace`（CLI では
`paseo workspace archive <id>`）で片付ける。archive に失敗した workspace がある run
ディレクトリは、台帳を失うと対応が追えなくなるため消さない。

実Paseoを起動する代表 MAD run は、待ち時間と API 課金を避けるため廃止している。
`tests/manual/mad-representative-run.sh` は `--verify-only` だけを受け付け、保存済みの
匿名 fixture を検査する。実Paseo、MCP、provider CLI、network、課金対象の child は起動しない。

保存済み証跡の検査は次の verify-only 経路を使う。これは承認変数を読まず、adapterを呼ばない。

    bash tests/test-paseo-mad.sh
    bash tests/manual/mad-representative-run.sh --verify-only \
      --evidence-dir "$PWD/tests/fixtures/agent-config/mad/representative-ok"

fixture の handoff は `/fixture/*.json` という匿名 placeholder を使い、verify-only が
一時 directory に 0600 の regular file として解決する。`wait-evidence.json` は `{status}` だけを持ち、
raw wait response や activity history は証跡に入れない。fixture の mode は Git が保存しない
ため、単体で別の証跡を検査するときは `find` で列挙した証跡を `chmod 600` にしてから
実行する。証跡には credential、auth/history、raw response、remote URL を入れない。

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
