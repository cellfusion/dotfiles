#!/usr/bin/env bash
# MAD の research レシピが Paseo MCP で成立するかを確かめる。
# 手動実行専用であり、run-tests.sh の対象外である（tests/manual/ にあるため）。
#
#   bash tests/manual/mad-orchestration-smoke.sh --help       使い方だけを出す
#   bash tests/manual/mad-orchestration-smoke.sh --dry-run    手順を出すだけで何も作らない
#   bash tests/manual/mad-orchestration-smoke.sh              backend を選び run を用意する
#   bash tests/manual/mad-orchestration-smoke.sh --report DIR 実行済み run を検証して結果を出す
#
# fixture test は state と成果物の形しか見ない。実 backend で子が 1 つも起動しない
# まま全部緑になる穴が残る。child の create、wait、stop は adapter が MCP transport
# の境界を担う。そのため、このスクリプトはシェルで確かめられる部分だけを実行し、
# 親エージェントが行う手順は出力として示す。
set -u

MODE=run
REPORT_DIR=""

case "${1:-}" in
  --help | -h) MODE=help ;;
  --dry-run) MODE=dry ;;
  --report)
    MODE=report
    REPORT_DIR="${2:-}"
    if [ -z "$REPORT_DIR" ]; then
      printf 'mad-orchestration-smoke: --report は run ディレクトリを 1 つ取る\n' >&2
      exit 2
    fi
    ;;
  "") MODE=run ;;
  *)
    printf 'mad-orchestration-smoke: 未知の引数: %s\n' "$1" >&2
    exit 2
    ;;
esac

say() { printf '\n## %s\n' "$*" >&2; }
note() { printf '%s\n' "$*" >&2; }

usage() {
  cat >&2 <<'USAGE'
MAD の research レシピを実 backend で 1 度通すための手動 smoke。

  bash tests/manual/mad-orchestration-smoke.sh --help
      使い方だけを出す。

  bash tests/manual/mad-orchestration-smoke.sh --dry-run
      backend の選び方、3 子の起動、親の gate、統合、観測、停止の手順を出す。
      ファイルを作らず、子も起動しない。

  bash tests/manual/mad-orchestration-smoke.sh
      backend を選び、run ディレクトリと初期 state.json を作り、親が行う手順を出す。

  bash tests/manual/mad-orchestration-smoke.sh --report RUN_DIR
      実行済みの run を成果物契約の validator にかけ、backend、run ID、
      node ごとの採用 attempt と状態、統合成果物の絶対パスを出す。

環境変数:
  MAD_VALIDATE
      manual-orchestration-validate の場所を差し替える。
USAGE
}

# 成果物契約の validator を探す。chezmoi apply 前は ~/.agents に配布されていない
# ので、その場合はリポジトリのソース側を使う。
resolve_validator() {
  local installed="$HOME/.agents/skills/multi-agent-development/scripts/manual-orchestration-validate"
  local source_copy
  source_copy="$(cd "$(dirname "$0")/../.." && pwd)"
  source_copy="$source_copy/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"

  if [ -n "${MAD_VALIDATE:-}" ]; then
    printf '%s\n' "$MAD_VALIDATE"
  elif [ -x "$installed" ]; then
    printf '%s\n' "$installed"
  else
    printf '%s\n' "$source_copy"
  fi
}

# Paseo MCP が届くことを確認する。届かない場合は run を開始しない。
select_backend() {
  local validator="$1"
  if ! command -v paseo >/dev/null 2>&1 || ! paseo status >/dev/null 2>&1; then
    printf 'mad-orchestration-smoke: Paseo MCP が利用できないため run を開始しない\n' >&2
    return 1
  fi
  MANUAL_ORCHESTRATION_PASEO_MCP_AVAILABLE=1 bash "$validator" --select-backend
}

