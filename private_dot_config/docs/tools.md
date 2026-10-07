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
| 旧 Paseo managed profiles の回収 | agent-config の回収処理のソース | `run_onchange_after_91-paseo-managed-profiles.sh` |

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
2. project rule は `projectRouting.rules` に移し、旧設定の優先順のまま上から並べる。`match.path` は
   canonical directory の完全一致、`match.remote` は同じ origin repository を持つ clone の一致である。
   Organization / group 単位では `match.remoteNamespace` に `github.com/example-org` や
   `gitlab.example/group/subgroup` を指定する。これは segment boundary を含む namespace prefix であり、
   glob や単純な文字列 prefix ではない。`match.gitRepository` には存在する canonical absolute Git
   directory を指定する。起動 cwd と rule の
   `git rev-parse --path-format=absolute --git-common-dir` を比較するため、main checkout、linked worktree、
   それぞれの subdirectory が同じ rule に一致し、同じ remote の別 clone は一致しない。複数 matcher は
   AND であり、最初に一致した rule を使う。environment は明示 `--environment`、親 `AGENT_ENV`、rule、
   `defaults.environment` の順で決まる。未知の explicit/parent environment は終了コード 2 で拒否し、
   stdout に JSON を出さない。`AGENT_ENV_SESSION` は参照しない。
3. 候補は `selection` の 16 枠に移す。枠の key は `<duty>.<complexity>` であり、duty は
   `author`、`implement`、`review`、`synthesize`、複雑度は `simple`、`routine`、`complex`、`critical` である。
   16 枠すべてを必須とする。環境ごとの上書きは `environments.<環境>.selection` に枠単位で書き、
   書かなかった枠は共通の `selection` を使う。role の `duty` と候補の順序も保持する。
4. model と provider の優先順位は各枠の `candidates` 配列の順序にする。先頭から provider の
   `backends` に `paseo` が含まれること、availability、`auto` mode、model、thinking option を確認し、
   最初に成立した候補を使う。これは availability fallback であり、品質不足時の再試行ではない。
5. 品質不足時の model・effort の切り替えは、必要な duty と complexity にだけ
   `attemptPolicy.<duty>.<complexity>.levels`を追加する。これは保持しているPaseo設定の選択方針であり、
   通常のOMP内部委譲やHerdr起動をPaseoへ切り替える指示ではない。
6. `claude`、`codex`、`pi`、`omp` 以外の provider family は、Paseo の provider record key に現れる
   literal な family 名をそのまま root `providers` の key にする。`pi` は
   `PI_CODING_AGENT_DIR` を `$HOME/.pi/agent`（非 primary は
   `$HOME/.pi/agent-<environment>`）へ materialize し、`featureAllowlist` は `{}` とする。
   OMP は `setup: null`、`environmentVariable: \"OMP_PROFILE\"` とし、選択 environment と同名の
   named profile を使う。その他の family は `setup` を `null` とし、directory、symlink、config を
   materialize しない。

実 target は直接変更せず、まず `~/.paseo/config.json` の mode 0600 の copy を絶対 path で用意する。
この移行手順でも、先に次の絶対 path を設定する。

```bash
MAD_GENERATOR="${MAD_GENERATOR:-$HOME/.local/bin/agent-config}"
AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"
```

`AGENT_CONFIG`は`~/.local/share/agent-config`ではなく、chezmoiの正本を指す。

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

`~/.local/bin/agent` は `~/.config/chezmoi/agent-config.json` を検査し、環境変数を設定して
family と同名の AI CLI を `exec` する。

```text
agent --provider=<provider-id> [--] [args...]
agent --family=<family> [--environment=<environment>] [--] [args...]
```

設定ファイル（`AGENT_CONFIG` を指定した場合はその path）が無ければ、`--family` または
`--provider` の値をそのまま CLI 名として起動する。引数と既存の環境変数は引き継ぎ、
`AGENT_ENV` や隔離用の変数は追加・変更しない。この場合、`--environment` は解決できないため
終了コード 2 で失敗する。設定ファイルが不正、または未存在以外の理由で読めない場合も停止する。

