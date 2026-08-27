#!/usr/bin/env bash
# .chezmoiscripts の run_onchange スクリプトを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

render_script() {
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    < "$CHEZMOI_SOURCE/.chezmoiscripts/$1" 2>&1
}

homebrew_s="$(render_script run_onchange_after_00-homebrew.sh.tmpl)"
brew_s="$(render_script run_onchange_after_10-brew.sh.tmpl)"
runtimes_s="$(render_script run_onchange_after_20-runtimes.sh.tmpl)"
mise_s="$(render_script run_onchange_after_30-mise.sh.tmpl)"
ai_s="$(render_script run_onchange_after_40-ai-clis.sh.tmpl)"
npm_s="$(render_script run_onchange_after_50-npm-globals.sh.tmpl)"
cargo_s="$(render_script run_onchange_after_60-cargo.sh.tmpl)"
macos_s="$(render_script run_onchange_after_70-macos-services.sh.tmpl)"
agent_env_s="$(render_script run_onchange_after_90-agent-envs.sh.tmpl)"

# --- 全スクリプト共通 ---
for pair in "homebrew:$homebrew_s" "brew:$brew_s" "runtimes:$runtimes_s" "mise:$mise_s" \
            "ai:$ai_s" "npm:$npm_s" "cargo:$cargo_s" "macos:$macos_s" \
            "agent-env:$agent_env_s"; do
  name="${pair%%:*}"
  body="${pair#*:}"
  assert_contains "$body" "#!/usr/bin/env bash" "$name: shebang がある"
  assert_contains "$body" "set -eu" "$name: set -eu がある"
  assert_not_contains "$body" "{{" "$name: 未展開のテンプレート構文が残っていない"
  # Homebrew の trust store は XDG_CONFIG_HOME が指す場所に置かれる。設定しないと
  # apply が書く trust と zsh から見る trust が別のファイルになる。
  assert_contains "$body" 'XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"' \
    "$name: trust store の場所を XDG_CONFIG_HOME で固定している"
done

# --- 変更検知のハッシュが埋まっている（64 桁の hex） ---
# homebrew / runtimes / ai は「未導入のときだけ入れる」のでマニフェストを持たない。
for pair in "brew:$brew_s" "mise:$mise_s" "npm:$npm_s" "cargo:$cargo_s" "macos:$macos_s"; do
  name="${pair%%:*}"
  body="${pair#*:}"
  hash_line="$(printf '%s\n' "$body" | grep -cE '^# manifest hash: [0-9a-f]{64}$' || true)"
  assert_eq "$hash_line" "1" "$name: manifest hash 行が 1 本ある"
done

# --- 全スクリプトが、飛ばさずに落ちる ---
# chezmoi は非ゼロで終わった script を entryState に記録しない。飛ばして記録される
# のではなく落ちることで、取りこぼしが次の apply で必ず再実行される。
for pair in "homebrew:$homebrew_s" "brew:$brew_s" "runtimes:$runtimes_s" \
            "mise:$mise_s" "ai:$ai_s" "npm:$npm_s" "cargo:$cargo_s" "macos:$macos_s" \
            "agent-env:$agent_env_s"; do
  name="${pair%%:*}"
  body="${pair#*:}"
  assert_contains "$body" 'die()' "$name: preamble の die を持っている"
  assert_contains "$body" 'prepend_path()' "$name: preamble を取り込んでいる"
  assert_not_contains "$body" 'chezmoi state delete-bucket' \
    "$name: skip の復旧手順を持たない（skip しないため）"
done

# --- homebrew ---
assert_contains "$homebrew_s" 'raw.githubusercontent.com/Homebrew/install' \
  "homebrew: 公式インストーラを使う"
assert_contains "$homebrew_s" 'NONINTERACTIVE=1' "homebrew: 非対話でインストーラを回す"
assert_contains "$homebrew_s" 'brew_env' "homebrew: brew_env で既存の導入を検出する"
# before に置くと、ここで失敗したときに nvim や zsh の設定まで配られない。
assert_contains "$homebrew_s" 'before ではなく after に置く' \
  "homebrew: after に置く理由がコメントにある"