print_procedure() {
  say "1. Paseo MCP backend を確認する"
  note 'paseo status で daemon に届くことを確かめてから selector を叩く。'
  note '  MANUAL_ORCHESTRATION_PASEO_MCP_AVAILABLE=1 manual-orchestration-validate --select-backend'
  note '  → {"backend":"paseo-mcp","backend_reason":"Paseo MCP available"}'
  note 'Paseo MCP が利用できなければ run を開始しない。開始済みの子が失敗しても別 backend へ'
  note '自動で切り替えない。失敗した子は再指示、再実行、停止のいずれかを親が裁定する。'

  say "2. run ディレクトリを作り、run ID を発行する"
  note '  RUN_DIR="$(agent-docs-dir "orchestration/$RUN_ID")"'
  note 'run 全体の状態は $RUN_DIR/state.json だけに置く。子の成果物は'
  note '$RUN_DIR/nodes/<node-id>/attempts/<attempt-id>/ に分ける。'
  note 'state.json の recipe は research、phase は research、backend は 1 で選んだ値にする。'
  note 'launch の解決には generate-paseo-config resolve を使う。'

  say "3. research の子を 3 つ並列に起動する"
  note '既定の 3 観点は次のとおりであり、node ID と 1 対 1 に対応する。'
  note '  research-1: 現状と確認済みの事実'
  note '  research-2: 制約とリスク'
  note '  research-3: 代替案'
  note '3 つは依存しないので同時に起動する。役割はいずれも researcher である。'
  note ''
  note 'wait と stop の境界はすべて paseo-mcp-adapter に限定する。create の境界は'
  note '公式 MCP tool の mcp__paseo__create_agent だけであり、adapter は create の'
  note 'subcommand を持たない。子ごとに次の順で進める。'
  note '  1. manual-orchestration-validate --exercise-success が launch を検証し、'
  note '     mode 0600 の mcp-create.json を書いて停止する。'
  note '  2. 親が mcp-create.json を assertMadCreateRequestV1 で再検証する。'
  note '     request を検証してから create を呼ぶ。検証を通らなければ create しない。'
  note '  3. manual-orchestration-validate --prepare-create が同じ request を検証し、'
  note '     create の前に一回性 marker を取る。marker を取れた呼び出しだけが次へ進む。'
  note '  4. 親が mcp__paseo__create_agent を子ごとに一回だけ呼ぶ。引数は'
  note '     mcp-create.json の 6 key をそのまま渡し、値を作り直さない。'
  note '  5. manual-orchestration-validate --exercise-accepted が prepare marker を確かめ、'
  note '     accepted response を検証して childRef と create_accepted だけを'
  note '     0600 の state へ保存する。この境界は marker を作らない。'
  note '3 回の create を 1 つの応答にまとめて並列に起動する。prompt には'
  note '$RUN_DIR/nodes/<node-id>/attempts/<attempt-id>/ へ prompt.md、result.json、'
  note 'state.json、handoff.json、log.md を書くことを含める。'
  note 'raw response、活動履歴、inspect 出力は state にも log にも保存しない。'
  note ''
  say "4. 子の実行を観測する"
  note '親は各 childRef に対して adapter の wait-agent を一回だけ呼ぶ。'
  note '  paseo-mcp-adapter wait-agent --child-ref <safe-id> --timeout <seconds>'
  note 'adapter は Paseo の応答を検証し、親へ sanitized response の status だけを返す。'
  note '親は raw の agent status、詳細、activity、ログを取得しない。'
  note ''
  note '正本は run ディレクトリの以下 2 つである。'
  note '  $RUN_DIR/state.json'
  note '  $RUN_DIR/nodes/<node-id>/attempts/<attempt-id>/state.json'
  note '子の本文を親の会話へ転記しない。親が読むのは adapter の sanitized response と'
  note 'mode 0600 の state/evidence だけである。state/attempt の設計と handoff は維持する。'

  say "5. 親が gate を置く"
  note 'research-1、research-2、research-3 の採用 attempt が 3 件すべてが ok に'
  note 'なるまで、統合役を起動してはならない。1 つでも failed または stopped なら、'
  note 'run の state を failed または stopped にして止める。'
  note '親は確認した内容を run state の parent_decision に書き、採用した attempt を'
  note 'adopted_attempts に node ID から attempt ID への map として書く。'

  say "6. 統合役を起動する"
  note 'node ID は synthesis、役割は synthesizer である。'
  note '入力は 3 子の採用 attempt の handoff.json が持つ artifact_paths だけであり、'
  note '絶対パスだけを渡す。調査結果の本文を親の会話へ転記しない。'
  note 'synthesis が ok になったら、統合成果物の絶対パスを run state の'
  note 'artifact_paths に入れ、completed_nodes に 4 つの node をすべて並べる。'

  say "7. 成果物契約を検証する"
  note '  manual-orchestration-validate "$RUN_DIR"'
  note 'この検証は Paseo MCP の実ツールを呼ばず、作られた state と成果物だけを見る。'
  note 'research では synthesis が completed_nodes と adopted_attempts の両方に'
  note '無いと失敗する。3 子が ok になる前に後段の node があっても失敗する。'
  note 'validator が失敗した run を ok にしてはならない。'
  note '実行後は次で結果をまとめて出せる。'
  note '  bash tests/manual/mad-orchestration-smoke.sh --report "$RUN_DIR"'

  say "8. 途中で止める"
  note '実行中の子は adapter の stop-agent だけで止める。'
  note '  paseo-mcp-adapter stop-agent --child-ref <safe-id>'
  note 'adapter は stop response の agent ID が childRef と一致することを検証し、'
  note '親へ sanitized response の {"status":"stopped"} または {"status":"error"} だけを返す。'
  note '親は raw の停止 response を保存・転記せず、0600 の state/evidence に結果を記録する。'
  note ''
  note '止めた事実を run state に残す。'
  note '  "state": "stopped"'
  note '  "phase_state": "stopped"'
  note '  parent_decision に停止の理由を書く'
  note '止めた run のディレクトリは rm -rf "$RUN_DIR" で消してよい。'
  note 'run ディレクトリはリポジトリの作業ツリーの外にあるので、リポジトリには残らない。'

  say "期待する結果"
  note '1. backend が paseo-mcp に 1 度だけ決まること'
  note '2. research-1、research-2、research-3 の 3 子が同時に走ること'
  note '3. 3 子が ok になるまで synthesis が起動しないこと'
  note '4. synthesis が 3 子の artifact_paths だけを入力に取ること'
  note '5. manual-orchestration-validate が run ディレクトリを valid と出すこと'
  note '6. 子の調査本文が親の会話に転記されていないこと'
}

