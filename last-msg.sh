#!/bin/bash
# Show the time of the last Claude response in this session
#
# Uses theme colors from config.theme for customizable appearance.

INPUT=$(cat)

read -r COMPACT DIM LGRAY RESET < <(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
theme = cfg.get('theme', {})
print(
    cfg.get('compact', False),
    theme.get('dim', ''),
    theme.get('lgray', ''),
    theme.get('reset', ''),
)
" 2>/dev/null)

TIMESTAMP=$(date +%H:%M:%S)

if [ "$COMPACT" = "True" ]; then
  echo -e "{\"output\": \"${LGRAY}${TIMESTAMP}${RESET}\", \"components\": [\"time\"]}"
else
  echo -e "{\"output\": \"${DIM}Last Msg:${RESET} ${LGRAY}${TIMESTAMP}${RESET}\", \"components\": [\"time\"]}"
fi
