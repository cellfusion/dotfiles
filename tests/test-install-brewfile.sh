#!/usr/bin/env bash
# Brewfile テンプレートが OS ごとに正しく展開されることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

render_brewfile() {
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"install/brewfile\" (dict \"os\" \"$1\") }}"
}

darwin="$(render_brewfile darwin)"
linux="$(render_brewfile linux)"

# --- core は両 OS に載る ---
for f in git gh ghq git-lfs lazygit neovim fzf fd ripgrep bat eza jq \
         television zoxide herdr; do
  assert_contains "$darwin" "brew \"$f\"" "darwin: core に $f がある"
  assert_contains "$linux" "brew \"$f\"" "linux: core に $f がある"
done

# --- 開発ツールは両 OS に載る ---
for f in sccache awscli grpcurl; do
  assert_contains "$darwin" "brew \"$f\"" "darwin: 開発ツールに $f がある"
  assert_contains "$linux" "brew \"$f\"" "linux: 開発ツールに $f がある"
done

# --- third-party は Brewfile に載せない ---
# non-official tap の formula は third-party.txt へ分けた。10-brew が fully-qualified 名で
# 入れると tap と trust が自動で付く。Brewfile に残すと trust が要求され apply が止まる。
for t in anomalyco asmvik felixkratz; do
  assert_not_contains "$darwin" "$t" "darwin: third-party の $t を Brewfile に載せない"
  assert_not_contains "$linux" "$t" "linux: third-party の $t を Brewfile に載せない"
done
assert_not_contains "$darwin" 'trusted:' "darwin: trusted 宣言に頼らない"

# --- macOS 専用 ---
for f in switchaudio-osx coreutils; do
  assert_contains "$darwin" "brew \"$f\"" "darwin: macOS 専用に $f がある"
  assert_not_contains "$linux" "brew \"$f\"" "linux: macOS 専用の $f が無い"
done
# --- third-party のマニフェスト ---
tp_darwin="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "install/third-party" (dict "os" "darwin") }}')"
tp_linux="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "install/third-party" (dict "os" "linux") }}')"
for f in anomalyco/tap/opencode asmvik/formulae/yabai asmvik/formulae/skhd \
         felixkratz/formulae/borders felixkratz/formulae/sketchybar; do
  assert_contains "$tp_darwin" "$f" "third-party: darwin に $f がある"
done
assert_contains "$tp_linux" 'anomalyco/tap/opencode' "third-party: linux に opencode がある"
assert_not_contains "$tp_linux" 'asmvik' "third-party: linux に macOS 専用が無い"
assert_not_contains "$tp_linux" 'felixkratz' "third-party: linux に macOS 専用が無い"

# sketchybarrc の shebang が /opt/homebrew/opt/lua@5.4/bin/lua を指している。
# lua@5.4 が無いと sketchybar は起動しない。
assert_contains "$darwin" 'brew "lua@5.4"' "darwin: sketchybar が要求する lua@5.4 がある"
assert_not_contains "$linux" 'brew "lua@5.4"' "linux: macOS 専用の lua@5.4 が無い"
assert_contains "$(cat "$CHEZMOI_SOURCE/private_dot_config/sketchybar/executable_sketchybarrc")" \
  'lua@5.4' "整合: sketchybarrc が lua@5.4 を参照している"

# --- cask は macOS だけ ---
assert_contains "$darwin" 'cask "ghostty"' "darwin: ghostty の cask がある"
assert_contains "$darwin" 'cask "1password-cli"' "darwin: 1password-cli の cask がある"
# google-cloud-sdk は gcloud-cli の旧名であり、同一 cask のエイリアスである。旧名で
# 宣言すると別物と誤認する。実際、削除候補として gcloud-cli を消したとき
# google-cloud-sdk ごと消えて gcloud が失われた。
assert_contains "$darwin" 'cask "gcloud-cli"' "darwin: gcloud-cli の cask がある"
assert_not_contains "$darwin" 'cask "google-cloud-sdk"' \
  "darwin: 旧名 google-cloud-sdk で宣言しない"
assert_contains "$darwin" 'cask "aquaskk"' "darwin: aquaskk の cask がある"
assert_not_contains "$linux" 'cask "' "linux: cask 行が 1 つも無い"

# --- モバイル・ネイティブは macOS だけ ---
for f in cocoapods ios-deploy libimobiledevice xcodegen xcode-build-server \
         apktool jadx kdoctor gradle; do
  assert_contains "$darwin" "brew \"$f\"" "darwin: モバイル系に $f がある"
  assert_not_contains "$linux" "brew \"$f\"" "linux: モバイル系の $f が無い"
done

# --- 2026-08-27 に外したものは載せない ---
# chezmoi は 20-runtimes が get.chezmoi.io で ~/.local/bin に入れる。brew 版を載せると
# 2 本になる。
# nowplaying-cli は macOS 26 で MediaRemote が塞がれていて動かない。
# 残りは設定からもスクリプトからも参照されず、他の formula の依存にもなっていない。
for f in chezmoi nowplaying-cli hunk semgrep sevenzip chafa watchman hyperfine \
         mint lazydocker git-filter-repo automake mkcert cloudflared \
         cmake ninja zig protobuf pandoc ffmpeg; do
  assert_not_contains "$darwin" "brew \"$f\"" "darwin: 外した $f を載せない"
  assert_not_contains "$linux" "brew \"$f\"" "linux: 外した $f を載せない"
done

# --- 削除候補は載せない ---
# 退役したツールは .chezmoiremove が削除を宣言している。
# 入れつつ設定を消す状態にならないよう Brewfile にも載せない。
for f in zk tmux sesh mprocs helix gitui lsd yazi fish gemini-cli avrdude putty qt \
         netcdf docutils pillow potrace mvfst xdg-ninja resvg vips composer \
         pipenv guile; do
  assert_not_contains "$darwin" "brew \"$f\"" "darwin: 削除候補の $f を載せない"
  assert_not_contains "$linux" "brew \"$f\"" "linux: 削除候補の $f を載せない"
done
for c in wezterm alacritty rio cmux jinrai copilot-cli zed aerospace omniwm; do
  assert_not_contains "$darwin" "cask \"$c\"" "darwin: 削除候補の cask $c を載せない"
done

# --- mise 管理のものは brew に載せない ---
for f in node python deno pnpm yarn openjdk go; do
  assert_not_contains "$darwin" "brew \"$f\"" "darwin: mise 管理の $f を brew に載せない"
  assert_not_contains "$linux" "brew \"$f\"" "linux: mise 管理の $f を brew に載せない"
done

# --- native installer に移したものは brew に載せない ---
# mise / bun / uv / rustup はいずれも自己更新を持ち、brew 版は別ビルドになる。
# brew の rustup は keg-only で toolchain を持たない。20-runtimes が入れる。
for f in mise uv bun rustup; do
  assert_not_contains "$darwin" "brew \"$f\"" \
    "darwin: native installer の $f を brew に載せない"
  assert_not_contains "$linux" "brew \"$f\"" \
    "linux: native installer の $f を brew に載せない"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
