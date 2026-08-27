#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

# 環境定義は clone した人のマシンによって違うので、fixture を与えて描画する。
cfg="$(mktemp)"
cat > "$cfg" <<'EOF'
[[data.environments]]
    session = "default"
    label   = "P1"
    agents  = ["claude", "codex"]

[[data.environments]]
    session = "work"
    label   = "P2"
    agents  = ["claude", "codex"]

[[data.environments]]
    session = "solo"
    label   = "P3"
    agents  = ["claude"]
EOF

USAGE_SH="$(mktemp)"
chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/private_dot_config/sketchybar/helpers/executable_usage.sh.tmpl" \
  > "$USAGE_SH"
chmod +x "$USAGE_SH"
trap 'rm -f "$USAGE_SH" "$cfg"' EXIT
STATUSLINE_SH="$CHEZMOI_SOURCE/private_dot_config/claude/executable_statusline.sh.tmpl"
usage_lua="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/private_dot_config/sketchybar/items/usage.lua.tmpl")"
fixture_home="$(mktemp -d)"
trap 'rm -f "$USAGE_SH" "$cfg"; rm -rf "$fixture_home"' EXIT

assert_contains "$usage_lua" 'app_icons["Claude"]' "LuaがClaudeアイコンを使う"
assert_contains "$usage_lua" 'app_icons["ChatGPT"]' "LuaがCodexアイコンを使う"
assert_contains "$usage_lua" 'widgets.usage.default.claude' "default Claude の item 名を固定する"
assert_contains "$usage_lua" 'widgets.usage.default.codex' "default Codex の item 名を固定する"
assert_contains "$usage_lua" 'widgets.usage.work.claude' "work Claude の item 名を固定する"
assert_contains "$usage_lua" 'widgets.usage.work.codex' "work Codex の item 名を固定する"
assert_contains "$usage_lua" 'mouse.entered' "ホバー開始イベントを購読する"
assert_contains "$usage_lua" 'mouse.exited.global' "ホバー終了イベントを購読する"
assert_contains "$usage_lua" 'update_freq = 120' "使用率の更新間隔を維持する"
assert_contains "$usage_lua" 'popup.default.claude' "default Claude の popup 行を持つ"
assert_contains "$usage_lua" 'popup.default.codex' "default Codex の popup 行を持つ"
assert_contains "$usage_lua" 'popup.work.claude' "work Claude の popup 行を持つ"
assert_contains "$usage_lua" 'popup.work.codex' "work Codex の popup 行を持つ"
assert_not_contains "$usage_lua" '単一item' "旧単一item前提のコメントを残さない"
assert_not_contains "$usage_lua" 'click_script = "open -a Ghostty"' "Ghostty起動クリックを残さない"

# position="right"は後から追加したitemほど左へ置かれるため、望む表示順
# (先頭環境 [Claude] 64% [Codex] 20% | 次の環境 …) を得るには、組んだ計画を
# 末尾から sbar.add する必要がある。
assert_contains "$usage_lua" 'for i = #display_plan, 1, -1 do' \
  "display_plan を末尾から add する（通常表示が 先頭環境...|次の環境... の順になる）"

primary_reset=4102444800
secondary_reset=4102448400
primary_log='{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":31.0,"window_minutes":300,"resets_at":1700000000},"secondary":{"used_percent":31.0,"window_minutes":10080,"resets_at":4102444800}}}}'
secondary_log='{"type":"event_msg","rate_limits":{"primary":{"used_percent":67.0,"window_minutes":10080,"resets_at":4102448400},"secondary":null}}'

put_log() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  touch -t "$4" "$1/$2"
}

mkdir -p "$fixture_home/.config/codex/sessions" \
  "$fixture_home/.config/codex_work/sessions" \
  "$fixture_home/.cache/sketchybar-usage"
put_log "$fixture_home" ".config/codex/sessions/2026/08/01/primary.jsonl" "$primary_log" 202608010000
put_log "$fixture_home" ".config/codex_work/sessions/2026/08/01/secondary.jsonl" "$secondary_log" 202608010000

primary_out=$(HOME="$fixture_home" "$USAGE_SH" codex "$fixture_home/.config/codex/sessions" default-codex)
secondary_out=$(HOME="$fixture_home" "$USAGE_SH" codex "$fixture_home/.config/codex_work/sessions" work-codex)
assert_eq "$primary_out" "$(printf '31\t%s\tok' "$primary_reset")" "primary Codex を独立取得する"
assert_eq "$secondary_out" "$(printf '67\t%s\tok' "$secondary_reset")" "secondary Codex を独立取得する"

