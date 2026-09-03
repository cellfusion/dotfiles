#!/bin/zsh

input=$(cat)

# Colors
GREEN='[32m'
YELLOW='[33m'
RED='[31m'
RESET='[0m'

color_for_pct() {
  local pct=$1
  if [ "$pct" -le 60 ]; then
    echo -e "$GREEN"
  elif [ "$pct" -le 80 ]; then
    echo -e "$YELLOW"
  else
    echo -e "$RED"
  fi
}

format_remaining() {
  local resets_at=$1
  if [ -z "$resets_at" ] || [ "$resets_at" = "null" ]; then
    return
  fi
  local now
  now=$(date +%s)
  local diff=$((resets_at - now))
  if [ "$diff" -le 0 ]; then
    echo "now"
    return
  fi
  local days=$((diff / 86400))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d${hours}h"
  else
    echo "${hours}h${mins}m"
  fi
}

build_meter() {
  local pct=$1
  local color
  color=$(color_for_pct "$pct")
  echo -e "${color}${pct}%${RESET}"
}

# Model
MODEL=$(echo "$input" | jq -r '.model.display_name // empty' | sed 's/ context//')

# Rate limits
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
FIVE_H_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
WEEK=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
WEEK_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Context window
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Build output
parts=()

# Nerd Font icons (UTF-8 encoded directly)
ICON_MODEL=""
ICON_5H=""
ICON_WEEK=""
ICON_CTX=""

# Model
if [ -n "$MODEL" ]; then
  parts+=("${ICON_MODEL} ${MODEL}")
fi

# 5h limit
if [ -n "$FIVE_H" ]; then
  FIVE_H_INT=$(printf '%.0f' "$FIVE_H")
  FIVE_H_REMAINING=$(format_remaining "$FIVE_H_RESET")
  if [ -n "$FIVE_H_REMAINING" ]; then
    parts+=("${ICON_5H} $(build_meter "$FIVE_H_INT") ${FIVE_H_REMAINING}")
  else
    parts+=("${ICON_5H} $(build_meter "$FIVE_H_INT")")
  fi
fi

# Weekly limit
if [ -n "$WEEK" ]; then
  WEEK_INT=$(printf '%.0f' "$WEEK")
  WEEK_REMAINING=$(format_remaining "$WEEK_RESET")
  if [ -n "$WEEK_REMAINING" ]; then
    parts+=("${ICON_WEEK} $(build_meter "$WEEK_INT") ${WEEK_REMAINING}")
  else
    parts+=("${ICON_WEEK} $(build_meter "$WEEK_INT")")
  fi
fi

# Context window
parts+=("${ICON_CTX} $(build_meter "$CTX")")

# Join with separator
result="${(j: │ :)parts}"
echo -e "$result"
