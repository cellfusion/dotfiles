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
STATUSLINE_SH="$CHEZMOI_SOURCE/private_dot_config/claude/executable_statusline.sh"
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
assert_not_contains "$statusline" 'sketchybar-usage' \
  "statusline はキャッシュのパスを持たない"
assert_not_contains "$statusline" 'AGENT_ENV_SESSION' \
  "statusline は環境名を解決しない"

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

# --- statusline は使用量キャッシュを書かない ---
# 書き手は usage_collect_claude.sh だけにする。statusline は Paseo の非対話
# モードでは実行されないうえ、herdr の外では AGENT_ENV_SESSION が先頭環境の
# ままになるため、別の環境の枠へ書く余地があった。
statusline_body="$(cat "$STATUSLINE_SH")"
assert_not_contains "$statusline_body" 'dump_usage_cache' \
  "statusline: 使用量を書き出す関数を残さない"
assert_not_contains "$statusline_body" 'sketchybar' \
  "statusline: SketchyBar 連携の記述を残さない"
assert_not_contains "$statusline_body" '{{' \
  "statusline: 環境定義を埋め込まなくなったのでテンプレート構文が無い"
assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_config/claude/executable_statusline.sh" ] && echo yes)" "yes" \
  "statusline: テンプレートではない実体として置く"
assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_config/claude/executable_statusline.sh.tmpl" ] && echo yes)" "" \
  "statusline: .tmpl を残さない"

# --- 環境名がソースに漏れていない ---
assert_not_contains "$(cat "$CHEZMOI_SOURCE/private_dot_config/sketchybar/items/usage.lua.tmpl")" \
  "secondary" "usage.lua.tmpl に固定の環境名が残っていない"

# --- Claude の使用量を採取する usage_collect_claude.sh ---
# Paseo は Claude Code を非対話モードで起動する。statusLine は対話 UI の描画時にしか
# 動かないので、launchd から回す採取スクリプトがキャッシュを書く唯一の経路になる。
# 背景は private_dot_config/docs/sketchybar-usage.md にある。
COLLECT_SH="$(mktemp)"
chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/private_dot_config/sketchybar/helpers/executable_usage_collect_claude.sh.tmpl" \
  > "$COLLECT_SH"
chmod +x "$COLLECT_SH"
trap 'rm -f "$USAGE_SH" "$cfg" "$COLLECT_SH"; rm -rf "$fixture_home"' EXIT

# /usage は「resets Sep 3 at 6:59pm」の形で出し、年を書かない。3 日後の日時で
# 組み立てて、秒を落とした epoch と一致するかを見る。
usage_target=$(( $(date +%s) + 259200 ))
usage_expect=$(( usage_target - usage_target % 60 ))
usage_day="$(LC_ALL=C date -r "$usage_target" '+%b %d')"
usage_time="$(LC_ALL=C date -r "$usage_target" '+%I:%M' | sed 's/^0//')$(LC_ALL=C date -r "$usage_target" '+%p' | tr '[:upper:]' '[:lower:]')"

usage_text=$(cat <<TXT
You are currently using your subscription to power your Claude Code usage

Current session: 13% used · resets $usage_day at $usage_time (Asia/Tokyo)
Current week (all models): 42% used · resets $usage_day at $usage_time (Asia/Tokyo)
Current week (Fable): 0% used
TXT
)

assert_eq "$(printf '%s\n' "$usage_text" | "$COLLECT_SH" parse)" \
  "$(printf '42\t%s' "$usage_expect")" "採取: 週次の使用率とリセット時刻を取り出す"

# 5 時間の窓（Current session）や Fable の行を拾うと、別の数字と時刻が入る。
assert_not_contains "$(printf '%s\n' "$usage_text" | "$COLLECT_SH" parse)" "13" \
  "採取: 5 時間の窓の使用率を週次として拾わない"

