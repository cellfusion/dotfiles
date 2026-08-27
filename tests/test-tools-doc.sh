#!/usr/bin/env bash
# ツール棚卸しドキュメントを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

doc="$(cat "$CHEZMOI_SOURCE/private_dot_config/docs/tools.md" 2>&1)"
brewfile="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "install/brewfile" (dict "os" "darwin") }}' 2>&1)"

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

# --- AquaSKK は cask で導入する ---
assert_contains "$doc" "aquaskk" "docs: AquaSKK が cask として載っている"
manual_install="$(printf '%s\n' "$doc" | sed -n '/^## 手動インストール/,/^## /p')"
assert_not_contains "$manual_install" "| AquaSKK |" "docs: AquaSKK を手動インストールの表に残さない"

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
# gcloud-cli は google-cloud-sdk と同一の cask であり、重複ではない。候補に残すと
# 消したときに gcloud ごと失う。
assert_not_contains "$removal_section" "gcloud-cli" "docs: gcloud-cli を削除候補に載せない"
assert_contains "$doc" "gcloud-cli (cask)" "docs: gcloud-cli が macOS 専用として載っている"

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

# --- Brewfile に無いものを core として載せていない ---
for f in yazi helix gitui; do
  assert_not_contains "$brewfile" "brew \"$f\"" "整合: $f は Brewfile に無い"
done

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

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