updated_primary_log='{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":35.0,"window_minutes":10080,"resets_at":4102444800},"secondary":null}}}'
put_log "$fixture_home" ".config/codex/sessions/2026/08/02/primary-new.jsonl" "$updated_primary_log" 202608020000
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" codex "$fixture_home/.config/codex_work/sessions" work-codex)" \
  "$(printf '67\t%s\tok' "$secondary_reset")" "primary 側ログ更新で secondary Codex を変えない"

printf '{"used_pct":"67","resets_at":"%s"}' "$secondary_reset" > "$fixture_home/.cache/sketchybar-usage/work-codex.json"
rm -rf "$fixture_home/.config/codex_work/sessions" \
  "$fixture_home/.config/codex/sessions"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" codex "$fixture_home/.config/codex_work/sessions" work-codex)" \
  "$(printf '67\t%s\tstale' "$secondary_reset")" "ログなしで同名Codexキャッシュがあればstaleにする"
rm -f "$fixture_home/.cache/sketchybar-usage/default-codex.json"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" codex "$fixture_home/.config/codex/sessions" default-codex)" \
  "$(printf -- '-\t-\terror')" "ログも同名キャッシュもないCodexはerrorにする"

# 週次window(>=10080分)が無く5時間window(300分)しか無いログは、週次の
# used_percent/resets_atを誤って返さずerrorにする(secondaryはnull)。
five_hour_only_log='{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1700000000},"secondary":null}}}'
rm -rf "$fixture_home/.config/codex/sessions"
mkdir -p "$fixture_home/.config/codex/sessions"
put_log "$fixture_home" ".config/codex/sessions/2026/08/03/five-hour-only.jsonl" "$five_hour_only_log" 202608030000
rm -f "$fixture_home/.cache/sketchybar-usage/default-codex.json"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" codex "$fixture_home/.config/codex/sessions" default-codex)" \
  "$(printf -- '-\t-\terror')" "5時間windowしか無いログは週次を騙らずerrorにする"

# 週次(10080分)と5時間(300分)の両方を持つログでは、window_minutesが小さい
# 5時間側ではなく週次側のused_percent/resets_atが選ばれる。
rm -rf "$fixture_home/.config/codex/sessions"
mkdir -p "$fixture_home/.config/codex/sessions"
put_log "$fixture_home" ".config/codex/sessions/2026/08/04/both-windows.jsonl" "$primary_log" 202608040000
rm -f "$fixture_home/.cache/sketchybar-usage/default-codex.json"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" codex "$fixture_home/.config/codex/sessions" default-codex)" \
  "$(printf '31\t%s\tok' "$primary_reset")" "週次と5時間の両方があれば週次側が選ばれる"

# 集約テストの前提(primary Codex はログもキャッシュも無く error)へ戻す。
rm -rf "$fixture_home/.config/codex/sessions"
rm -f "$fixture_home/.cache/sketchybar-usage/default-codex.json"

now=$(date +%s)
printf '{"used_pct":"23","resets_at":"%s","ts":%s}\n' "$primary_reset" "$now" > \
  "$fixture_home/.cache/sketchybar-usage/default-claude.json"
printf '{"used_pct":"71","resets_at":"%s","ts":%s}\n' "$secondary_reset" "$now" > \
  "$fixture_home/.cache/sketchybar-usage/work-claude.json"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" claude "$fixture_home/.config/claude" default-claude)" \
  "$(printf '23\t%s\tok' "$primary_reset")" "default Claude のキャッシュを読む"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" claude "$fixture_home/.config/claude_work" work-claude)" \
  "$(printf '71\t%s\tok' "$secondary_reset")" "work Claude のキャッシュを読む"

statusline=$(cat "$STATUSLINE_SH")
assert_contains "$statusline" 'AGENT_ENV_SESSION' "statusline は AGENT_ENV_SESSION からキャッシュキーを作る"
assert_not_contains "$statusline" 'claude_secondary) key=' "statusline に固定の環境名の写像が残っていない"

aggregate=$(HOME="$fixture_home" "$USAGE_SH")
assert_eq "$(printf '%s\n' "$aggregate" | awk 'END { print NR }')" "5" "無引数実行は定義された環境別レコードを出す"
assert_contains "$aggregate" "$(printf 'P1\tclaude\t23')" "集約に default Claude を含める"
assert_contains "$aggregate" "$(printf 'P1\tcodex\t-\t-\terror\tnone')" "集約の default Codex error をレコード内に閉じ込める"
assert_contains "$aggregate" "$(printf 'P2\tclaude\t71')" "集約に work Claude を含める"
assert_contains "$aggregate" "$(printf 'P2\tcodex\t67')" "集約に work Codex を含める"
assert_contains "$aggregate" "$(printf 'P3\tclaude\t-\t-\terror\tnone')" "集約に solo Claude を含める"

