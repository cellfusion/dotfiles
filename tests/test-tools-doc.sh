#!/usr/bin/env bash
# ツール棚卸しドキュメントを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

doc="$(cat "$CHEZMOI_SOURCE/private_dot_config/docs/tools.md" 2>&1)"
brewfile="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "install/brewfile" (dict "os" "darwin") }}' 2>&1)"

assert_contains "$doc" '.agents/skills/multi-agent-development/scripts' \
  "docs: MAD script の配布先を絶対 path で示す"
assert_contains "$doc" 'AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"' \
  "docs: AGENT_CONFIG の fallback を示す"
assert_contains "$doc" 'checkout 専用である' \
  "docs: unit gate が repository 専用であることを示す"

# 削除候補の節はファイル末尾まで続く。複数の assert が同じ範囲を見るので 1 回だけ切る。
removal_section="$(printf '%s\n' "$doc" | sed -n '/^## 削除候補/,$p')"

# --- 節がある ---
for s in "管理方法" "新マシンでの手順" "apply 後に手でやること" "core" "開発ツール" \
         "macOS 専用" "モバイル・ネイティブ開発" "native installer" "mise 管理" \
         "npm グローバル" "cargo 管理" "手動インストール" "削除候補"; do
  assert_contains "$doc" "## $s" "docs: $s の節がある"
done

# --- Brewfile に載っているものはドキュメントにも載る ---
for f in chezmoi neovim herdr television lazygit yabai skhd sketchybar ghostty; do
  assert_contains "$doc" "$f" "docs: $f が載っている"
done

# --- 削除候補が載っている ---
# Task 9 で brew / cargo 分は実行済み。残っているのは npm と ~/.local/bin だけ。
for f in openclaw coderabbit corepack generator-code; do
  assert_contains "$doc" "$f" "docs: 削除候補の $f が載っている"
done

# --- 候補一覧が実態に合っている ---
# Task 9 で削除済みのものを候補に残さない。削除例も、まだ残っている候補で書く。
for f in zellij gitui yazi gemini-cli cliclick cairnd zk-mcp tmuxcc mprocs \
         qt fish python@3.9 spotify_player; do
  assert_not_contains "$removal_section" "$f" "docs: 削除済みの $f を候補に残さない"
done
assert_not_contains "$removal_section" "cargo uninstall" \
  "docs: 削除例が cargo を使っていない（cargo 分は実行済み）"

# --- sketchybar が要求する lua@5.4 を削除候補にしない ---
# 削除候補として実行すると sketchybar が起動しなくなる。
assert_not_contains "$removal_section" "lua@5.4" "docs: lua@5.4 を削除候補に載せない"
assert_contains "$doc" "lua@5.4" "docs: lua@5.4 が macOS 専用として載っている"

# --- native installer の扱いが書かれている ---
assert_contains "$doc" "claude.ai/install.sh" "docs: claude の導入方法が書かれている"
assert_contains "$doc" "chatgpt.com/codex/install.sh" "docs: codex の導入方法が書かれている"
assert_contains "$doc" "自己更新" "docs: brew に寄せない理由が書かれている"

# --- AquaSKK の扱いが記録されている ---
# 2026-08-27 に Brewfile から外した。現マシンには残っている。
assert_contains "$doc" "aquaskk" "docs: AquaSKK の扱いが記録されている"

# --- 手で入れるコマンドの入手方法が記録されている ---
# paseo はマニフェストに載らない。ここに書いていないと新マシンで入れられない。
assert_not_contains "$doc" "braid" "docs: 退役した braid を案内しない"
assert_contains "$doc" "paseo.sh/download" "docs: paseo の入手先が書かれている"
assert_contains "$doc" "/Applications/Paseo.app/Contents/Resources/bin/paseo" \
  "docs: paseo の CLI の在り処が書かれている"

# --- 削除したシェル資産を案内しない。配布済み実体は .chezmoiremove が回収する ---
for legacy in "mad-run" "mad-agent" "mad-route" "mad-runs" "mad-lib"; do
  assert_not_contains "$doc" "$legacy" "docs: 退役した $legacy を案内しない"
done

# --- worktree を作るレシピは後片付けが要る。片付け方が docs に無いと workspace が残る ---
assert_contains "$doc" "archive_workspace" \
  "docs: MAD の worktree を片付ける手段を書く"
assert_contains "$doc" 'mcp-create.prepared' \
  "docs: MAD は create の前に一回性 marker を取ると書く"
assert_contains "$doc" 'max_rounds` を 4' \
  "docs: MAD review/fix の上限を4 roundに固定する"
assert_contains "$doc" '--prepare-review' \
  "docs: MAD review/fix の admission を通す"
