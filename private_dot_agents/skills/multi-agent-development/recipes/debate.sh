# 立場を分けて主張させ、裁定する。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

proposal="$(mad_arg proposal)"
if [ -z "$proposal" ]; then
  printf 'debate: proposal が要る\n' >&2
  exit 2
fi
positions="$(mad_arg_array positions '["賛成","反対"]')" || exit 2
advocate_role="$(mad_arg advocate_role researcher)"
judge_role="$(mad_arg judge_role judge)"

n="$(printf '%s' "$positions" | jq 'length')"
i=0
while [ "$i" -lt "$n" ]; do
  pos="$(printf '%s' "$positions" | jq -r ".[$i]")"
  i=$((i + 1))
  printf '提案「%s」に対して、%s の立場から主張と根拠を述べる。\n' "$proposal" "$pos" |
    mad_prompt "position-$i"
  mad_start_node "position-$i" "$advocate_role"
done
mad_join || exit 1

{
  printf '提案「%s」への次の主張を突き合わせ、どちらが妥当かを裁定する。\n\n' "$proposal"
  mad_collect | jq .
} | mad_prompt verdict
mad_run_node verdict "$judge_role" || exit 1
cat "$MAD_RUN_DIR/verdict.json"