# --- brew ---
assert_contains "$brew_s" 'brew_env' "brew: brew_env で PATH を組み立てる"
assert_not_contains "$brew_s" 'command -v brew' "brew: PATH 頼みの判定をしない"
assert_contains "$brew_s" 'brew bundle --file' "brew: brew bundle を実行する"
assert_contains "$brew_s" '$HOME/.config/install/Brewfile' "brew: 配った Brewfile を参照する"
assert_not_contains "$brew_s" "brew bundle cleanup" "brew: cleanup を実行しない"
# `brew bundle` は既定で outdated な formula の upgrade も行う。マニフェストに
# 1 行足しただけの apply が無関係な formula の再ビルドを巻き込まないよう抑止する。
assert_contains "$brew_s" '--no-upgrade' "brew: 既定の upgrade を抑止する"

# --- runtimes ---
assert_contains "$runtimes_s" 'https://mise.run' "runtimes: mise の native installer を使う"
assert_contains "$runtimes_s" 'https://bun.sh/install' "runtimes: bun の native installer を使う"
assert_contains "$runtimes_s" 'https://astral.sh/uv/install.sh' "runtimes: uv の native installer を使う"
assert_contains "$runtimes_s" 'https://sh.rustup.rs' "runtimes: rustup の native installer を使う"
# PATH の管理は .zshenv と preamble に一本化する。rustup に shell の設定ファイルを
# 書き換えさせない。
assert_contains "$runtimes_s" '--no-modify-path' "runtimes: rustup に PATH を触らせない"
# rustup を入れただけでは toolchain が無く、cargo は存在しない。
assert_contains "$runtimes_s" 'rustup default stable' "runtimes: toolchain を入れる"
assert_not_contains "$runtimes_s" 'brew install' "runtimes: brew を使わない"
assert_not_contains "$runtimes_s" 'brew_env ||' "runtimes: brew に依存しない"
# chezmoi は Brewfile から外した。apply の連鎖に chezmoi を入れる経路はここだけである。
# ここが無いと、bootstrap が ./bin に置いた 1 本しか残らず、~/.local/bin にも
# /opt/homebrew/bin にも chezmoi が無い新マシンができる。
assert_contains "$runtimes_s" 'get.chezmoi.io' "runtimes: chezmoi の native installer を使う"
# install script の既定の BINDIR は ./bin（カレントディレクトリ配下）である。-b を
# 渡さないと、.zshenv が PATH に載せる ~/.local/bin には入らない。
assert_contains "$runtimes_s" '-b "$HOME/.local/bin"' \
  "runtimes: chezmoi を ~/.local/bin に入れる"
assert_contains "$runtimes_s" 'command -v chezmoi' "runtimes: chezmoi の有無を確認する"

# --- mise ---
assert_contains "$mise_s" 'mise install' "mise: mise install を実行する"
assert_not_contains "$mise_s" 'command -v mise >/dev/null 2>&1 || die' \
  "mise: 判定と die が 1 行に潰れていない"
assert_contains "$mise_s" 'local_bin_env' "mise: native installer の置き場を PATH に載せる"

# --- AI CLI ---
assert_contains "$ai_s" 'https://claude.ai/install.sh' "ai: claude の native installer を使う"
assert_contains "$ai_s" 'https://chatgpt.com/codex/install.sh' "ai: codex の native installer を使う"
assert_contains "$ai_s" 'command -v claude' "ai: claude の有無を確認する"
assert_contains "$ai_s" 'command -v codex' "ai: codex の有無を確認する"
assert_contains "$ai_s" 'local_bin_env' "ai: native installer の置き場を PATH に載せる"
assert_not_contains "$ai_s" 'brew install' "ai: brew を使わない"

# --- npm ---
# npm を PATH から探すと、mise activate を通していないシェルから apply したときに
# システムの node を掴む。mise に解決させる。
assert_contains "$npm_s" 'mise exec -- npm install -g' "npm: mise の node で npm を回す"
assert_contains "$npm_s" '$HOME/.config/install/npm-globals.txt' "npm: 配ったマニフェストを参照する"
assert_not_contains "$npm_s" 'command -v npm' "npm: PATH 頼みの判定をしない"

# --- cargo ---
assert_contains "$cargo_s" 'cargo install' "cargo: cargo install を実行する"
assert_contains "$cargo_s" '$HOME/.config/install/cargo-globals.txt' "cargo: 配ったマニフェストを参照する"
assert_contains "$cargo_s" 'rust_env' "cargo: CARGO_HOME/bin を PATH に載せる"
# brew の rustup は keg-only で toolchain を持たない。20-runtimes が native の
# rustup を入れるので、この回避策は要らなくなった。
assert_not_contains "$cargo_s" 'brew --prefix rustup' "cargo: brew の rustup に依存しない"