print_prerequisites() {
  say "前提"
  note 'chezmoi apply を済ませ、~/.agents に multi-agent-development の scripts が'
  note '配布されていること。未配布ならこのスクリプトはリポジトリのソース側の'
  note 'validator を使う。'
  note 'jq が入っていること。validator が jq を使う。'
  note 'Paseo アプリが起動し daemon が動いていること。'
}

case "$MODE" in
  help)
    usage
    exit 0
    ;;

  dry)
    VALIDATOR="$(resolve_validator)"
    say "dry run"
    note 'ファイルは作らず、子も起動しない。以下は実行時に行う手順である。'
    printf 'validator: %s\n' "$VALIDATOR" >&2
    print_prerequisites
    print_procedure

    say "merge 前に回す"
    note '1. bash tests/run-tests.sh'
    note '2. bash tests/manual/mad-orchestration-smoke.sh --dry-run'
    note '3. Paseo daemon が動く実機で bash tests/manual/mad-orchestration-smoke.sh を'
    note '   1 度通し、上の「期待する結果」6 件を目で確かめる'
    exit 0
    ;;

  report)
    VALIDATOR="$(resolve_validator)"
    if [ ! -d "$REPORT_DIR" ]; then
      printf 'mad-orchestration-smoke: run ディレクトリが無い: %s\n' "$REPORT_DIR" >&2
      exit 1
    fi
    RUN_DIR="$(cd "$REPORT_DIR" && pwd -P)"
    RUN_STATE="$RUN_DIR/state.json"

    say "成果物契約の検証"
    printf 'manual-orchestration-validate "%s"\n' "$RUN_DIR" >&2
    if ! bash "$VALIDATOR" "$RUN_DIR"; then
      printf 'mad-orchestration-smoke: validator が失敗した。この run を ok にしない\n' >&2
      exit 1
    fi

    say "run の要約"
    jq -r '
      "run ID:   \(.run_id)",
      "recipe:   \(.recipe)",
      "backend:  \(.backend) (\(.backend_reason))",
      "state:    \(.state) / phase \(.phase) \(.phase_state)",
      "決定:     \(.parent_decision)",
      "次の処理: \(.next_action)"
    ' "$RUN_STATE" >&2

    say "node ごとの採用 attempt と状態"
    while IFS=$'\t' read -r node attempt; do
      attempt_state="$RUN_DIR/nodes/$node/attempts/$attempt/state.json"
      if [ -f "$attempt_state" ]; then
        printf '%-12s %-16s %s\n' "$node" "$attempt" "$(jq -r '.state' "$attempt_state")" >&2
      else
        printf '%-12s %-16s (attempt state が無い)\n' "$node" "$attempt" >&2
      fi
    done < <(jq -r '.adopted_attempts | to_entries[] | [.key, .value] | @tsv' "$RUN_STATE")

    say "統合成果物"
    synthesis_attempt="$(jq -r '.adopted_attempts.synthesis // empty' "$RUN_STATE")"
    if [ -n "$synthesis_attempt" ]; then
      jq -r '.artifact_paths[]' \
        "$RUN_DIR/nodes/synthesis/attempts/$synthesis_attempt/handoff.json" >&2
    else
      note 'synthesis の採用 attempt がまだ無い。'
    fi

    say "run 全体の artifact_paths"
    jq -r '.artifact_paths[]' "$RUN_STATE" >&2

    say "後片付け"
    printf 'rm -rf %s\n' "$RUN_DIR" >&2
    exit 0
    ;;

  run)
    VALIDATOR="$(resolve_validator)"
    printf 'validator: %s\n' "$VALIDATOR" >&2
    if [ ! -f "$VALIDATOR" ]; then
      printf 'mad-orchestration-smoke: validator が無い: %s\n' "$VALIDATOR" >&2
      exit 1
    fi
    command -v jq >/dev/null 2>&1 || {
      printf 'mad-orchestration-smoke: jq が要る\n' >&2
      exit 1
    }

    say "backend を選ぶ"
    BACKEND_JSON="$(select_backend "$VALIDATOR")" || exit 1
    printf '%s\n' "$BACKEND_JSON" >&2
    BACKEND="$(printf '%s' "$BACKEND_JSON" | jq -r '.backend')"
    BACKEND_REASON="$(printf '%s' "$BACKEND_JSON" | jq -r '.backend_reason')"

    say "run ディレクトリを作る"
    RUN_ID="mad-smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    RUN_DIR="$(bash "$HOME/.agents/skills/_shared/scripts/agent-docs-dir" \
      "orchestration/$RUN_ID")" || exit 1
    ( umask 077; mkdir -p "$RUN_DIR/nodes" ) || exit 1
    chmod 700 "$RUN_DIR" "$RUN_DIR/nodes" || exit 1
    [ "$(stat -f '%Lp' "$RUN_DIR")" = 700 ] || {
      printf 'mad-orchestration-smoke: run directory が 0700 でない\n' >&2
      exit 1
    }

    jq -n \
      --arg run_id "$RUN_ID" \
      --arg backend "$BACKEND" \
      --arg backend_reason "$BACKEND_REASON" \
      --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{
        run_id: $run_id,
        recipe: "research",
        state: "running",
        phase: "research",
        phase_state: "running",
        next_action: "research-1 / research-2 / research-3 を並列に起動する",
        current_round: 0,
        started_at: $started_at,
        backend: $backend,
        backend_reason: $backend_reason,
        parent_decision: "3 観点の調査役を並列に起動する",
        active_nodes: ["research-1", "research-2", "research-3"],
        completed_nodes: [],
        adopted_attempts: {},
        artifact_paths: []
      }' > "$RUN_DIR/state.json"
    chmod 600 "$RUN_DIR/state.json" || exit 1
    [ "$(stat -f '%Lp' "$RUN_DIR/state.json")" = 600 ] || {
      printf 'mad-orchestration-smoke: state.json が 0600 でない\n' >&2
      exit 1
    }

    printf 'run ID:   %s\n' "$RUN_ID" >&2
    printf 'backend:  %s (%s)\n' "$BACKEND" "$BACKEND_REASON" >&2
    printf 'RUN_DIR:  %s\n' "$RUN_DIR" >&2

    say "初期 state を検証する"
    bash "$VALIDATOR" "$RUN_DIR" >&2 || {
      printf 'mad-orchestration-smoke: 初期 state が契約を満たさない\n' >&2
      exit 1
    }

    print_prerequisites
    print_procedure

    say "ここから先は親エージェントが行う"
    note 'child の create、wait、stop は paseo-mcp-adapter 経由で親エージェントが実行する。'
    note 'raw MCP/CLI の create、wait、stop は親から直接呼ばない。終わったら次で結果を確かめる。'
    printf '  bash tests/manual/mad-orchestration-smoke.sh --report %s\n' "$RUN_DIR" >&2
    exit 0
    ;;
esac