# 分がちょうどのとき /usage は「7pm」と分を省く。date -j は書式に無い項目を
# 現在時刻で埋めるため、分のある書式で読むと分が実行時刻の分になる。
hour_expect=$(( usage_target - usage_target % 3600 ))
hour_day="$(LC_ALL=C date -r "$hour_expect" '+%b %d')"
hour_time="$(LC_ALL=C date -r "$hour_expect" '+%I' | sed 's/^0//')$(LC_ALL=C date -r "$hour_expect" '+%p' | tr '[:upper:]' '[:lower:]')"
assert_eq "$(printf 'Current week (all models): 42%% used · resets %s at %s (Asia/Tokyo)\n' "$hour_day" "$hour_time" | "$COLLECT_SH" parse)" \
  "$(printf '42\t%s' "$hour_expect")" "採取: 分を省いた書き方のリセット時刻を読む"

no_week=$(cat <<TXT
You are currently using your subscription to power your Claude Code usage

Current session: 13% used · resets $usage_day at $usage_time (Asia/Tokyo)
TXT
)
no_week_out=$(printf '%s\n' "$no_week" | "$COLLECT_SH" parse)
no_week_rc=$?
assert_eq "$no_week_rc" "1" "採取: 週次の行が無ければ失敗を返す"
assert_eq "$no_week_out" "" "採取: 取れなかったときは何も出さない"

no_reset_out=$(printf 'Current week (all models): 42%% used\n' | "$COLLECT_SH" parse)
no_reset_rc=$?
assert_eq "$no_reset_rc" "1" "採取: リセット時刻が無ければ失敗を返す"
assert_eq "$no_reset_out" "" "採取: リセット時刻が無ければ何も出さない"

printf '%s\n' "$usage_text" | HOME="$fixture_home" "$COLLECT_SH" record default-claude
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" claude "$fixture_home/.config/claude" default-claude)" \
  "$(printf '42\t%s\tok' "$usage_expect")" "採取: 書いたキャッシュを usage.sh が ok として読む"

kept_cache=$(cat "$fixture_home/.cache/sketchybar-usage/default-claude.json")
printf '%s\n' "$no_week" | HOME="$fixture_home" "$COLLECT_SH" record default-claude
record_rc=$?
assert_eq "$record_rc" "1" "採取: 取れなかった環境では失敗を返す"
assert_eq "$(cat "$fixture_home/.cache/sketchybar-usage/default-claude.json")" "$kept_cache" \
  "採取: 取れなかった環境のキャッシュは書き換えない"

# 環境とキャッシュキーの対応を確かめる。Paseo は provider ごとに CLAUDE_CONFIG_DIR
# だけを差し替え、AGENT_ENV_SESSION は先頭環境の値のまま渡す。採取スクリプトが
# 実行時の AGENT_ENV_SESSION を見ていると、2 つ目の環境の値が先頭環境の枠に入る。
fake_claude="$fixture_home/fake-claude"
cat > "$fake_claude" <<'FAKE'
#!/bin/sh
case "${CLAUDE_CONFIG_DIR##*/}" in
  claude) u=11 ;;
  claude_work) u=22 ;;
  claude_solo) u=33 ;;
  *) u=0 ;;
esac
printf 'Current week (all models): %s%% used · resets %s at %s (Asia/Tokyo)\n' \
  "$u" "$FAKE_DAY" "$FAKE_TIME"
# launchd では PATH に node が無く、プラグインのフックが毎回落ちる。
printf 'SessionEnd hook [node "x.mjs" SessionEnd] failed: node: command not found\n' >&2
printf 'Auth error: token expired\n' >&2
printf '\n' >&2
FAKE
chmod +x "$fake_claude"
mkdir -p "$fixture_home/.config/claude" "$fixture_home/.config/claude_work"
rm -f "$fixture_home/.cache/sketchybar-usage/default-claude.json" \
  "$fixture_home/.cache/sketchybar-usage/work-claude.json" \
  "$fixture_home/.cache/sketchybar-usage/solo-claude.json"
collect_stderr="$fixture_home/collect.stderr"
HOME="$fixture_home" USAGE_CLAUDE_BIN="$fake_claude" \
  FAKE_DAY="$usage_day" FAKE_TIME="$usage_time" "$COLLECT_SH" >/dev/null 2>"$collect_stderr"
