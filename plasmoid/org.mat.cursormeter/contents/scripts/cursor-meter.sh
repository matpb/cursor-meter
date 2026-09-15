#!/usr/bin/env bash
# cursor-meter — emit current Cursor plan usage as one JSON line for the Cursor Meter plasmoid.
#
# PRIMARY source: Cursor's dashboard Connect-RPC on api2.cursor.sh. Always fresh, account-wide
#   (counts the IDE, the CLI and Cloud Agents alike) and costs ZERO quota (read-only status).
#   Auth is the access token Cursor already stores after you sign in — ~/.config/cursor/auth.json
#   from the CLI, or cursorAuth/accessToken in the IDE state DB. The token is used in memory only.
# FALLBACK: the last successful live read cached at ~/.config/cursor-meter/last.json.
#
# Output: {"ok":true,"source":"live"|"cache","age":N,"plan":"Pro","cycle_sec":S,"total_pct":P,
#          "five":{"pct":P,"reset_in":S,"fresh":B},"seven":{...}}
#   `five` = Auto + Composer bucket, `seven` = named-model API bucket (same billing cycle).
#
# Optional environment overrides (none are required):
#   CURSOR_CONFIG_HOME     CLI auth dir (default ~/.config/cursor)
#   CURSOR_STATE_DB        IDE state DB (default ~/.config/Cursor/User/globalStorage/state.vscdb)
#   CURSOR_METER_CACHE     Snapshot path (default ~/.config/cursor-meter/last.json)
#   CURSOR_METER_USAGE_JSON / CURSOR_METER_PLAN_JSON   Test fixtures
#   CURSOR_METER_DEBUG=1   Print diagnostics to stderr

set -f
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH:/home/linuxbrew/.linuxbrew/bin"

cursor_cfg="${CURSOR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/cursor}"
auth="$cursor_cfg/auth.json"
state_db="${CURSOR_STATE_DB:-${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/globalStorage/state.vscdb}"
cache="${CURSOR_METER_CACHE:-${XDG_CONFIG_HOME:-$HOME/.config}/cursor-meter/last.json}"
api_base="${CURSOR_API_BASE:-https://api2.cursor.sh}"
usage_url="$api_base/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
plan_url="$api_base/aiserver.v1.DashboardService/GetPlanInfo"
legacy_url="$api_base/auth/usage"
now=$(date +%s)
UA="cursor-meter/1.0"

log() { [ -n "${CURSOR_METER_DEBUG:-}" ] && printf 'cursor-meter: %s\n' "$*" >&2; }

