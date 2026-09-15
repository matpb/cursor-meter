#!/usr/bin/env bash
# Render compact panel screenshot from live meter JSON (for README assets).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/plasmoid/org.mat.cursormeter/contents/scripts/cursor-meter.sh"
BARS="${BARS:-2}"
OUT="${OUT:-$HERE/panel.png}"
data=$(bash "$SCRIPT")
auto=$(printf '%s' "$data" | jq -r '.five.pct // 0')
api=$(printf '%s' "$data" | jq -r '.seven.pct // 0')
grok=$(printf '%s' "$data" | jq -r '.grok.pct // empty')
auto_reset=$(printf '%s' "$data" | jq -r '.five.reset_in // 0')
api_reset=$(printf '%s' "$data" | jq -r '.seven.reset_in // 0')
grok_reset=$(printf '%s' "$data" | jq -r '.grok.reset_in // 0')
cycle=$(printf '%s' "$data" | jq -r '.cycle_sec // 2592000')
grok_cycle=$(printf '%s' "$data" | jq -r '.grok.week_sec // 604800')
auto_tp=$(( (cycle - auto_reset) * 100 / cycle ))
api_tp=$(( (cycle - api_reset) * 100 / cycle ))
grok_tp=0
[ -n "$grok" ] && grok_tp=$(( (grok_cycle - grok_reset) * 100 / grok_cycle ))

pace_color() {
  local p=$1 t=$2 m hue
  m=$((p - t))
  if [ "$m" -le -8 ]; then hue="#5fbf4f"
  elif [ "$m" -lt 0 ]; then hue="#c9c24a"
  elif [ "$m" -lt 8 ]; then hue="#d4a83a"
  else hue="#e85d5d"; fi
  printf '%s' "$hue"
}
ac=$(pace_color "$auto" "$auto_tp")
pc=$(pace_color "$api" "$api_tp")
gc=""
grok_row=""
show_grok=false
if [ "$BARS" = "3" ] && [ -n "$grok" ]; then
  show_grok=true
  gc=$(pace_color "$grok" "$grok_tp")
  grok_row="<div class=\"row\"><div class=\"lbl\">Grok</div><div class=\"track\"><div class=\"fill\" style=\"width:${grok}%;background:${gc}\"></div><div class=\"tick\" style=\"left:${grok_tp}%\"></div></div><div class=\"pct\" style=\"color:${gc}\">${grok}%</div></div>"
fi
bar_gap=5
[ "$show_grok" = true ] && bar_gap=2

html=$(mktemp --suffix=.html)
cat > "$html" <<EOF
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
body{margin:0;background:#1b1c1f;font:12px system-ui,sans-serif;color:#cfd3dc}
.wrap{display:inline-flex;align-items:center;gap:8px;padding:10px 12px;border-radius:8px;background:#232428;border:1px solid #333}
.icon{width:18px;height:18px;background:linear-gradient(135deg,#edecec 60%,#888);clip-path:polygon(15% 10%,45% 10%,45% 45%,85% 45%,85% 85%,45% 85%,45% 55%,15% 55%)}
.bars{display:flex;flex-direction:column;gap:${bar_gap}px;width:170px}
.row{display:flex;align-items:center;gap:6px}
.lbl{width:28px;opacity:.6;font-weight:700;font-size:10px}
.track{flex:1;height:12px;background:rgba(255,255,255,.14);border-radius:6px;position:relative}
.fill{height:100%;border-radius:6px}
.tick{position:absolute;top:-2px;width:2px;height:16px;background:#fff;border-radius:1px}
.pct{width:30px;text-align:right;font-weight:700;font-size:11px}
</style></head><body><div class="wrap">
<div class="icon"></div><div class="bars">
<div class="row"><div class="lbl">Models</div><div class="track"><div class="fill" style="width:${auto}%;background:${ac}"></div><div class="tick" style="left:${auto_tp}%"></div></div><div class="pct" style="color:${ac}">${auto}%</div></div>
<div class="row"><div class="lbl">Other</div><div class="track"><div class="fill" style="width:${api}%;background:${pc}"></div><div class="tick" style="left:${api_tp}%"></div></div><div class="pct" style="color:${pc}">${api}%</div></div>
${grok_row}
</div></div></body></html>
EOF
h=90
[ "$show_grok" = true ] && h=118
google-chrome-stable --headless --disable-gpu --window-size=320,$h --screenshot="$OUT" "file://$html" 2>/dev/null
rm -f "$html"
[ -s "$OUT" ] && echo "wrote $OUT" || exit 1
