# 同じ作業を項目ごとに並行して行い、1 つに統合する。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

items="$(mad_arg_array items '')" || exit 2
task="$(mad_arg task)"
if [ -z "$items" ] || [ -z "$task" ]; then
  printf 'fanout: items と task が要る\n' >&2
  exit 2
fi
worker_role="$(mad_arg worker_role researcher)"
synthesizer_role="$(mad_arg synthesizer_role synthesizer)"

n="$(printf '%s' "$items" | jq 'length')"
i=0
while [ "$i" -lt "$n" ]; do
  item="$(printf '%s' "$items" | jq -r ".[$i]")"
  i=$((i + 1))
  printf '次の項目について作業する。\n\n項目: %s\n作業: %s\n' "$item" "$task" |
    mad_prompt "fanout-$i"
  mad_start_node "fanout-$i" "$worker_role"
done
mad_join || exit 1

collected="$(mad_collect)" || exit 1
{
  printf '作業「%s」の項目ごとの結果を、重複を除き、食い違いを明示して統合する。\n\n' "$task"
  printf '%s' "$collected" | jq .
} | mad_prompt synthesis
mad_run_node synthesis "$synthesizer_role" || exit 1
cat "$MAD_RUN_DIR/synthesis.json"