`--provider` は既存の明示起動である。`<provider-id>` は Paseo provider record と同じ名前空間を使い、
既定環境は family 名（`claude`）、それ以外は `<family>-<environment>`（`claude-lab`）である。

`--family` は cwd-aware 起動で、環境を explicit `--environment`、親 `AGENT_ENV`、最初に一致した
`projectRouting.rules` rule、`defaults.environment` の順に選ぶ。たとえば
`agent --family=codex --environment=pxgrid` は親や cwd rule と異なる `pxgrid` への明示切替を許す。
ただし、その environment の `providers` に `codex` が無ければ起動しない。`--provider` と
`--family` は併用できず、`--environment` は `--family` とだけ併用できる。

`match.gitRepository` は Git common directory を比較するため、登録した checkout の linked worktree と
その subdirectory でも同じ environment を選ぶ。`match.remoteNamespace` は
`github.com/example-org` のような正規化済み namespace を使い、その配下の全 repository に一致する。
Git 外 cwd、無関係 repository、どの rule にも一致しない cwd は default environment を使う。
Unknown environment、invalid config、ineligible family では default へ落とさず終了コード 2 で失敗する。

正常時は `AGENT_ENV` と family の隔離変数を設定する。Claude は `CLAUDE_CONFIG_DIR`、Codex は
`CODEX_HOME`、Pi は `PI_CODING_AGENT_DIR` を使う。OMP は `OMP_PROFILE=<environment>` を使う。
OMP named profile は profile ごとの native config、session、`agent.db` を持ち、
`PI_CODING_AGENT_DIR` を無視する。一つの profile には一方の account だけを login し、OMP の
複数-account rotation で A/B を混ぜない。

zsh の bare `claude`、`codex`、`pi`、`omp` は `agent --family=<family>` へ送る。
`pi update` は launcher からグローバル設定の `mise upgrade npm:@earendil-works/pi-coding-agent`、
`codex update` は native CLI へ送る。`command claude`、absolute executable path、
zsh 設定を読まない process は family wrapper を bypass する。

Orca terminal と Project Quick Command からは、たとえば次を実行する。

```text
agent --family=codex
orca terminal create --worktree active --command "agent --family codex"
```

Orca 1.4.215 には shipped per-project launch profile がない。Agent picker、
`worktree create --agent`、scheduled automation provider、orchestration worker は project rule から
family/provider を自動選択しない。これらでは environment-specific provider id を明示する。
Materialized provider と wrapper は `AGENT_ENV` を子へ継承するため、明示 `--environment` がない
child resolve は親環境を保持する。Project-scoped Quick Command は Orca UI 設定であり、この
repository から自動配布しない。

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

`/etc/zshenv` で `ZDOTDIR` を無条件に上書きしない。Orca の準備完了通知用ラッパーが
読まれなくなり、起動が15秒のタイムアウトまで待たされる。既存マシンに残っている
代入は管理者権限で除く。`/etc/paths.d/dotnet-cli-tools` の `~/.dotnet/tools` も
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
| GitHub release | worktrunk（`wt`）、OpenCode |
| Cargo | eza（macOS 向けの配布バイナリがないため rustup の toolchain でビルド） |
| npm | Pi、wrangler、firebase-tools、mcp-hub |

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
旧 npm グローバルのマニフェストと専用 installer は廃止し、Pi の更新も mise に集約する。

## cargo 管理

直接 cargo install するツールは無い。マニフェスト `~/.config/install/cargo-globals.txt` は
コメント行だけで、`run_onchange_after_60-cargo.sh` は何も入れない。eza は mise の Cargo backend が管理する。

## 技術文章レビュー

