# 観点を分けてレビューし、1 つの PASS / FAIL に統合する。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

requirements="$(mad_arg requirements)"
review_file="$(mad_arg review_file)"
if [ -z "$requirements" ] || [ -z "$review_file" ]; then
  printf 'review: requirements と review_file が要る\n' >&2
  exit 2
fi
perspectives="$(mad_arg_array perspectives '["要件適合","正しさとテスト","保守性と安全性"]')" || exit 2
reviewer_role="$(mad_arg reviewer_role reviewer)"
final_reviewer_role="$(mad_arg final_reviewer_role reviewer)"

n="$(printf '%s' "$perspectives" | jq 'length')"
i=0
while [ "$i" -lt "$n" ]; do
  p="$(printf '%s' "$perspectives" | jq -r ".[$i]")"
  i=$((i + 1))
  printf '要件「%s」に対して、%s を読み、次の観点でレビューする。\n\n観点: %s\n' \
    "$requirements" "$review_file" "$p" | mad_prompt "review-$i"
  mad_start_node "review-$i" "$reviewer_role"
done
mad_join || exit 1

{
  printf '要件「%s」に対する次のレビュー結果を統合し、重複を除いて最終の PASS か FAIL を返す。\n\n' \
    "$requirements"
  mad_collect | jq .
} | mad_prompt final
mad_run_node final "$final_reviewer_role" || exit 1
cat "$MAD_RUN_DIR/final.json"