token_alive() {
    local payload pad exp
    payload=$(printf '%s' "$1" | cut -d. -f2)
    pad=$(( (4 - ${#payload} % 4) % 4 ))
    [ "$pad" -gt 0 ] && payload="$payload$(printf '=%.0s' $(seq 1 $pad))"
    exp=$(printf '%s' "$payload" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null)
    [ -n "$exp" ] || return 0
    [ "$exp" -gt "$now" ]
}

read_token() {
    local tok=""
    if [ -s "$auth" ]; then
        tok=$(jq -r '.accessToken // empty' "$auth" 2>/dev/null)
    fi
    if [ -z "$tok" ] && [ -s "$state_db" ] && command -v sqlite3 >/dev/null 2>&1; then
        tok=$(sqlite3 -readonly "$state_db" "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken';" 2>/dev/null)
    fi
    [ -n "$tok" ] && printf '%s' "$tok"
}

normalize_dashboard() {
    local plan="$1"
    jq -e -c --argjson now "$now" --arg plan "$plan" '
      def pct(v): if v == null then 0 else ((v * 100 + 0.5) | floor) end;
      def fresh(p; ri; cycle): (p == 0) and (ri >= (cycle - 120));
      (.billingCycleStart // 0) as $bs | (.billingCycleEnd // 0) as $be
      | if (($be | tonumber) <= 0) then error("no billing cycle") else . end
      | (($be | tonumber) / 1000 | floor) as $end
      | (($bs | tonumber) / 1000 | floor) as $start
      | ($end - $now) as $ri0
      | (if $ri0 < 0 then 0 else $ri0 end) as $ri
      | ($end - $start) as $cycle
      | (.planUsage // {}) as $pu
      | pct($pu.autoPercentUsed) as $auto
      | pct($pu.apiPercentUsed) as $api
      | pct($pu.totalPercentUsed) as $total
      | { ok: true, source: "live", age: 0,
          plan: (if $plan == "" then "Cursor" else $plan end),
          cycle_sec: $cycle, total_pct: $total,
          five:  { pct: $auto, reset_in: $ri, fresh: fresh($auto; $ri; $cycle) },
          seven: { pct: $api,  reset_in: $ri, fresh: fresh($api; $ri; $cycle) } }
    '
}

normalize_legacy() {
    local plan="$1"
    jq -e -c --argjson now "$now" --arg plan "$plan" '
      def bucket:
        . as $b
        | ($b.maxRequestUsage // 0) as $max
        | if $max <= 0 then null
          else { pct: (($b.numRequests // 0) * 100 / $max | floor),
                 reset_in: null, fresh: (($b.numRequests // 0) == 0) } end;
      (.["gpt-4"] // .["gpt-4-32k"] // .["default"] // empty) as $primary
      | if $primary == null or ($primary.maxRequestUsage // 0) <= 0 then error("no legacy buckets") else . end
      | ($primary | bucket) as $b
      | { ok: true, source: "live", age: 0,
          plan: (if $plan == "" then "Enterprise" else $plan end),
          cycle_sec: 2592000, total_pct: $b.pct,
          five:  $b,
          seven: ($b + { fresh: false }) }
    '
}

emit_cache() {
    [ -s "$cache" ] || { printf '{"ok":false,"reason":"no-data"}\n'; return; }
    jq -e -c --argjson now "$now" '
      ($now - (.ts // $now)) as $age
      | if (.ok != true) then error("bad cache") else . end
      | .five.reset_in  as $f | .seven.reset_in as $s
      | { ok: true, source: "cache", age: $age,
          plan: (.plan // "Cursor"), cycle_sec: (.cycle_sec // 2592000),
          total_pct: (.total_pct // .five.pct // 0),
          five:  (.five  + { reset_in: (if $f == null then null elif ($f - $age) < 0 then 0 else ($f - $age) end) }),
          seven: (.seven + { reset_in: (if $s == null then null elif ($s - $age) < 0 then 0 else ($s - $age) end) }) }
    ' "$cache" 2>/dev/null || printf '{"ok":false,"reason":"parse-error"}\n'
}

write_cache() {
    local dir tmp
    dir=$(dirname "$cache")
    mkdir -p "$dir" 2>/dev/null || return 0
    tmp="$cache.tmp.$$"
    printf '%s' "$1" | jq -c --argjson now "$now" '. + {ts: $now}' > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$cache" 2>/dev/null || rm -f "$tmp"
}

plan_from_file() {
    jq -r '.planInfo.planName // empty' "$1" 2>/dev/null
}

plan_from_live() {
    local tok="$1" resp p
    [ -n "$tok" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0
    set +x
    resp=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | timeout 10 curl -sS --fail --max-time 10 \
        -K - \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Connect-Protocol-Version: 1" \
        -H "User-Agent: $UA" \
        -d '{}' \
        "$plan_url" 2>/dev/null) || return 0
    p=$(printf '%s' "$resp" | jq -r '.planInfo.planName // empty' 2>/dev/null)
    [ -n "$p" ] && printf '%s' "$p"
}

try_live() {
    command -v jq >/dev/null 2>&1 || { log "missing jq"; return 1; }

    local tok="" usage="" plan="" resp

    if [ -n "${CURSOR_METER_USAGE_JSON:-}" ]; then
        [ -s "$CURSOR_METER_USAGE_JSON" ] || { log "usage fixture missing"; return 1; }
        usage=$(cat "$CURSOR_METER_USAGE_JSON")
        [ -n "$usage" ] || { log "usage fixture empty"; return 1; }
    else
        command -v curl >/dev/null 2>&1 || { log "missing curl"; return 1; }
        tok=$(read_token)
        [ -n "$tok" ] || { log "no token — sign in to Cursor or run: cursor-agent login"; return 1; }
        token_alive "$tok" || { log "access token expired — open Cursor or run cursor-agent once"; return 1; }
        set +x
        resp=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | timeout 10 curl -sS --fail --max-time 10 \
            -K - \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Connect-Protocol-Version: 1" \
            -H "User-Agent: $UA" \
            -d '{}' \
            "$usage_url" 2>/dev/null) || { log "dashboard usage endpoint failed"; return 1; }
        usage=$resp
        [ -n "$usage" ] || { log "usage endpoint returned nothing"; return 1; }
    fi

    if [ -n "${CURSOR_METER_PLAN_JSON:-}" ] && [ -s "$CURSOR_METER_PLAN_JSON" ]; then
        plan=$(plan_from_file "$CURSOR_METER_PLAN_JSON")
    elif [ -z "${CURSOR_METER_USAGE_JSON:-}" ]; then
        plan=$(plan_from_live "$tok")
    fi
    plan="${plan:-Cursor}"

    if printf '%s' "$usage" | jq -e '.planUsage != null' >/dev/null 2>&1; then
        printf '%s' "$usage" | normalize_dashboard "$plan" 2>/dev/null \
            || { log "could not parse dashboard response"; return 1; }
        return 0
    fi

    # Enterprise-style request buckets when planUsage is absent.
    if [ -n "${CURSOR_METER_USAGE_JSON:-}" ]; then
        log "fixture lacks planUsage and legacy shape"
        return 1
    fi
    resp=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | timeout 10 curl -sS --fail --max-time 10 \
        -K - \
        -H "Accept: application/json" \
        -H "User-Agent: $UA" \
        "$legacy_url" 2>/dev/null) || { log "legacy usage endpoint failed"; return 1; }
    printf '%s' "$resp" | normalize_legacy "$plan" 2>/dev/null \
        || { log "could not parse legacy usage response"; return 1; }
}

if out=$(try_live) && [ -n "$out" ]; then
    write_cache "$out"
    printf '%s\n' "$out"
else
    emit_cache
fi