pace_now=$(date +%s)
pace_reset=$((pace_now + 302400))
assert_eq "$("$USAGE_SH" pace 4 "$pace_reset" ok "$pace_now")" "none" "5%未満は灰"
assert_eq "$("$USAGE_SH" pace 54 "$pace_reset" ok "$pace_now")" "ok" "差5未満は緑"
assert_eq "$("$USAGE_SH" pace 55 "$pace_reset" ok "$pace_now")" "warn" "差5は黄"
assert_eq "$("$USAGE_SH" pace 69 "$pace_reset" ok "$pace_now")" "warn" "差19は黄"
assert_eq "$("$USAGE_SH" pace 70 "$pace_reset" ok "$pace_now")" "crit" "差20は赤"
assert_eq "$("$USAGE_SH" pace 90 "$pace_reset" stale "$pace_now")" "none" "staleは灰"
assert_eq "$("$USAGE_SH" pace 90 "$pace_reset" error "$pace_now")" "none" "errorは灰"
assert_eq "$("$USAGE_SH" pace 90 "$((pace_now - 1))" ok "$pace_now")" "none" "リセット済みは灰"
assert_eq "$("$USAGE_SH" pace nope "$pace_reset" ok "$pace_now")" "none" "使用率が非数値なら灰"
assert_eq "$("$USAGE_SH" pace 50 nope ok "$pace_now")" "none" "リセット日時が非数値なら灰"
assert_eq "$("$USAGE_SH" pace 50 "$pace_reset" ok nope)" "none" "現在時刻が非数値なら灰"

# --- 環境定義から項目が組まれる。持たない agent の項目は作らない ---
assert_contains "$usage_lua" 'widgets.usage.solo.claude' "3 つ目の Claude 項目がある"
assert_not_contains "$usage_lua" 'widgets.usage.solo.codex' \
  "codex を持たない環境の Codex 項目は作らない"
assert_not_contains "$usage_lua" 'widgets.usage.primary.' "固定の primary 項目名が残っていない"
assert_not_contains "$usage_lua" 'widgets.usage.secondary.' "固定の secondary 項目名が残っていない"

# --- usage.sh が環境ごとの emit_record を持つ ---
usage_sh_body="$(cat "$USAGE_SH")"
assert_contains "$usage_sh_body" 'emit_record P1 claude "$HOME/.config/claude" default-claude' \
  "先頭環境の Claude はサフィックス無しのパスを見る"
assert_contains "$usage_sh_body" 'emit_record P1 codex "$HOME/.config/codex/sessions" default-codex' \
  "先頭環境の Codex はサフィックス無しのパスを見る"
assert_contains "$usage_sh_body" 'emit_record P2 claude "$HOME/.config/claude_work" work-claude' \
  "2 つ目の Claude は suffix 付きのパスを見る"
assert_contains "$usage_sh_body" 'emit_record P2 codex "$HOME/.config/codex_work/sessions" work-codex' \
  "2 つ目の Codex は suffix 付きのパスを見る"
assert_contains "$usage_sh_body" 'emit_record P3 claude "$HOME/.config/claude_solo" solo-claude' \
  "3 つ目の Claude は suffix 付きのパスを見る"
assert_not_contains "$usage_sh_body" 'codex_solo' \
  "codex を持たない環境の emit_record は出さない"

# --- statusline のキャッシュキーが AGENT_ENV_SESSION から作られる ---
statusline_body="$(cat "$STATUSLINE_SH")"
assert_contains "$statusline_body" 'AGENT_ENV_SESSION' \
  "statusline は AGENT_ENV_SESSION を使う"
assert_not_contains "$statusline_body" 'claude_secondary) key=' \
  "statusline に固定の環境名の写像が残っていない"

# --- 環境名がソースに漏れていない ---
assert_not_contains "$(cat "$CHEZMOI_SOURCE/private_dot_config/sketchybar/items/usage.lua.tmpl")" \
  "secondary" "usage.lua.tmpl に固定の環境名が残っていない"

# --- statusline の fallback キーがウィジェットの読むキーと一致する ---
# AGENT_ENV_SESSION は Claude Code から起動された statusline には届くが、
# 届かない経路では以前 basename をキーにしていた。usage.sh が読むのは
# <session>-claude なので、basename のままだとウィジェットからは永久に読まれない。
statusline_rendered="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/private_dot_config/claude/executable_statusline.sh.tmpl" 2>/dev/null)"
assert_contains "$statusline_rendered" 'key="default-claude"' \
  "statusline: AGENT_ENV_SESSION が無いときは先頭環境の session でキーを作る"
assert_not_contains "$statusline_rendered" 'basename "$CLAUDE_CONFIG_DIR"' \
  "statusline: fallback で basename を使わない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
