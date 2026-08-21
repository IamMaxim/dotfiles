#!/usr/bin/env bash
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name')
effort=$(echo "$input" | jq -r '.effort.level')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd')

used_abs=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_ctx=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/~}"

# Git branch (skip optional locks)
branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" -c gc.auto=0 rev-parse --short HEAD 2>/dev/null)
fi

# Build the status line
printf "\033[33m%s\033[0m" "$short_cwd"

if [ -n "$branch" ]; then
  printf " \033[36m(%s)\033[0m" "$branch"
fi

printf " \033[35m[%s %s]\033[0m" "$model" "$effort"

echo

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  printf "\033[90mctx: %s%%\033[0m (%s/%s)" "$used_int" "$used_abs" "$total_ctx"
fi

# Rate limit usage (only shown when data is available from Claude.ai subscription)
rate_parts=""
if [ -n "$five_hour" ]; then
  five_int=$(printf "%.0f" "$five_hour")
  rate_parts="5h:${five_int}%"
fi
if [ -n "$seven_day" ]; then
  week_int=$(printf "%.0f" "$seven_day")
  if [ -n "$rate_parts" ]; then
    rate_parts="${rate_parts} 7d:${week_int}%"
  else
    rate_parts="7d:${week_int}%"
  fi
fi
if [ -n "$rate_parts" ]; then
  printf " · \033[90m%s\033[0m" "$rate_parts"
fi

printf " · $%.2f" "$cost"