assert_contains "$doc" '--write-review-observations' \
  "docs: scope外 observation を atomic 保存する"
assert_contains "$doc" '--check-review-observations' \
  "docs: scope外 observation を最終 gate 前に検査する"
assert_contains "$doc" 'scope 外の重要事項' \
  "docs: scope外の重要事項を observations に保留する"
assert_contains "$doc" '新しい fix/review や hotfix node を起動しない' \
  "docs: review/fix 中に loop を延長しない"
assert_contains "$doc" "workspaces.json" \
  "docs: MAD の workspace 台帳の場所を書く"
assert_contains "$doc" "--verify-only" \
  "docs: 代表証跡は verify-only で検査する"
assert_not_contains "$doc" "MAD_REPRESENTATIVE_RUN_APPROVED=1" \
  "docs: API課金対象の代表 run 承認を案内しない"
assert_not_contains "$doc" "mad-representative-run.sh --run" \
  "docs: API課金対象の代表 run コマンドを案内しない"

assert_eq "$(printf '%s' "$doc" | grep -c 'generate-paseo-config')" "0" \
  "tools.md: 旧 CLI 名が残らない"
assert_eq "$(printf '%s' "$doc" | grep -cE '\"\$MAD_GENERATOR\" (--input [^ ]+ )?(--paseo-config [^ ]+ )?(--diff|--check)?$')" "0" \
  "tools.md: subcommand を付けない呼び出しが残らない"
assert_contains "$doc" "selection" "tools.md: selection の 16 枠を説明する"
assert_eq "$(printf '%s' "$doc" | grep -c '`fast` は入力時だけ')" "0" \
  "tools.md: fast の正規化の記述が残らない"

# --- SketchyBar の使用量採取ジョブの読み込み手順が書かれている ---
# plist を置くだけでは動かない。読み込むまで Claude の週次使用率は更新されない。
assert_contains "$doc" "sketchybar-usage-claude" \
  "docs: 使用量採取ジョブの読み込み手順が書かれている"

# --- 削除を自動化しないことが明記されている ---
assert_contains "$doc" "削除は自動化しない" "docs: 削除を自動化しない旨が書かれている"

# --- 新マシンでの手順 ---
# 1 回の apply で連鎖が成立するようになった。前提が無ければ入れ、入らなければ
# 非ゼロで落ちる。chezmoi は非ゼロで終わった script を記録しないので、落ちた
# ところから次の apply で再開する。
assert_contains "$doc" 'sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply cellfusion' \
  "docs: 1 コマンドのセットアップが書かれている"
assert_not_contains "$doc" "chezmoi state delete-bucket" \
  "docs: skip の復旧手順が残っていない（skip しなくなった）"
assert_not_contains "$doc" "Homebrew を先に入れる" \
  "docs: Homebrew を先に入れる前提が残っていない"
# NONINTERACTIVE=1 の Homebrew installer は sudo -n で判定するため、実際には
# 1 回ではなく Homebrew 本体と cask の両方で複数回聞かれる。「1 回」に戻る退行を防ぐ。
assert_contains "$doc" "複数回" "docs: sudo を複数回聞かれる旨が書かれている"
assert_not_contains "$doc" "sudo のパスワードを 1 回聞かれる" \
  "docs: sudo が 1 回だけという事実と逆の記述が残っていない"

# --- 9 本のスクリプトが一覧されている ---
for s in 00-homebrew 10-brew 20-runtimes 30-mise 40-ai-clis 50-npm-globals \
         60-cargo 70-macos-services 80-secure-enclave-keys; do
  assert_contains "$doc" "$s" "docs: $s が管理方法の表に載っている"
done

# --- 自動化できないものが明記されている ---
manual_section="$(printf '%s\n' "$doc" | sed -n '/^## apply 後に手でやること/,/^## /p')"
assert_contains "$manual_section" "アクセシビリティ" "docs: yabai/skhd の権限付与が書かれている"
assert_contains "$manual_section" "private-data.toml" "docs: private-data.toml の配置が書かれている"
assert_contains "$manual_section" "1Password" "docs: 1Password へのサインインが書かれている"
# calendar_events は Calendar.sqlitedb を直読みするのでフルディスクアクセスが要る。
assert_contains "$manual_section" "フルディスクアクセス" "docs: calendar_events の権限付与が書かれている"
# Secure Enclave の鍵は apply が作るが、GitHub への登録だけは人間が行う。
assert_contains "$manual_section" "Signing Key" "docs: GitHub への鍵登録が書かれている"

