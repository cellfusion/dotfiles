# cwd の草稿を批評して改稿する。worktree に隔離しない。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

mad_declare 'file goal' 'max_rounds writer_role critic_role'

file="$(mad_arg file)"
goal="$(mad_arg goal)"
max_rounds="$(mad_arg max_rounds 2)"
writer_role="$(mad_arg writer_role writer)"
critic_role="$(mad_arg critic_role reviewer)"

if [ ! -f "$file" ]; then
  printf 'refine: %s が無い\n' "$file" >&2
  exit 2
fi
abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
case "$abs" in
  "$PWD"/*) ;;
  *) printf 'refine: %s は cwd の外にある\n' "$file" >&2; exit 2 ;;
esac

revisions=0
while :; do
  round=$((revisions + 1))
  {
    printf '次のファイルを読み、目的に対して直すべき点を挙げる。\n\n'
    printf '対象: %s\n目的: %s\n' "$file" "$goal"
  } | mad_prompt "critique-$round"
  mad_run_node "critique-$round" "$critic_role" || exit 1

  # dry-run では偽の出力しか無いので 1 回で止める。
  [ "${MAD_DRY_RUN:-0}" = "1" ] && exit 0

  status="$(jq -r '.status // "FAIL"' "$MAD_RUN_DIR/critique-$round.json")"
  [ "$status" = "PASS" ] && break
  [ "$revisions" -ge "$max_rounds" ] && break

  revisions=$((revisions + 1))
  cp "$file" "$MAD_RUN_DIR/refine-$revisions.before"
  {
    printf '次のファイルを、指摘に従って書き換える。\n\n'
    printf '対象: %s\n目的: %s\n\n指摘:\n' "$file" "$goal"
    jq '.findings' "$MAD_RUN_DIR/critique-$round.json"
  } | mad_prompt "revise-$revisions"
  mad_run_node "revise-$revisions" "$writer_role" || exit 1
done

jq -n --arg status "$status" --arg file "$file" --argjson revisions "$revisions" \
  --slurpfile critique "$MAD_RUN_DIR/critique-$round.json" \
  '{status: $status, file: $file, revisions: $revisions,
    findings: ($critique[0].findings // [])}'