# --- macOS サービス ---
# helper のバイナリは .chezmoiignore で配布対象から外してある。新マシンでは
# ソースから作る以外に入手経路が無い。
assert_contains "$macos_s" 'brew_env' "macos: yabai/skhd を PATH に載せる"
assert_contains "$macos_s" 'make' "macos: sketchybar の helper をビルドする"
assert_contains "$macos_s" '.config/sketchybar/helpers' "macos: helper の場所を参照する"
# yabai と skhd のサービス登録は brew では行われない。--start-service が
# LaunchAgent を書く。
assert_contains "$macos_s" 'yabai --start-service' "macos: yabai のサービスを登録する"
assert_contains "$macos_s" 'skhd --start-service' "macos: skhd のサービスを登録する"
assert_contains "$macos_s" 'com.asmvik.yabai.plist' "macos: yabai の LaunchAgent を判定に使う"
assert_contains "$macos_s" 'com.koekeishiya.skhd.plist' "macos: skhd の LaunchAgent を判定に使う"
# sketchybar と borders は yabairc が起動する。ここでは触らない。
assert_not_contains "$macos_s" 'sketchybar --start-service' "macos: sketchybar は yabairc が起動する"
assert_not_contains "$macos_s" 'borders' "macos: borders は yabairc が起動する"

# linux では中身が空になる。.chezmoi.os はテンプレート実行時の実 OS を返すため、
# テストから linux を偽装できない。展開結果ではなくテンプレートのソースを見る。
macos_src="$(cat "$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_70-macos-services.sh.tmpl")"
assert_contains "$macos_src" '{{ if eq .chezmoi.os "darwin"' \
  "macos: darwin 以外では中身が空になる"

# --- ビルド成果物は配布対象から外れている ---
# 成果物は destDir に生成される。ignore を外すと chezmoi が管理対象と誤認する。
ignore="$(cat "$CHEZMOI_SOURCE/.chezmoiignore")"
for b in menus/bin/menus \
         event_providers/cpu_load/bin/cpu_load \
         event_providers/memory_load/bin/memory_load \
         event_providers/network_load/bin/network_load \
         event_providers/disk_load/bin/disk_load \
         event_providers/calendar_events/bin/calendar_events \
         event_providers/spotify_events/bin/spotify_events; do
  assert_contains "$ignore" ".config/sketchybar/helpers/$b" \
    "ignore: $b を配布対象から外している"
done

# chezmoi の .chezmoiignore は destDir からの相対 target path で照合する。~/ を付けると
# パターンが一致せず ignore が無効になる（隔離環境で実測）。
assert_not_contains "$ignore" '~/' "ignore: ~/ プレフィックスを使わない（照合されない）"

# --- 同じ入力なら同じ内容に展開される（冪等性） ---
assert_eq "$(render_script run_onchange_after_00-homebrew.sh.tmpl)" "$homebrew_s" \
  "homebrew: 2 回展開しても内容が変わらない"
assert_eq "$(render_script run_onchange_after_10-brew.sh.tmpl)" "$brew_s" \
  "brew: 2 回展開しても内容が変わらない"

# --- bash の構文として妥当 ---
for pair in "homebrew:$homebrew_s" "brew:$brew_s" "runtimes:$runtimes_s" "mise:$mise_s" \
            "ai:$ai_s" "npm:$npm_s" "cargo:$cargo_s" "macos:$macos_s" \
            "agent-env:$agent_env_s"; do
  name="${pair%%:*}"
  body="${pair#*:}"
  err="$(printf '%s\n' "$body" | bash -n 2>&1 || true)"
  assert_eq "$err" "" "$name: bash -n が通る"
done

# --- 番号が一意である ---
# chezmoi はスクリプトをファイル名順に実行する。同じ番号が 2 本あると実行順が
# 番号の後ろの語に決まってしまい、tools.md が「00 / 20 / 40」のように番号だけで
# 指している記述もどちらを指すのか分からなくなる。
nums="$(ls "$CHEZMOI_SOURCE/.chezmoiscripts/" | sed -n 's/^run_onchange_after_\([0-9][0-9]\)-.*/\1/p' | sort)"
dupes="$(printf '%s\n' "$nums" | uniq -d | tr '\n' ' ' | sed 's/ $//')"
assert_eq "$dupes" "" "run_onchange スクリプトの番号が一意である"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