# --- zk は退役済み ---
# .chezmoiremove が .config/zk と zk-* ヘルパを削除対象に宣言している。
# core に載せると apply が zk を入れつつ zk の設定を消すことになる。
core_section="$(printf '%s\n' "$doc" | sed -n '/^## core/,/^## 開発ツール/p')"
assert_not_contains "$core_section" "| zk |" "docs: zk を core に載せない"
assert_not_contains "$brewfile" 'brew "zk"' "整合: zk は Brewfile に無い"
# zk への呼び出しは解消済み。helix の設定は存在せず、ship.md のジャーナル節は削除した。
assert_not_contains "$doc" "languages.toml" \
  "docs: 存在しない helix/languages.toml に言及しない"
assert_not_contains "$doc" "退役済みだが参照が残っている" \
  "docs: 未解消の zk 参照を記録する節が残っていない"
ship="$(cat "$CHEZMOI_SOURCE/private_dot_config/claude/commands/ship.md")"
for s in "zk tag list" "zk new" "zk-journal" "--no-journal"; do
  assert_not_contains "$ship" "$s" "ship.md: 退役した zk の $s を呼ばない"
done

# --- アンインストール済みのものを候補に残さない ---
# 候補一覧が実態から外れると、消したかどうかを毎回確かめ直すことになる。
# この節を削除するまでは `helix/languages.toml` が `## 削除候補` の範囲に入って
# いて helix の部分一致が起きるため、この検証は Task 7 ではなくここに置く。
for f in helix wezterm alacritty aerospace omniwm cmux jinrai copilot-cli; do
  assert_not_contains "$removal_section" "$f" "docs: 削除済みの $f を候補に残さない"
done
# gcloud-cli は google-cloud-sdk と同一の cask であり、消すと gcloud ごと失う。
# Brewfile からは外したが、uninstall コマンドには絶対に含めない。
uninstall_cmds="$(printf '%s\n' "$doc" | grep 'brew uninstall' || true)"
assert_not_contains "$uninstall_cmds" "gcloud-cli" \
  "docs: gcloud-cli を brew uninstall の対象に載せない"

# --- native installer と mise に移したものが、その旨とともに載っている ---
native_section="$(printf '%s\n' "$doc" | sed -n '/^## native installer/,/^## /p')"
for t in mise bun uv rustup claude codex; do
  assert_contains "$native_section" "$t" "docs: native installer の節に $t が載っている"
done
# 開発ツールの表からは消えている。brew からは入らなくなった。
build_section="$(printf '%s\n' "$doc" | sed -n '/^## 開発ツール/,/^## /p')"
for t in mise bun uv rustup go cmake ninja zig protobuf automake watchman \
         semgrep mkcert lazydocker cloudflared; do
  assert_not_contains "$build_section" "| $t |" "docs: $t を開発ツールの表に残さない"
done
# chezmoi の install script の既定の BINDIR は ./bin（カレントディレクトリ配下）である。
# -b を渡さないと ~/.local/bin には入らず、「which chezmoi が ~/.local/bin を指すことを
# 確かめてから brew 版を消す」という移行手順がそこで止まる。
chezmoi_install='sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"'
assert_contains "$native_section" "$chezmoi_install" \
  "docs: native installer の chezmoi が -b で ~/.local/bin を指定している"
assert_contains "$removal_section" "$chezmoi_install" \
  "docs: brew からの移行手順が -b で ~/.local/bin を指定している"
# chezmoi を Brewfile から外したので、apply の連鎖に入れる経路は 20-runtimes だけになった。
assert_contains "$native_section" "20-runtimes" \
  "docs: chezmoi を入れるスクリプトが native installer の表から分かる"
# go は mise 管理へ移した。
mise_section="$(printf '%s\n' "$doc" | sed -n '/^## mise 管理/,/^## /p')"
assert_contains "$mise_section" "| go |" "docs: go が mise 管理として載っている"

# --- 2026-08-27 に Brewfile から外したものが表に残っていない ---
core_now="$(printf '%s\n' "$doc" | sed -n '/^## core/,/^## 開発ツール/p')"
for t in hyperfine hunk sevenzip pandoc chafa ffmpeg git-filter-repo; do
  assert_not_contains "$core_now" "| $t |" "docs: $t を core の表に残さない"
done
mac_section="$(printf '%s\n' "$doc" | sed -n '/^## macOS 専用/,/^## /p')"
assert_not_contains "$mac_section" "| nowplaying-cli |" \
  "docs: nowplaying-cli を macOS 専用の表に残さない"
mobile_section="$(printf '%s\n' "$doc" | sed -n '/^## モバイル・ネイティブ開発/,/^## /p')"
assert_not_contains "$mobile_section" "| mint |" \
  "docs: mint をモバイルの表に残さない"
