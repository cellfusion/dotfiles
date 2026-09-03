# 候補案を並行で作り、観点ごとに採点して 1 つ選ぶ。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

problem="$(mad_arg problem)"
if [ -z "$problem" ]; then
  printf 'decide: problem が要る\n' >&2
  exit 2
fi
approaches="$(mad_arg_array approaches '["最小で単純な","堅牢でリスクを抑えた","異なる発想の"]')" || exit 2
criteria="$(mad_arg_array criteria '["適合性","実現性","単純さ","リスク"]')" || exit 2
candidate_role="$(mad_arg candidate_role researcher)"
judge_role="$(mad_arg judge_role judge)"

n="$(printf '%s' "$approaches" | jq 'length')"
i=0
while [ "$i" -lt "$n" ]; do
  a="$(printf '%s' "$approaches" | jq -r ".[$i]")"
  i=$((i + 1))
  printf '課題「%s」への案を 1 つ作る。\n\n方向: %s案\n' "$problem" "$a" |
    mad_prompt "candidate-$i"
  mad_start_node "candidate-$i" "$candidate_role"
done
mad_join || exit 1

collected="$(mad_collect)" || exit 1
{
  printf '課題「%s」への次の候補を、%s の観点で採点し、1 案を選ぶ。\n\n' \
    "$problem" "$(printf '%s' "$criteria" | jq -r 'join("、")')"
  printf '%s' "$collected" | jq .
} | mad_prompt verdict
mad_run_node verdict "$judge_role" || exit 1
cat "$MAD_RUN_DIR/verdict.json"
