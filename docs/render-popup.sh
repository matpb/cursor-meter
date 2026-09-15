#!/usr/bin/env bash
# Render popup screenshot from live meter JSON (for README assets).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/plasmoid/org.mat.cursormeter/contents/scripts/cursor-meter.sh"
OUT="$HERE/popup.png"
data=$(bash "$SCRIPT")
plan=$(printf '%s' "$data" | jq -r '.plan // "Cursor"')
total=$(printf '%s' "$data" | jq -r '.total_pct // 0')
auto=$(printf '%s' "$data" | jq -r '.five.pct // 0')
api=$(printf '%s' "$data" | jq -r '.seven.pct // 0')
auto_reset=$(printf '%s' "$data" | jq -r '.five.reset_in // 0')
api_reset=$(printf '%s' "$data" | jq -r '.seven.reset_in // 0')
grok=$(printf '%s' "$data" | jq -r '.grok.pct // empty')
grok_reset=$(printf '%s' "$data" | jq -r '.grok.reset_in // 0')
grok_cycle=$(printf '%s' "$data" | jq -r '.grok.week_sec // 604800')
cycle=$(printf '%s' "$data" | jq -r '.cycle_sec // 2592000')

fmt() {
  local s=$1 d h m
  if [ "$s" -le 0 ]; then echo "now"; return; fi
  d=$((s/86400)); s=$((s%86400)); h=$((s/3600)); s=$((s%3600)); m=$((s/60))
  if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

auto_elapsed=$(( cycle - auto_reset ))
api_elapsed=$(( cycle - api_reset ))
auto_tp=$(( auto_elapsed * 100 / cycle ))
api_tp=$(( api_elapsed * 100 / cycle ))
grok_tp=0
grok_block=""
if [ -n "$grok" ]; then
  grok_elapsed=$(( grok_cycle - grok_reset ))
  grok_tp=$(( grok_elapsed * 100 / grok_cycle ))
  grok_block="<div class=\"block grok\"><div class=\"row\"><span class=\"name\">Grok Bot (weekly)</span><span class=\"pct\">${grok}%</span></div><div class=\"track\"><div class=\"fill\"></div><div class=\"tick\"></div></div><div class=\"detail\">resets in $(fmt "$grok_reset") · ${grok_tp}% through week · on pace</div></div>"
fi

html=$(mktemp --suffix=.html)
cat > "$html" <<EOF
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
body{margin:0;background:#1a1b1e;font:14px system-ui,sans-serif;color:#e8e8ea}
.card{width:320px;margin:24px;padding:20px;border-radius:12px;background:#232428;border:1px solid #333}
.hdr{display:flex;gap:10px;align-items:center;margin-bottom:18px}
.title{font-size:18px;font-weight:700;color:#edecec}
.sub{opacity:.6;font-size:12px}
.block{margin-bottom:16px}
.row{display:flex;justify-content:space-between;align-items:center;margin-bottom:6px}
.name{opacity:.8}.pct{font-weight:700;font-size:16px;color:#e85d5d}
.track{height:14px;background:rgba(255,255,255,.12);border-radius:7px;position:relative;overflow:visible}
.fill{height:100%;border-radius:7px;background:linear-gradient(90deg,#ff8a7a,#e85d5d);width:${auto}%}
.tick{position:absolute;top:-2px;width:2px;height:18px;background:#fff;border-radius:1px;left:${auto_tp}%}
.detail{opacity:.55;font-size:11px;margin-top:6px;line-height:1.4}
.api .fill{width:${api}%;background:linear-gradient(90deg,#9bdc8a,#5fbf4f)}
.api .pct{color:#5fbf4f}
.api .tick{left:${api_tp}%}
.grok .fill{width:${grok:-0}%;background:linear-gradient(90deg,#8ab4ff,#5f8fff)}
.grok .pct{color:#5f8fff}
.grok .tick{left:${grok_tp}%}
.foot{opacity:.45;font-size:11px;text-align:right;margin-top:12px}
</style></head><body><div class="card">
<div class="hdr"><div style="width:28px;height:28px;background:#444;border-radius:6px"></div>
<div><div class="title">Cursor</div><div class="sub">included usage · ${plan} · allowance ${total}%</div></div></div>
<div class="block"><div class="row"><span class="name">Cursor, Grok and Composer</span><span class="pct">${auto}%</span></div>
<div class="track"><div class="fill"></div><div class="tick"></div></div>
<div class="detail">resets in $(fmt "$auto_reset") · ${auto_tp}% through cycle · on pace</div></div>
<div class="block api"><div class="row"><span class="name">Other models</span><span class="pct">${api}%</span></div>
<div class="track"><div class="fill"></div><div class="tick"></div></div>
<div class="detail">resets in $(fmt "$api_reset") · ${api_tp}% through cycle · comfortable</div></div>
${grok_block}
<div class="foot">live · account-wide Cursor</div></div></body></html>
EOF
h=420
[ -n "$grok" ] && h=520
google-chrome-stable --headless --disable-gpu --window-size=400,$h --screenshot="$OUT" "file://$html" 2>/dev/null
rm -f "$html"
[ -s "$OUT" ] && echo "wrote $OUT" || exit 1
