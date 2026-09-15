#!/usr/bin/env bash
# Fixture-only tests for cursor-meter.sh. Does not hit the network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/plasmoid/org.mat.cursormeter/contents/scripts/cursor-meter.sh"
FIX="$HERE/fixtures"
pass=0
fail=0

die() { printf 'FAIL: %s\n' "$*" >&2; fail=$((fail + 1)); }
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass + 1)); }

make_jwt() {
    local exp="$1" hdr pl
    hdr=$(printf '{"alg":"none","typ":"JWT"}' | openssl base64 -A 2>/dev/null | tr '+/' '-_' | tr -d '=')
    pl=$(printf '{"exp":%s}' "$exp" | openssl base64 -A 2>/dev/null | tr '+/' '-_' | tr -d '=')
    printf '%s.%s.x' "$hdr" "$pl"
}

run_meter() {
    env -u CURSOR_METER_DEBUG "$@" bash "$SCRIPT"
}

assert_jq() {
    local json="$1" expr="$2" label="$3"
    if printf '%s' "$json" | jq -e "$expr" >/dev/null 2>&1; then
        ok "$label"
    else
        die "$label (got: $json)"
    fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

got=$(CURSOR_METER_USAGE_JSON="$FIX/usage-live.json" \
      CURSOR_METER_PLAN_JSON="$FIX/plan.json" \
      CURSOR_METER_CACHE="$TMP/cache-live.json" \
      CURSOR_CONFIG_HOME="$TMP/no-auth" \
      run_meter)
assert_jq "$got" '.ok == true and .source == "live"' "live fixture ok/source"
assert_jq "$got" '.five.pct == 9 and .seven.pct == 1 and .total_pct == 8' "live fixture percents"
assert_jq "$got" '.plan == "Pro" and .cycle_sec == 2592000' "live fixture plan/cycle"

now_ms=$(( $(date +%s) * 1000 ))
start_ms=$(( now_ms - 60000 ))
end_ms=$(( start_ms + 2592000000 ))
jq -n --argjson start "$start_ms" --argjson end "$end_ms" '{
  billingCycleStart: ($start|tostring), billingCycleEnd: ($end|tostring),
  planUsage: { autoPercentUsed: 0, apiPercentUsed: 0, totalPercentUsed: 0 }
}' > "$TMP/usage-fresh-now.json"
got=$(CURSOR_METER_USAGE_JSON="$TMP/usage-fresh-now.json" \
      CURSOR_METER_PLAN_JSON="$FIX/plan.json" \
      CURSOR_METER_CACHE="$TMP/cache-fresh.json" \
      CURSOR_CONFIG_HOME="$TMP/no-auth" \
      run_meter)
assert_jq "$got" '.ok == true and .five.fresh == true and .seven.fresh == true' "fresh cycle"

mkdir -p "$TMP/empty-home"
got=$(CURSOR_CONFIG_HOME="$TMP/empty-home" \
      CURSOR_METER_CACHE="$TMP/missing-cache.json" \
      run_meter)
assert_jq "$got" '.ok == false and .reason == "no-data"' "missing auth → no-data"

mkdir -p "$TMP/expired-home"
exp_jwt=$(make_jwt $(( $(date +%s) - 3600 )))
printf '{"accessToken":"%s"}\n' "$exp_jwt" > "$TMP/expired-home/auth.json"
now=$(date +%s)
jq -n --argjson ts $((now - 120)) '{
  ok: true, source: "live", age: 0, plan: "Pro", cycle_sec: 2592000, total_pct: 8, ts: $ts,
  five:  {pct: 9, reset_in: 100000, fresh: false},
  seven: {pct: 1, reset_in: 100000, fresh: false}
}' > "$TMP/cache-expired.json"
got=$(CURSOR_CONFIG_HOME="$TMP/expired-home" \
      CURSOR_METER_CACHE="$TMP/cache-expired.json" \
      run_meter)
assert_jq "$got" '.ok == true and .source == "cache" and .age > 0' "expired JWT → cache"

printf '{not json\n' > "$TMP/bad.json"
set +e
got=$(CURSOR_METER_USAGE_JSON="$TMP/bad.json" \
      CURSOR_METER_CACHE="$TMP/missing-malformed.json" \
      CURSOR_CONFIG_HOME="$TMP/empty-home" \
      run_meter)
rc=$?
set -e
[ "$rc" -eq 0 ] || die "malformed usage crashed (exit $rc)"
assert_jq "$got" '.ok == false' "malformed usage → ok=false"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