collect_rc=$?
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" claude "$fixture_home/.config/claude" default-claude)" \
  "$(printf '11\t%s\tok' "$usage_expect")" "採取: 先頭環境の値を default-claude に書く"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" claude "$fixture_home/.config/claude_work" work-claude)" \
  "$(printf '22\t%s\tok' "$usage_expect")" "採取: 2 つ目の環境の値を work-claude に書く"
assert_eq "$(HOME="$fixture_home" "$USAGE_SH" claude "$fixture_home/.config/claude_solo" solo-claude)" \
  "$(printf -- '-\t-\terror')" "採取: 設定ディレクトリが無い環境は飛ばす"
assert_eq "$collect_rc" "1" "採取: 失敗した環境があれば終了ステータスで知らせる"

# 採取に影響しないフックの失敗で launchd の err.log を埋めない。ただし他の
# 失敗は残す。両方落とすと認証切れの原因が分からなくなる。
assert_not_contains "$(cat "$collect_stderr")" 'SessionEnd hook' \
  "採取: フックの失敗はログへ流さない"
assert_contains "$(cat "$collect_stderr")" 'Auth error: token expired' \
  "採取: フック以外の失敗はログへ流す"
# 残るのは、設定ディレクトリが有る 2 環境の Auth error と、無い 1 環境を
# 飛ばした知らせの 3 行だけである。空行が残ると 15 分ごとに 2 行ずつ増える。
assert_eq "$(wc -l < "$collect_stderr" | tr -d ' ')" "3" \
  "採取: ログに空行を残さない"

collect_body="$(cat "$COLLECT_SH")"
assert_contains "$collect_body" 'collect_env "$HOME/.config/claude" default-claude' \
  "採取: 先頭環境はサフィックス無しのパスを見る"
assert_contains "$collect_body" 'collect_env "$HOME/.config/claude_work" work-claude' \
  "採取: 2 つ目の環境は suffix 付きのパスを見る"
assert_contains "$collect_body" 'collect_env "$HOME/.config/claude_solo" solo-claude' \
  "採取: 3 つ目の環境は suffix 付きのパスを見る"
assert_not_contains "$collect_body" 'AGENT_ENV_SESSION' \
  "採取: 実行時の AGENT_ENV_SESSION に依存しない"
assert_not_contains "$collect_body" 'codex' \
  "採取: Codex は sessions のログから読むので採取しない"
# /usage は Claude Code の中で処理され、モデルへのリクエストを出さない。
# 通常のプロンプトを送る形に戻すと、採取のたびに使用量そのものが増える。
assert_contains "$collect_body" '-p /usage' "採取: モデルを呼ばない /usage を使う"
# launchd から動かすと stdin が繋がっていない。閉じずに呼ぶと claude が 3 秒待って
# 「no stdin data received」を出し、環境ごとに待ち時間が増える。
assert_contains "$collect_body" '< /dev/null' "採取: stdin を閉じて呼ぶ"
assert_not_contains "$collect_body" '--model' "採取: モデルを指定しない"

# --- 採取を回す launchd ジョブ ---
usage_plist="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/Library/LaunchAgents/com.cellfusion.sketchybar-usage-claude.plist.tmpl")"
assert_contains "$usage_plist" '<string>com.cellfusion.sketchybar-usage-claude</string>' \
  "plist: Label を固定する"
assert_contains "$usage_plist" '/.config/sketchybar/helpers/usage_collect_claude.sh' \
  "plist: 採取スクリプトを実行する"
assert_contains "$usage_plist" '<key>StartInterval</key>' "plist: 定期実行にする"
assert_contains "$usage_plist" '<integer>900</integer>' "plist: 15 分ごとに実行する"
assert_contains "$usage_plist" 'sketchybar-usage-claude.err.log' "plist: 失敗を記録する"
plist_file="$(mktemp)"
printf '%s\n' "$usage_plist" > "$plist_file"
plutil -lint "$plist_file" >/dev/null 2>&1
assert_eq "$?" "0" "plist: plutil の検査を通る"
rm -f "$plist_file"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
