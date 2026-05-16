#!/bin/sh

# macOS: fast ioreg query (~15ms)
if command -v ioreg >/dev/null 2>&1; then
  watts=$(ioreg -rn AppleSmartBattery 2>/dev/null \
    | grep '"AdapterDetails"' \
    | grep -o '"Watts"=[0-9]*' \
    | grep -o '[0-9]*$')
  if [ -n "$watts" ]; then
    printf '%sW\n' "$watts"
    exit 0
  fi
fi

# Linux: upower
if command -v upower >/dev/null 2>&1; then
  adapter=$(upower -e 2>/dev/null | grep 'line_power\|ac_adapter' | head -n 1 || true)
  if [ -n "$adapter" ]; then
    upower -i "$adapter" 2>/dev/null | awk -F': *' '/energy-rate/ { printf "%.0fW\n", $2; exit }'
    exit 0
  fi
fi

exit 0
