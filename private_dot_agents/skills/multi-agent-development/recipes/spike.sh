# 同じ要件を別の方針で並行実装し、差分を比べて 1 つ選ぶ。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

mad_declare 'requirements' 'approaches criteria implementer_role judge_role base'
mad_default_timeout 3600

requirements="$(mad_text requirements)" || exit 1
approaches="$(mad_arg_array approaches '["最小で単純な","堅牢でリスクを抑えた","異なる発想の"]')" || exit 2
criteria="$(mad_arg_array criteria '["適合性","実現性","単純さ","リスク"]')" || exit 2
implementer_role="$(mad_arg implementer_role implementer)"
judge_role="$(mad_arg judge_role judge)"

base="$(mad_base)" || exit 2
mad_record_base "$base"

# 方針ごとに worktree を作り、実装を並行で起こす。
# 途中で worktree を作れなくなっても、起動済みのノードを待ってから終わる。
# 待たずに抜けると、失敗した run の worktree に実装役が書き込み続ける。
cands='[]'
n="$(printf '%s' "$approaches" | jq 'length')"
i=0
setup_failed=0
while [ "$i" -lt "$n" ]; do
  a="$(printf '%s' "$approaches" | jq -r ".[$i]")"
  i=$((i + 1))
  ws_line="$(mad_worktree "mad/$MAD_RUN_ID/spike-$i" "$base")" || { setup_failed=1; break; }
  ws_id="$(mad_ws_field "$ws_line" id)"
  ws_cwd="$(mad_ws_field "$ws_line" cwd)"
  cands="$(printf '%s' "$cands" | jq -c \
    --arg name "spike-$i" --arg approach "$a" --arg ws "$ws_id" \
    --arg wt "$ws_cwd" --arg branch "mad/$MAD_RUN_ID/spike-$i" \
    '. + [{name: $name, approach: $approach, workspaceId: $ws,
           worktree: $wt, branch: $branch}]')"
  {
    printf '次の要件を、指定した方向で実装する。\n\n'
    printf '方向: %s案\n作業ディレクトリ: %s\nbase ブランチ: %s\n\n要件:\n%s\n' \
      "$a" "$ws_cwd" "$base" "$requirements"
  } | mad_prompt "spike-$i"
  mad_start_node "spike-$i" "$implementer_role" "$ws_id"
done
mad_join || setup_failed=1
[ "$setup_failed" = "0" ] || exit 1

# 差分を先に取る。取れなければ、中身の無い裁定依頼を出さずに止める。
i=0
while [ "$i" -lt "$n" ]; do
  c="$(printf '%s' "$cands" | jq -c ".[$i]")"
  i=$((i + 1))
  mad_diff "$(printf '%s' "$c" | jq -r '.worktree')" "$base" 800 \
    > "$MAD_RUN_DIR/spike-$i.diff" || exit 1
done

# 案ごとの差分を裁定役に並べて渡す。judge は worktree の中を読めないので埋める。
{
  printf '同じ要件に対する %s 個の実装案を、%s の観点で採点し、1 つ選ぶ。\n' \
    "$n" "$(printf '%s' "$criteria" | jq -r 'join("、")')"
  printf 'winner には案の名前（spike-<番号>）を書く。\n\n要件:\n%s\n' "$requirements"
  i=0
  while [ "$i" -lt "$n" ]; do
    c="$(printf '%s' "$cands" | jq -c ".[$i]")"
    i=$((i + 1))
    printf '\n## %s（%s案）\n\n' \
      "$(printf '%s' "$c" | jq -r '.name')" "$(printf '%s' "$c" | jq -r '.approach')"
    printf '```diff\n'
    cat "$MAD_RUN_DIR/spike-$i.diff"
    printf '```\n'
  done
} | mad_prompt verdict
mad_run_node verdict "$judge_role" || exit 1

[ "${MAD_DRY_RUN:-0}" = "1" ] && exit 0

jq --argjson candidates "$cands" '. + {candidates: $candidates}' \
  "$MAD_RUN_DIR/verdict.json"
