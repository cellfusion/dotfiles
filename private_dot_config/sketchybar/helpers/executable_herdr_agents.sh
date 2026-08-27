#!/bin/sh
# herdr の全 running セッションを走査し、確認待ち(done)/入力待ち(blocked) の
# エージェント数をセッション別に集計して sketchybar 用に出力する。
# 出力: "<severity>\t<label>"   severity ∈ none | done | blocked
#   - blocked が1つでもあれば severity=blocked（赤）
#   - blocked なしで done があれば severity=done（黄）
#   - どちらも無ければ none（アイコンのみ grey、ラベル非表示）
#
# 状態マーカー。SF Symbols のモノクロ字形(checkmark.circle.fill 等)はテキスト非
# エンコードで sketchybar ラベルに入れられないため、確実にモノクロ描画される
# Unicode 等価字を使う。⚠ は U+FE0E(VS15) を付けて emoji 化を抑止している。
MARK_DONE="✓"        # finished（確認待ち）
MARK_BLOCKED="⚠︎"    # blocked（入力待ち, U+26A0 + U+FE0E）

# sketchybar は GUI セッション起動で PATH が細いので明示的に足す。
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

command -v herdr >/dev/null 2>&1 || { printf 'none\t'; exit 0; }
command -v jq   >/dev/null 2>&1 || { printf 'none\t'; exit 0; }

sessions=$(herdr session list --json 2>/dev/null | jq -r '.sessions[] | select(.running == true) | .name')
[ -n "$sessions" ] || { printf 'none\t'; exit 0; }

label=""
severity="none"
for s in $sessions; do
  counts=$(herdr --session "$s" agent list 2>/dev/null | jq -r '
    [.result.agents[]?.agent_status]
    | { d: (map(select(. == "done"))    | length),
        b: (map(select(. == "blocked")) | length) }
    | "\(.d) \(.b)"')
  [ -n "$counts" ] || counts="0 0"
  d=${counts%% *}
  b=${counts##* }
  [ "$d" = 0 ] && [ "$b" = 0 ] && continue

  short=$(printf '%s' "$s" | cut -c1-3)
  tok="$short"
  [ "$d" != 0 ] && tok="$tok $d$MARK_DONE"
  [ "$b" != 0 ] && tok="$tok $b$MARK_BLOCKED"

  if [ -n "$label" ]; then label="$label  $tok"; else label="$tok"; fi
  if [ "$b" != 0 ]; then
    severity="blocked"
  elif [ "$severity" != "blocked" ]; then
    severity="done"
  fi
done

printf '%s\t%s' "$severity" "$label"
