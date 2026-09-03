# 要件を worktree で実装し、レビューして直すループを回す。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

mad_declare 'requirements' 'implementer_role reviewer_role max_rounds branch base'
mad_default_timeout 3600

requirements="$(mad_text requirements)" || exit 1
implementer_role="$(mad_arg implementer_role implementer)"
reviewer_role="$(mad_arg reviewer_role reviewer)"
max_rounds="$(mad_arg max_rounds 3)"
branch="$(mad_arg branch "mad/$MAD_RUN_ID")"

base="$(mad_base)" || exit 2
mad_record_base "$base"

ws_line="$(mad_worktree "$branch" "$base")" || exit 1
ws_id="$(mad_ws_field "$ws_line" id)"
ws_cwd="$(mad_ws_field "$ws_line" cwd)"

round=1
while :; do
  if [ "$round" = "1" ]; then
    {
      printf '次の要件を実装する。\n\n'
      printf '作業ディレクトリ: %s\nbase ブランチ: %s\n\n要件:\n%s\n' \
        "$ws_cwd" "$base" "$requirements"
    } | mad_prompt "implement-$round"
  else
    {
      printf '前のラウンドの実装がレビューで指摘された。指摘を直してコミットする。\n\n'
      printf '作業ディレクトリ: %s\nbase ブランチ: %s\n\n要件:\n%s\n\n指摘:\n' \
        "$ws_cwd" "$base" "$requirements"
      jq '.findings' "$MAD_RUN_DIR/review-$((round - 1)).json"
    } | mad_prompt "implement-$round"
  fi
  mad_run_node "implement-$round" "$implementer_role" "$ws_id" || exit 1

  {
    printf '次の要件に対する差分をレビューする。\n\n要件:\n%s\n\n差分:\n' "$requirements"
    printf '```diff\n'
    mad_diff "$ws_cwd" "$base" 2000
    printf '```\n'
  } | mad_prompt "review-$round"
  mad_run_node "review-$round" "$reviewer_role" "$ws_id" || exit 1

  # dry-run では偽の出力しか無いので 1 ラウンドで止める。
  [ "${MAD_DRY_RUN:-0}" = "1" ] && exit 0

  status="$(jq -r '.status // "FAIL"' "$MAD_RUN_DIR/review-$round.json")"
  [ "$status" = "PASS" ] && break
  [ "$round" -ge "$max_rounds" ] && break
  round=$((round + 1))
done

jq -n --arg status "$status" --arg branch "$branch" --arg ws "$ws_id" \
  --arg worktree "$ws_cwd" --argjson rounds "$round" \
  --slurpfile review "$MAD_RUN_DIR/review-$round.json" \
  --slurpfile impl "$MAD_RUN_DIR/implement-$round.json" \
  '{status: $status, branch: $branch, workspaceId: $ws, worktree: $worktree,
    rounds: $rounds, review: $review[0],
    changedFiles: ($impl[0].changedFiles // [])}'