# chezmoi は brew から native installer へ移した。表から消してはならない。
assert_not_contains "$core_now" "| chezmoi |" "docs: chezmoi を core の表に残さない"
assert_contains "$native_section" "chezmoi" \
  "docs: chezmoi が native installer の節に載っている"

# --- brew bundle の挙動と一致している ---
assert_contains "$doc" "--no-upgrade" "docs: 手で回すコマンドが --no-upgrade を付けている"
assert_contains "$doc" "upgrade は行わない" "docs: upgrade を行わない旨が書かれている"

# --- Brewfile の core にあるものが棚卸しの core にも載っている ---
# 逆向き（棚卸しにあって Brewfile に無い）だけを見ていると、Brewfile に足した
# formula を棚卸しに書き忘れても落ちない。読んだ人が入っているツールを把握できなくなる。
core_formulas="$(printf '%s\n' "$brewfile" \
  | sed -n '/^# --- core/,/^$/p' | sed -n 's/^brew "\(.*\)"$/\1/p')"
for f in $core_formulas; do
  assert_contains "$core_section" "| $f |" "整合: Brewfile の core の $f が棚卸しの core に載っている"
done

# --- Brewfile に無いものを core として載せていない ---
for f in yazi helix gitui; do
  assert_not_contains "$brewfile" "brew \"$f\"" "整合: $f は Brewfile に無い"
done

# --- worktrees.md が現在の経路を書いている ---
# MAD の implement / spike では worktree を作るのは親である。子が作ると、実装の
# コミットが親の見ないブランチに載り、親が取る diff が空になる。
worktrees_doc="$(cat "$CHEZMOI_SOURCE/private_dot_config/docs/worktrees.md" 2>&1)"
assert_contains "$worktrees_doc" "using-git-worktrees" \
  "worktrees: worktree の手順が using-git-worktrees にあると書く"
assert_contains "$worktrees_doc" "multi-agent-development" \
  "worktrees: 実装工程の入口が MAD であると書く"
assert_contains "$worktrees_doc" "worktree を作るのは親である" \
  "worktrees: MAD の worktree を作るのは親であると書く"
assert_not_contains "$worktrees_doc" "親は worktree を作らない" \
  "worktrees: 子を所有者とする旧記述を残さない"
assert_contains "$worktrees_doc" "mcp__paseo__create_workspace" \
  "worktrees: Paseo MCP backend の worktree 作成手段を書く"

# --- Paseo-only の実行順が記録されている ---
for step in "list-providers" "list-models" "snapshot" "create"; do
  assert_contains "$doc" "$step" "docs: Paseo の $step 手順を記録する"
done
assert_contains "$doc" "0600" "docs: Paseo 成果物の権限を記録する"

# --- README と棚卸しの整合 ---
readme="$(cat "$CHEZMOI_SOURCE/README.md" 2>&1)"

# 使っているツールが Main Tools 表に載っている。
for t in chezmoi Ghostty Herdr Neovim lazygit television yabai skhd Claude SketchyBar; do
  assert_contains "$readme" "$t" "README: $t が載っている"
done

# 削除候補は Main Tools 表に載せない。
main_tools="$(printf '%s\n' "$readme" | sed -n '/^## Main Tools/,/^## /p')"
for t in yazi WezTerm Alacritty OmniWM zellij helix; do
  assert_not_contains "$main_tools" "$t" "README: 削除候補の $t を Main Tools に載せない"
done

# ツール一覧ドキュメントへのリンクがある。
assert_contains "$readme" "private_dot_config/docs/tools.md" "README: tools.md へのリンクがある"

# インストール手順が書かれている。
assert_contains "$readme" "install/Brewfile" "README: Brewfile の場所が書かれている"
assert_contains "$readme" "--no-upgrade" "README: 手で回すコマンドが --no-upgrade を付けている"

# --- 管理方法の表と本文の本数が一致する ---
# 表に 1 行足して本数を直し忘れると、新マシンの手順書が実態とずれる。
script_rows="$(printf '%s\n' "$doc" | grep -c '| `run_onchange_after_')"
declared="$(printf '%s\n' "$doc" | sed -n 's/^apply の中で上の表の \([0-9][0-9]*\) 本が番号順に実行される。$/\1/p')"
assert_eq "$declared" "$script_rows" "docs: 表のスクリプト数と本文の本数が一致する"

assert_contains "$doc" "## agent で AI 環境を指定して起動する" "tools.md: agent ラッパーの節がある"
assert_contains "$doc" 'agent --provider=<provider-id>' "tools.md: agent ラッパーの使い方を書く"
assert_contains "$doc" "setup.configDirectoryEnv" "tools.md: ラッパーが設定する変数の出所を書く"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
