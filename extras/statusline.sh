#!/usr/bin/env bash
# One-line Cursor usage for scripts and status hooks.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../plasmoid/org.mat.cursormeter/contents/scripts/cursor-meter.sh"
out=$(bash "$SCRIPT" 2>/dev/null) || exit 0
printf '%s' "$out" | jq -r '
  if .ok != true then empty
  else "Cursor allowance \(.total_pct)% · Models \(.five.pct)% · Other \(.seven.pct)%"
       + (if .grok == null then "" else " · Grok \(.grok.pct)%" end)
  end
'
