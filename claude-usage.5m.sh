#!/bin/bash
# <bitbar.title>Claude Code Usage</bitbar.title>
# <bitbar.version>5.0</bitbar.version>
# <bitbar.author>naufal</bitbar.author>
# <bitbar.desc>Shows Claude Code rate limits and token usage</bitbar.desc>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/Users/naufal/.nvm/versions/node/v22.14.0/bin:$PATH"

CACHE_FILE="$HOME/.claude/usage-cache.json"
TOKEN_CACHE="/tmp/ccusage-swiftbar"
mkdir -p "$TOKEN_CACHE"

# Refresh OAuth cache in background
refresh_oauth() {
    local credentials token
    credentials=$(security find-generic-password -s "Claude Code-credentials" -a "$USER" -w 2>/dev/null || echo "")
    [ -z "$credentials" ] && return 1
    token=$(echo "$credentials" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null || echo "")
    [ -z "$token" ] && return 1
    curl -s -f \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" \
        -o "$CACHE_FILE.tmp" 2>/dev/null && mv "$CACHE_FILE.tmp" "$CACHE_FILE" 2>/dev/null
}

# Refresh token cache via ccusage in parallel
refresh_tokens() {
    local TODAY=$(date +%Y%m%d)
    local MONTH_START=$(date +%Y%m01)
    ccusage daily --since "$TODAY" --json --offline --no-color > "$TOKEN_CACHE/daily.json" 2>/dev/null &
    ccusage monthly --since "$MONTH_START" --json --offline --no-color > "$TOKEN_CACHE/monthly.json" 2>/dev/null &
    wait
}

# Refresh OAuth if cache > 60s old
if [ -f "$CACHE_FILE" ]; then
    cache_mtime=$(stat -f%m "$CACHE_FILE" 2>/dev/null || echo "0")
    now=$(date +%s)
    [ $((now - cache_mtime)) -gt 60 ] && refresh_oauth &>/dev/null &
else
    refresh_oauth 2>/dev/null
fi

# Refresh token data if cache > 5min old
if [ -f "$TOKEN_CACHE/daily.json" ]; then
    token_mtime=$(stat -f%m "$TOKEN_CACHE/daily.json" 2>/dev/null || echo "0")
    now=$(date +%s)
    [ $((now - token_mtime)) -gt 300 ] && refresh_tokens &
else
    refresh_tokens
fi
wait

python3 << 'PYEOF'
import json, os, sys
from datetime import datetime, timezone

cache = os.path.expanduser("~/.claude/usage-cache.json")
token_cache = "/tmp/ccusage-swiftbar"

five_pct = week_pct = sonnet_pct = 0
five_reset = week_reset = sonnet_reset = ""

def fmt_reset(iso):
    if not iso:
        return "?"
    try:
        dt = datetime.fromisoformat(iso)
        now = datetime.now(timezone.utc)
        diff = (dt - now).total_seconds()
        if diff < 86400:
            return "@" + dt.astimezone().strftime("%-I%p").lower()
        else:
            return "@" + dt.astimezone().strftime("%a").lower()
    except:
        return "?"

if os.path.exists(cache):
    with open(cache) as f:
        d = json.load(f)
    five = d.get("five_hour", {})
    week = d.get("seven_day", {})
    sonnet = d.get("seven_day_sonnet") or {}

    five_pct = five.get("utilization", 0) or 0
    week_pct = week.get("utilization", 0) or 0
    sonnet_pct = sonnet.get("utilization", 0) or 0

    five_reset = fmt_reset(five.get("resets_at"))
    week_reset = fmt_reset(week.get("resets_at"))
    sonnet_reset = fmt_reset(sonnet.get("resets_at"))

def load_tokens(name):
    path = f"{token_cache}/{name}.json"
    try:
        with open(path) as f:
            t = json.load(f)["totals"]
            tokens = t["totalTokens"]
            cost = t["totalCost"]
            fmt = f"{tokens/1e6:.1f}M" if tokens >= 1e6 else f"{tokens/1e3:.1f}K" if tokens >= 1e3 else str(tokens)
            return fmt, f"${cost:.2f}"
    except:
        return "0", "$0.00"

day_tk, day_cost = load_tokens("daily")
month_tk, month_cost = load_tokens("monthly")

def color(pct):
    if pct >= 80: return "#ef4444"
    if pct >= 50: return "#eab308"
    return "#22c55e"

ICON="iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAEKADAAQAAAABAAAAEAAAAAA0VXHyAAACv0lEQVQ4EYVSWUhVURTd+9zBdyvRsiJLHMAxC41AyGgCDRIqUF6aFPinhH2E5gAPuh+JEoqg//0E5fOBQV/1k0FFX34oOPTQJgki7ZlDvunes9tHeZIGteFy7llnr3XW3vsA7IhgW23RZIc3NwETAc7f8VqJ/c5V/AmM2ud1ieDXCEdG7QaPOpttr6tZNzFAtr0tN8HbBl6wXzmI8DolKel4ejRyUSWxYDmR2Ie2LadaqrNmO68PzLR6cxICuvr5aDekOuHIrRi6w1HQfOtxpwYltfDRM0I6qCGMzbRdSdY0c9gytLJVcP2KprgbDsI/VywJdHuXZrw1IX4i6kifx9DOBjuuVSDBHgkwjmgNpHrMsrVIrK8g6eg7RVaBmwvAjM+bY0h9kIFLrpT9BHBVEnzn8xiLrHtMvSocd18WWIWVqpwEb0sgAQQ76hoY7OJ9GhEZvEZ1TVgOUciVcFkT4AqCEhcg2xWxQZxr92Y6qDUB0Qob+gEkFwDFEYFwlxuaJXmOyiiLrSLgF95o/H3lksdIxB6oJi4LoA+87mfVTCZlA5DD9sM68gkLsJiKJUKYYGBCEM66KKaLu5+G/iphurM2Xwe8x7xjnFyAiEkaK8Rd9w0bGQHCc+zkJCChgaJiY4xK/nNH/V4Hyce310sJD9m4xd83Np8BkrI1FBlcTmaeVVQ9sTZnmXr8QN6sM78lEJHufUMXZdyoKiJ5hm8pZXtDErFUNVMinUYkz/vwlF93qbGoN/BJXbz1EoUm7dBisJxApjGpRRjYxDXno4RQPCZ9/CQPkWRHEl/opmhWZBVbAnndgYWUw4VsG22eQmNu19A8v8JTXPdicX8gRIKauR83kpfXH0dcs2+T/oeAAmIQizgk6wt7njyftL2mAEwTINXooLDHHzAQK9OXPNGS3ke/FPbfUBMZb725+1+JvwE25CojpnbmBgAAAABJRU5ErkJggg=="

print(f"{five_pct:.0f}% {five_reset} | image={ICON}")

print("---")
print(f"Rate Limits | size=13 color=#7C3AED")
print(f"5hr Block: {five_pct:.0f}% (resets {five_reset}) | color={color(five_pct)}")
print(f"Weekly: {week_pct:.0f}% (resets {week_reset}) | color={color(week_pct)}")
if sonnet_pct or sonnet_reset:
    print(f"Sonnet: {sonnet_pct:.0f}% (resets {sonnet_reset}) | color={color(sonnet_pct)}")
print("---")
print(f"Token Usage | size=13 color=#7C3AED")
print(f"Today: {day_tk} . {day_cost}")
print(f"This Month: {month_tk} . {month_cost}")
print("---")
print("Refresh | refresh=true")
PYEOF
