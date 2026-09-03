# レシピが読み込む補助関数。mad-run が export した変数を前提にする。
# MAD_RUN_DIR / MAD_RUN_ID / MAD_TIMEOUT / MAD_DRY_RUN / MAD_SCRIPTS

# レシピが受け取る引数名を宣言する。第 1 引数は必須、第 2 引数は省略可で、
# どちらも空白区切りの並びである。宣言に無いキーと必須の欠落は 2 で終わる。
# MAD_SPEC_ONLY=1 のときは宣言だけを出して終わる。
mad_declare() {
  MAD_REQUIRED="${1-}"
  MAD_OPTIONAL="${2-}"
  if [ "${MAD_SPEC_ONLY:-0}" = "1" ]; then
    printf 'required=%s\n' "$MAD_REQUIRED"
    printf 'optional=%s\n' "$MAD_OPTIONAL"
    exit 0
  fi
  local known=" $MAD_REQUIRED $MAD_OPTIONAL " k
  for k in $(jq -r 'keys[]' "$MAD_RUN_DIR/args.json"); do
    case "$known" in
      *" $k "*) ;;
      *)
        printf 'mad-lib: 未知の引数 %s。受け取るのは%s\n' "$k" "$known" >&2
        exit 2 ;;
    esac
  done
  for k in $MAD_REQUIRED; do
    if [ -z "$(jq -r --arg n "$k" '.[$n] // empty' "$MAD_RUN_DIR/args.json")" ]; then
      printf 'mad-lib: 引数 %s が要る\n' "$k" >&2
      exit 2
    fi
  done
}

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

mad_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ノードの状態を 1 ファイルに書く。並行するノードが同じファイルを取り合わない。
mad_state_write() {
  printf 'state=%s\nrole=%s\nworkspace=%s\nstartedAt=%s\nfinishedAt=%s\n' \
    "$2" "$3" "$4" "$5" "$6" > "$MAD_RUN_DIR/$1.state"
}

# run.json の base を書き換える。worktree を作るレシピが 1 回呼ぶ。
mad_record_base() {
  local f="$MAD_RUN_DIR/run.json"
  [ -f "$f" ] || return 0
  jq --arg b "$1" '.base = $b' "$f" > "$f.$$" && mv -f "$f.$$" "$f"
}

# 書いてあるプロンプトでノードを走らせる。第 3 引数に workspace の id を渡すと、
# その workspace の中で動かす。
mad_run_node() {
  local name="$1" role="$2" ws="${3-}"
  local pf="$MAD_RUN_DIR/$name.prompt"
  local of="$MAD_RUN_DIR/$name.json"
  local lf="$MAD_RUN_DIR/$name.log"
  local started
  started="$(mad_now)"
  mad_state_write "$name" running "$role" "$ws" "$started" ""
  if [ "${MAD_DRY_RUN:-0}" = "1" ]; then
    # 失敗しても出力ファイルは作る。mad_collect が読む先を欠かさないため。
    local route
    printf '{}\n' > "$of"
    route="$("$MAD_SCRIPTS/mad-route" "$role")" || {
      mad_state_write "$name" failed "$role" "$ws" "$started" "$(mad_now)"
      printf 'mad-lib: ノード %s（役割 %s）の provider を解決できない\n' "$name" "$role" >&2
      return 1
    }
    mad_state_write "$name" ok "$role" "$ws" "$started" "$(mad_now)"
    printf 'node=%s role=%s %s workspace=%s prompt_chars=%s\n' \
      "$name" "$role" "$route" "${ws:-none}" "$(wc -c < "$pf" | tr -d ' ')"
    return 0
  fi
  set -- --role "$role" --prompt-file "$pf" --out "$of" --log "$lf" \
    --timeout "$MAD_TIMEOUT" --title "mad/$MAD_RUN_ID/$name"
  if [ -n "$ws" ]; then
    set -- "$@" --workspace "$ws"
  else
    set -- "$@" --cwd "$PWD"
  fi
  "$MAD_SCRIPTS/mad-agent" "$@"
  local status=$?
  if [ "$status" -eq 0 ]; then
    mad_state_write "$name" ok "$role" "$ws" "$started" "$(mad_now)"
  else
    mad_state_write "$name" failed "$role" "$ws" "$started" "$(mad_now)"
    # 失敗したノードの名前を出す。背景で走る分もここを通る。
    printf 'mad-lib: ノード %s（役割 %s）が失敗した。ログ: %s\n' "$name" "$role" "$lf" >&2
  fi
  return "$status"
}

# 走っているノードが上限に達している間、空きを待つ。bash 3.2 に wait -n が無い。
mad_wait_slot() {
  local limit="${MAD_MAX_PARALLEL:-4}" alive pid
  while :; do
    alive=0
    for pid in ${MAD_JOBS:-}; do
      kill -0 "$pid" 2>/dev/null && alive=$((alive + 1))
    done
    [ "$alive" -lt "$limit" ] && return 0
    sleep 1
  done
}

# ノードを背景で走らせる。dry-run のときは順に走らせる。
mad_start_node() {
  MAD_NODES="${MAD_NODES:-} $1"
  if [ "${MAD_DRY_RUN:-0}" = "1" ]; then
    mad_run_node "$1" "$2" "${3-}" || MAD_FAILED=1
    return 0
  fi
  mad_wait_slot
  mad_run_node "$1" "$2" "${3-}" &
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
# 呼ぶ前に mad_join が成功していること。失敗したノードがあるまま呼ばない。
mad_collect() {
  local acc="[]" name
  for name in ${MAD_NODES:-}; do
    acc="$(printf '%s' "$acc" | jq -c --arg n "$name" \
      --slurpfile o "$MAD_RUN_DIR/$name.json" '. + [{node: $n, output: $o[0]}]')" || {
      printf 'mad-lib: ノード %s の出力を JSON として読めない\n' "$name" >&2
      MAD_NODES=""
      return 1
    }
  done
  MAD_NODES=""
  printf '%s' "$acc"
}
