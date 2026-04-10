#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

INPUT=$(cat)

COMPACT=False COMPONENTS="" PRIMARY="" SUCCESS="" WARNING="" DANGER="" MUTED="" RESET="" SID="" CACHE_ICON="↺"
CACHE_TTL=60 WARN_TOKENS_K=200 DANGER_TOKENS_K=500 GOOD_CACHE_PCT=95 WARN_CACHE_PCT=90

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
palette = cfg.get('palette', {})
settings = cfg.get('settings', {})
data = d.get('data', {})
print(f'COMPACT={cfg.get(\"compact\", False)}')
print('COMPONENTS=\"' + ','.join(cfg.get('components', [])) + '\"')
print(f'PRIMARY=\"{palette.get(\"primary\", \"\")}\"')
print(f'SUCCESS=\"{palette.get(\"success\", \"\")}\"')
print(f'WARNING=\"{palette.get(\"warning\", \"\")}\"')
print(f'DANGER=\"{palette.get(\"danger\", \"\")}\"')
print(f'MUTED=\"{palette.get(\"muted\", \"\")}\"')
print(f'RESET=\"{palette.get(\"reset\", \"\")}\"')
print(f'SID=\"{data.get(\"session_id\", \"\")}\"')
icons = cfg.get('icons', {})
print(f'CACHE_ICON=\"{icons.get(\"cache\", \"↺\")}\"')
print(f'CACHE_TTL={settings.get(\"cache_ttl\", 60)}')
print(f'WARN_TOKENS_K={settings.get(\"warn_tokens_k\", 200)}')
print(f'DANGER_TOKENS_K={settings.get(\"danger_tokens_k\", 500)}')
print(f'GOOD_CACHE_PCT={settings.get(\"good_cache_pct\", 95)}')
print(f'WARN_CACHE_PCT={settings.get(\"warn_cache_pct\", 90)}')
" 2>/dev/null)"

no_output() {
  echo '{"output": "--", "components": ["tokens", "cache"]}'
}

[[ -z "$SID" ]] && { no_output; exit 0; }
command -v claudelytics &>/dev/null || { no_output; exit 0; }

CACHE="/tmp/soffit-usage-$SID"
LOCK="/tmp/soffit-usage-$SID.lock"

has_component() {
  local name="$1"
  [[ -z "$COMPONENTS" ]] && return 0
  local IFS=','
  for c in $COMPONENTS; do
    [[ "$c" == "$name" ]] && return 0
  done
  return 1
}

render() {
  local raw
  raw=$(cat "$CACHE" 2>/dev/null) || return 1
  local tokens_raw hit_pct_raw
  tokens_raw=$(echo "$raw" | cut -f1)
  hit_pct_raw=$(echo "$raw" | cut -f2)

  local SEP=" "
  [[ "$COMPACT" == "True" ]] && SEP=""

  local parts=""

  if has_component "tokens"; then
    local tok_color tok_str
    if [[ "$tokens_raw" == "--" ]]; then
      tok_color="$MUTED"
      tok_str="--"
    else
      tok_str=$(python3 -c "
v = $tokens_raw
if v >= 1_000_000:
    print(f'{v/1_000_000:.1f}M')
elif v >= 1000:
    print(f'{v//1000}k')
else:
    print(str(v))
" 2>/dev/null || echo "--")
      local tok_k=$(( tokens_raw / 1000 ))
      if (( tok_k >= DANGER_TOKENS_K )); then
        tok_color="$DANGER"
      elif (( tok_k >= WARN_TOKENS_K )); then
        tok_color="$WARNING"
      elif (( tok_k >= 50 )); then
        tok_color="$PRIMARY"
      else
        tok_color="$MUTED"
      fi
    fi
    parts="${tok_color}${tok_str}${RESET}"
  fi

  if has_component "cache"; then
    local cache_color cache_str
    if [[ "$hit_pct_raw" == "--" ]]; then
      cache_color="$MUTED"
      cache_str="${CACHE_ICON}--"
    else
      local hit_int
      hit_int=$(python3 -c "print(round($hit_pct_raw * 100))" 2>/dev/null || echo 0)
      cache_str="${CACHE_ICON}${hit_int}%"
      if (( hit_int >= GOOD_CACHE_PCT )); then
        cache_color="$SUCCESS"
      elif (( hit_int >= WARN_CACHE_PCT )); then
        cache_color="$WARNING"
      else
        cache_color="$DANGER"
      fi
    fi
    [[ -n "$parts" ]] && parts="${parts}${SEP}"
    parts="${parts}${cache_color}${cache_str}${RESET}"
  fi

  echo -e "{\"output\": \"$parts\", \"components\": [\"tokens\", \"cache\"]}"
}

if [[ -f "$CACHE" ]]; then
  render
else
  no_output
fi

if [[ -f "$CACHE" ]]; then
  NOW=$(date +%s)
  MTIME=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  AGE=$(( NOW - MTIME ))
  (( AGE < CACHE_TTL )) && exit 0
fi

if [[ -f "$LOCK" ]]; then
  NOW=$(date +%s)
  LMTIME=$(stat -c %Y "$LOCK" 2>/dev/null || echo 0)
  LAGE=$(( NOW - LMTIME ))
  (( LAGE < 30 )) && exit 0
fi

rm -f "$LOCK"
touch "$LOCK"

(
  trap 'rm -f "$LOCK"' EXIT
  DATA=$(claudelytics --json cache-stats --session-id "$SID" 2>/dev/null) || exit 0
  TMPFILE=$(mktemp)
  echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
total = d.get('total_tokens')
tok_out = str(total) if total is not None else '--'
hit = d.get('hit_pct')
hit_out = str(hit) if hit is not None else '--'
sys.stdout.write(tok_out + '\t' + hit_out)
" > "$TMPFILE" && mv "$TMPFILE" "$CACHE" || rm -f "$TMPFILE"
) & disown
