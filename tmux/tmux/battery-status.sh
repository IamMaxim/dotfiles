#!/bin/sh

if command -v pmset >/dev/null 2>&1; then
  pmset -g batt | grep -o "[0-9]\{1,3\}%" | head -n 1
  exit 0
fi

if command -v upower >/dev/null 2>&1; then
  battery=$(upower -e 2>/dev/null | grep '/battery_' | head -n 1 || true)
  if [ -n "$battery" ]; then
    upower -i "$battery" 2>/dev/null | awk -F': *' '/percentage/ { print $2; exit }'
    exit 0
  fi
fi

for battery in /sys/class/power_supply/BAT*; do
  if [ -r "$battery/capacity" ]; then
    cat "$battery/capacity"
    printf '%%\n'
    exit 0
  fi
done

exit 0
