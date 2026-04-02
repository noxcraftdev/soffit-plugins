#!/bin/bash
# System stats: CPU 1-minute load average, memory usage, and uptime
#
# Uses theme colors from config.theme for customizable appearance.
# Memory color adapts to usage: green < 50%, orange 50-80%, red >= 80%.

INPUT=$(cat)

read -r COMPACT COMPONENTS DIM LGRAY GREEN ORANGE RED RESET < <(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
theme = cfg.get('theme', {})
print(
    cfg.get('compact', False),
    ','.join(cfg.get('components', [])),
    theme.get('dim', ''),
    theme.get('lgray', ''),
    theme.get('green', ''),
    theme.get('orange', ''),
    theme.get('red', ''),
    theme.get('reset', ''),
)
" 2>/dev/null)

LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "?")
MEM_PCT=$(free 2>/dev/null | awk '/Mem:/{printf "%.0f", $3/$2*100}')
MEM="${MEM_PCT:-?}%"
UP=$(uptime -p 2>/dev/null | sed 's/up //' | sed 's/ hours\?/h/' | sed 's/ minutes\?/m/' | sed 's/, //' || echo "?")

# Pick memory color based on usage
if [ "${MEM_PCT:-0}" -ge 80 ] 2>/dev/null; then
  MEM_COL="$RED"
elif [ "${MEM_PCT:-0}" -ge 50 ] 2>/dev/null; then
  MEM_COL="$ORANGE"
else
  MEM_COL="$GREEN"
fi

parts=""
show_all=true
[ -n "$COMPONENTS" ] && show_all=false

# CPU load component
if $show_all || echo "$COMPONENTS" | grep -q "cpu"; then
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${LGRAY}${LOAD}${RESET}"
  else
    parts="${parts}${DIM}\u26a1${RESET}${LGRAY}${LOAD}${RESET}"
  fi
fi

# Memory component
if $show_all || echo "$COMPONENTS" | grep -q "mem"; then
  [ -n "$parts" ] && { [ "$COMPACT" = "True" ] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${MEM_COL}${MEM}${RESET}"
  else
    parts="${parts}${DIM}\U0001f9e0${RESET}${MEM_COL}${MEM}${RESET}"
  fi
fi

# Uptime component
if $show_all || echo "$COMPONENTS" | grep -q "uptime"; then
  [ -n "$parts" ] && { [ "$COMPACT" = "True" ] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${DIM}${UP}${RESET}"
  else
    parts="${parts}${DIM}\u231b${UP}${RESET}"
  fi
fi

echo -e "{\"output\": \"$parts\", \"components\": [\"cpu\", \"mem\", \"uptime\"]}"
