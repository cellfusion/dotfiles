# 観点を分けて調べ、1 つに統合する。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

topic="$(mad_arg topic)"
if [ -z "$topic" ]; then
  printf 'research: topic が要る\n' >&2
  exit 2
fi
perspectives="$(mad_arg_array perspectives '["現状と確認済みの事実","制約とリスク","代替案"]')" || exit 2
researcher_role="$(mad_arg researcher_role researcher)"
synthesizer_role="$(mad_arg synthesizer_role synthesizer)"

n="$(printf '%s' "$perspectives" | jq 'length')"
i=0
while [ "$i" -lt "$n" ]; do
  p="$(printf '%s' "$perspectives" | jq -r ".[$i]")"
  i=$((i + 1))
  printf '対象「%s」を、次の観点から調べる。\n\n観点: %s\n' "$topic" "$p" |
    mad_prompt "research-$i"
  mad_start_node "research-$i" "$researcher_role"
done
mad_join || exit 1

{
  printf '対象「%s」についての次の調査結果を、重複を除き、食い違いを明示して統合する。\n\n' "$topic"
  mad_collect | jq .
} | mad_prompt synthesis
mad_run_node synthesis "$synthesizer_role" || exit 1
cat "$MAD_RUN_DIR/synthesis.json"
