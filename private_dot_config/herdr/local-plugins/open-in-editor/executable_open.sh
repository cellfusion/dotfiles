#!/usr/bin/env bash
# Link-handler action: fired when a matching file link/path is clicked in a pane.
# Resolves it to an absolute <path>[:<line>] and opens it in nvim (overlay popup).
set -euo pipefail

url="${HERDR_PLUGIN_CLICKED_URL:-}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

# 実際に渡ってくる URL/context を採取（形が確定したら削ってよい）。
log="${HERDR_PLUGIN_CONFIG_DIR:-/tmp}/clicks.log"
printf '%s\turl=%s\tctx=%s\n' \
  "$(date '+%F %T' 2>/dev/null || echo -)" "$url" "$ctx" >>"$log" 2>/dev/null || true

[ -n "$url" ] || exit 0

# file:// スキームを剥がす: file:///abs -> /abs
path="${url#file://}"
line=""

# 行番号の抽出: #L42 / #42 / ?line=42
case "$path" in
  *'#L'*) line="${path##*#L}"; path="${path%#L*}" ;;
  *'#'*)  frag="${path##*#}"; [[ "$frag" =~ ^[0-9]+$ ]] && { line="$frag"; path="${path%#*}"; } ;;
esac
case "$path" in
  *'?'*) q="${path#*\?}"; path="${path%%\?*}"; [[ "$q" =~ line=([0-9]+) ]] && line="${BASH_REMATCH[1]}" ;;
esac

# %XX の URL デコード
path="$(printf '%b' "${path//%/\\x}")"

# 相対パス / ~ を解決するための基準 cwd。クリック元 pane の foreground_cwd を最優先。
base=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  base="$(printf '%s' "$ctx" | jq -r '.workspace_cwd // empty' 2>/dev/null || true)"
  pane="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)"
  if [ -n "$pane" ]; then
    pcwd="$(herdr pane list 2>/dev/null \
      | jq -r --arg p "$pane" '.result.panes[]? | select(.pane_id==$p) | .foreground_cwd // .cwd' 2>/dev/null \
      | head -1)"
    [ -n "$pcwd" ] && base="$pcwd"
  fi
fi
[ -n "$base" ] || base="$HOME"

# ~ 展開 → 相対を絶対化
case "$path" in
  '~/'*) path="$HOME/${path#\~/}" ;;
  '~')   path="$HOME" ;;
esac
case "$path" in
  /*) : ;;
  *)  path="$base/$path" ;;
esac

# 絶対化後の末尾 :42（デコード後に判定。:42 を外した側が実在する時だけ行番号扱い）
if [[ -z "$line" && "$path" =~ ^(.*):([0-9]+)$ ]]; then
  if [[ ! -e "$path" && -e "${BASH_REMATCH[1]}" ]]; then
    path="${BASH_REMATCH[1]}"; line="${BASH_REMATCH[2]}"
  fi
fi

# 実在するファイルの時だけ開く（ディレクトリ・非ファイル・誤マッチは無視）
[ -f "$path" ] || exit 0

herdr plugin pane open \
  --plugin open-in-editor --entrypoint editor --placement overlay \
  --env EDIT_FILE="$path" --env EDIT_LINE="$line" --focus \
  >/dev/null 2>&1 || true
