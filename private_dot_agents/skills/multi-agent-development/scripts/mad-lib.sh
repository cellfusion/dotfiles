# レシピが読み込む補助関数。mad-run が export した変数を前提にする。
# MAD_RUN_DIR / MAD_RUN_ID / MAD_TIMEOUT / MAD_DRY_RUN / MAD_SCRIPTS

# 文字列の引数を取り出す。第 2 引数は既定値。
mad_arg() {
  jq -r --arg n "$1" --arg d "${2-}" '.[$n] // $d' "$MAD_RUN_DIR/args.json"
}

# 配列の引数を JSON 配列で取り出す。渡された値は JSON 配列の文字列として読む。
mad_arg_array() {
  local v
  v="$(jq -r --arg n "$1" '.[$n] // empty' "$MAD_RUN_DIR/args.json")"
  if [ -z "$v" ]; then
    printf '%s' "$2"
    return 0
  fi
  if ! printf '%s' "$v" | jq -ce 'type == "array"' >/dev/null 2>&1; then
    printf 'mad-lib: 引数 %s が JSON 配列ではない\n' "$1" >&2
    return 1
  fi
  printf '%s' "$v" | jq -c .
}

# ノードのプロンプトを標準入力から書く。
mad_prompt() {
  cat > "$MAD_RUN_DIR/$1.prompt"
}

# 書いてあるプロンプトでノードを走らせる。
mad_run_node() {
  local name="$1" role="$2"
  local pf="$MAD_RUN_DIR/$name.prompt"
  local of="$MAD_RUN_DIR/$name.json"
  local lf="$MAD_RUN_DIR/$name.log"
  if [ "${MAD_DRY_RUN:-0}" = "1" ]; then
    local route
    route="$("$MAD_SCRIPTS/mad-route" "$role")" || return 1
    printf 'node=%s role=%s %s prompt_chars=%s\n' \
      "$name" "$role" "$route" "$(wc -c < "$pf" | tr -d ' ')"
    printf '{}\n' > "$of"
    return 0
  fi
  "$MAD_SCRIPTS/mad-agent" --role "$role" --prompt-file "$pf" --cwd "$PWD" \
    --out "$of" --log "$lf" --timeout "$MAD_TIMEOUT" --title "mad/$MAD_RUN_ID/$name"
}

# ノードを背景で走らせる。dry-run のときは順に走らせる。
mad_start_node() {
  MAD_NODES="${MAD_NODES:-} $1"
  if [ "${MAD_DRY_RUN:-0}" = "1" ]; then
    mad_run_node "$1" "$2" || MAD_FAILED=1
    return 0
  fi
  mad_run_node "$1" "$2" &
  MAD_JOBS="${MAD_JOBS:-} $!"
}

# 背景のノードをすべて待つ。1 つでも失敗したら非ゼロで返す。
mad_join() {
  local pid rc="${MAD_FAILED:-0}"
  for pid in ${MAD_JOBS:-}; do
    wait "$pid" || rc=1
  done
  MAD_JOBS=""
  MAD_FAILED=0
  [ "$rc" = "0" ]
}

# 走らせたノードの出力を 1 つの JSON 配列にまとめる。
mad_collect() {
  local acc="[]" name
  for name in ${MAD_NODES:-}; do
    acc="$(printf '%s' "$acc" | jq -c --arg n "$name" \
      --slurpfile o "$MAD_RUN_DIR/$name.json" '. + [{node: $n, output: $o[0]}]')"
  done
  MAD_NODES=""
  printf '%s' "$acc"
}
