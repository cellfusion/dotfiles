# 不具合の原因を観点ごとに並行で調べ、最も確からしい 1 つを裁定する。
set -u
. "$MAD_SCRIPTS/mad-lib.sh"

mad_declare 'symptom' 'angles researcher_role judge_role'

symptom="$(mad_arg symptom)"
angles="$(mad_arg_array angles \
  '["再現条件と入力","直近の変更履歴","エラーが出る位置と呼び出し経路","同種の既知の不具合"]')" || exit 2
researcher_role="$(mad_arg researcher_role researcher)"
judge_role="$(mad_arg judge_role judge)"

n="$(printf '%s' "$angles" | jq 'length')"
i=0
while [ "$i" -lt "$n" ]; do
  a="$(printf '%s' "$angles" | jq -r ".[$i]")"
  i=$((i + 1))
  printf '症状「%s」の原因を、次の観点から調べる。根拠はコード上の位置で示す。\n\n観点: %s\n' \
    "$symptom" "$a" | mad_prompt "angle-$i"
  mad_start_node "angle-$i" "$researcher_role"
done
mad_join || exit 1

collected="$(mad_collect)" || exit 1
{
  printf '症状「%s」について観点ごとに集めた根拠を突き合わせる。\n' "$symptom"
  printf '最も確からしい原因を 1 つ選び、次に確かめる手順を reason に書く。\n\n'
  printf '%s' "$collected" | jq .
} | mad_prompt verdict
mad_run_node verdict "$judge_role" || exit 1
cat "$MAD_RUN_DIR/verdict.json"