`technical-writing-review` は、GitHub の PR 本文・コメント、README、設計説明、手順を
書く・推敲する・レビューするときに使う。日本語を中心に、可読性、読者に必要な説明、
構成と図表を3つの読み取り専用サブエージェントで並列に確認し、親が指摘を統合する。
コード差分の正しさを調べる `pr-review` とは別用途である。

Codex 向けの `~/.agents/skills`、Claude Code の `~/.config/claude/skills`、
OpenCode の `~/.config/opencode/skills` に、同じ本体とレビュー用 references を配る。
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

Paseoは既存の補助環境として残すが、通常の開発スキルの実行前提にはしない。
Paseo本体や他プラグインは、この移行で停止・アンインストールしない。

## Herdr・OMPの開発ワークフロー

メインの実行環境はmainMBP。GhosttyでHerdrを開き、OMP、Neovim、LazyGit、Tuicrを使う。
subMBPはGhostty／Herdr／Tailscaleを使い、`herdr --remote`でmainMBP側へ接続する。
Android端末にはMoshiを使う。接続元へ認証や履歴を複製しない。

- メイン作業はdefaultブランチからHerdrのworktree＋workspaceを作成する。
- 通常の委譲はOMP内で済ませる。
- 独立対話、ユーザー介入、別CLIエージェントにはHerdrの別paneを使う。
- 書き込み分離だけならWorktrunkで子worktreeを作り、Herdrには表示しない。
- worktreeの所有権、統合状態、終了手順は[worktrees.md](worktrees.md)に従う。

`task-routing`と`multi-agent-development`はこの区分を使う。Orca専用スキルはOrcaを
明示した作業だけに使い、通常の作業分割やhandoffからOrcaを起動しない。
エージェントの権限やmodel設定を、端末を分けるためだけに変更しない。

native roleはClaude Code、Codex、Piへ同じrole catalogから配る。
Claude Codeは`~/.config/claude/agents`、Codexは`$CODEX_HOME/agents`、
Piは`$PI_CODING_AGENT_DIR/agents`を使う。Piのsubagent extensionも配る。

### ツールの入口

| 入口 | 動作 |
|---|---|
| `lazygit` / `Alt-g` | 現在の作業場所でLazyGit。ショートカットは全画面popup |
| `tuicr` / `Alt-a` | 現在の作業場所でTuicr。ショートカットは全画面popup |
| `pr-review <番号またはURL> [--quick]` | 専用Herdr環境を作り、root paneでOMPとPRレビュースキルを開始 |
| `agent-usage` / `Ctrl-b → u` | アカウント使用枠を確認。ショートカットは操作待ちのpopup |

汎用agent-launcherは廃止し、別エージェントは必要な場面でHerdrから直接起動する。
既存のClaude新tab起動、ファイル選択、zoxide、スクラッチ端末は維持する。

### PRレビュー

Herdr内の対象リポジトリで`pr-review 123`を実行する。
OMPから委譲する場合は`--no-focus`を付け、元の作業へフォーカスを残す。
番号は現在のリポジトリを使い、URLはローカルリポジトリとの一致を確認する。

事前に公式のライフサイクル連携を`herdr integration install omp`で導入する。
起動コマンドはこの拡張を明示的に読み込み、専用root paneと私有sessionの報告を確認してから
プロンプトを送る。拡張の自動検出や、sessionファイルの作成前後に依存しない。

レビュー用worktreeはPRのbase SHAから作る。head側の指示ファイルをOMP起動時に読み込ませない。
準備済み情報と固定base/headを専用OMPへ渡し、同じ環境内でレビューを続ける。
成果物とworkspaceは保持し、GitHubへの投稿は明示確認後に行う。
起動失敗やtimeoutで、別環境を自動作成したり既存環境を削除したりしない。

Paseoの旧PRレビュープラグインは配布・登録処理を退役した。
稼働中のプラグインは自動停止しない。旧プラグインの停止・登録解除は、
実環境へ変更を適用する際に対象を確認して行う。
Paseo本体とアカウント設定は削除しない。

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
