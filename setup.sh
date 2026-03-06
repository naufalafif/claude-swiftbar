#!/bin/bash
set -euo pipefail

# ============================================================
# Claude Code Menu Bar Setup
# Installs SwiftBar + Claude usage plugin + statusline hook
# ============================================================

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'
RESET='\033[0m'

log()  { echo -e "${GREEN}[+]${RESET} $1"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; }
err()  { echo -e "${RED}[x]${RESET} $1"; exit 1; }

PLUGIN_DIR="$HOME/Plugins/SwiftBar"

# --- Prerequisites ---
command -v brew &>/dev/null || err "Homebrew is required. Install from https://brew.sh"
command -v python3 &>/dev/null || err "Python 3 is required"
command -v jq &>/dev/null || { log "Installing jq..."; brew install jq; }

# --- Detect Node.js path (nvm or system) ---
NODE_BIN=""
if [ -d "$HOME/.nvm" ]; then
    NVM_NODE=$(ls -d "$HOME/.nvm/versions/node"/*/bin 2>/dev/null | sort -V | tail -1)
    [ -n "$NVM_NODE" ] && NODE_BIN="$NVM_NODE"
fi
if [ -z "$NODE_BIN" ]; then
    NODE_BIN=$(dirname "$(which node 2>/dev/null)" || echo "")
fi
[ -z "$NODE_BIN" ] && err "Node.js is required for ccusage. Install via nvm or brew install node"
log "Using Node.js from: $NODE_BIN"

# --- Install SwiftBar ---
if [ -d "/Applications/SwiftBar.app" ]; then
    log "SwiftBar already installed"
else
    log "Installing SwiftBar..."
    brew install --cask swiftbar
fi

# --- Create plugin directory ---
mkdir -p "$PLUGIN_DIR"

# --- Set SwiftBar plugin directory ---
defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR" 2>/dev/null || true
log "Plugin directory: $PLUGIN_DIR"

# --- Install ccusage globally ---
if PATH="$NODE_BIN:$PATH" command -v ccusage &>/dev/null; then
    log "ccusage already installed"
else
    log "Installing ccusage..."
    PATH="$NODE_BIN:$PATH" npm install -g ccusage
fi

# --- Download Claude icon ---
ICON_FILE="/tmp/claude-menubar-icon.png"
log "Fetching Claude icon..."
curl -sL "https://claude.ai/favicon.ico" -o "$ICON_FILE.ico"
sips -s format png -z 16 16 "$ICON_FILE.ico" --out "$ICON_FILE" &>/dev/null
ICON_B64=$(base64 -i "$ICON_FILE" | tr -d '\n')
rm -f "$ICON_FILE.ico"
log "Icon ready (16x16 base64)"

# --- Write SwiftBar plugin ---
PLUGIN_FILE="$PLUGIN_DIR/claude-usage.5m.sh"
log "Writing plugin to $PLUGIN_FILE"

cat > "$PLUGIN_FILE" << 'PLUGIN_HEADER'
#!/bin/bash
# <bitbar.title>Claude Code Usage</bitbar.title>
# <bitbar.version>5.0</bitbar.version>
# <bitbar.author>naufal</bitbar.author>
# <bitbar.desc>Shows Claude Code rate limits and token usage</bitbar.desc>

PLUGIN_HEADER

cat >> "$PLUGIN_FILE" << EOF
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:${NODE_BIN}:\$PATH"
EOF

cat >> "$PLUGIN_FILE" << 'PLUGIN_BODY'

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

PLUGIN_BODY

cat >> "$PLUGIN_FILE" << EOF
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
            return fmt, f"\\\${cost:.2f}"
    except:
        return "0", "\\\$0.00"

day_tk, day_cost = load_tokens("daily")
month_tk, month_cost = load_tokens("monthly")

def color(pct):
    if pct >= 80: return "#ef4444"
    if pct >= 50: return "#eab308"
    return "#22c55e"

ICON="${ICON_B64}"

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
EOF

chmod +x "$PLUGIN_FILE"
log "Plugin installed and executable"

# --- Write Claude Code statusline hook ---
STATUSLINE="$HOME/.claude/statusline.sh"
log "Writing statusline to $STATUSLINE"

cat > "$STATUSLINE" << 'STATUSLINE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Custom Claude Code statusline showing model, context, and rate limits
# Usage: echo '{"model":{...},"context_window":{...}}' | bash ~/.claude/statusline.sh

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
RESET='\033[0m'

CACHE_FILE="$HOME/.claude/usage-cache.json"
CACHE_TTL=60

format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        echo "$((num / 1000000))M"
    elif [ "$num" -ge 1000 ]; then
        echo "$((num / 1000))K"
    else
        echo "$num"
    fi
}

color_for_pct() {
    local pct=$1
    if [ "${pct%.*}" -ge 80 ]; then
        echo -e "$RED"
    elif [ "${pct%.*}" -ge 50 ]; then
        echo -e "$YELLOW"
    else
        echo -e "$GREEN"
    fi
}

format_reset_time() {
    local iso_time=$1
    local clean_time=$(echo "$iso_time" | sed -E 's/\.[0-9]+//; s/\+00:00$/+0000/')

    if command -v gdate &> /dev/null; then
        local epoch=$(gdate -d "$iso_time" +%s 2>/dev/null || echo "")
    else
        local epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$clean_time" +%s 2>/dev/null || echo "")
    fi

    if [ -z "$epoch" ]; then
        echo "$iso_time" | sed -E 's/.*T([0-9]{2}):([0-9]{2}).*/\1:\2/' | sed 's/^0//'
        return
    fi

    local now=$(date +%s)
    local diff=$((epoch - now))

    if [ "$diff" -lt 86400 ]; then
        date -r "$epoch" "+%-I%p" | tr '[:upper:]' '[:lower:]'
    else
        date -r "$epoch" "+%a"
    fi
}

fetch_usage() {
    local credentials token
    credentials=$(security find-generic-password -s "Claude Code-credentials" -a "$USER" -w 2>/dev/null || echo "")
    [ -z "$credentials" ] && return 1
    token=$(echo "$credentials" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null || echo "")
    [ -z "$token" ] && return 1
    curl -s -f \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" \
        -o "$CACHE_FILE.tmp" 2>/dev/null || return 1
    mv "$CACHE_FILE.tmp" "$CACHE_FILE" 2>/dev/null || return 1
}

check_and_refresh_cache() {
    if [ ! -f "$CACHE_FILE" ]; then
        ( fetch_usage ) &
        local pid=$!
        ( sleep 0.5 && kill -9 $pid 2>/dev/null ) &
        wait $pid 2>/dev/null || true
        return
    fi

    local cache_age=0
    if stat -f%m "$CACHE_FILE" &>/dev/null; then
        local cache_mtime=$(stat -f%m "$CACHE_FILE" 2>/dev/null || echo "0")
        local now=$(date +%s)
        cache_age=$((now - cache_mtime))
    elif stat -c%Y "$CACHE_FILE" &>/dev/null; then
        local cache_mtime=$(stat -c%Y "$CACHE_FILE" 2>/dev/null || echo "0")
        local now=$(date +%s)
        cache_age=$((now - cache_mtime))
    fi

    if [ "$cache_age" -gt "$CACHE_TTL" ]; then
        ( fetch_usage ) &>/dev/null &
    fi
}

main() {
    local stdin_json
    stdin_json=$(cat)

    local model_name ctx_pct ctx_used ctx_total

    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required" >&2
        exit 1
    fi

    model_name=$(echo "$stdin_json" | jq -r '.model.display_name // "Unknown"' 2>/dev/null || echo "Unknown")
    ctx_pct=$(echo "$stdin_json" | jq -r '.context_window.used_percentage // 0' 2>/dev/null || echo "0")
    ctx_total=$(echo "$stdin_json" | jq -r '.context_window.context_window_size // 0' 2>/dev/null || echo "0")
    ctx_used=$(echo "$stdin_json" | jq -r '
        .context_window.current_usage // {} |
        (.input_tokens // 0) + (.output_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
    ' 2>/dev/null || echo "0")

    local output=""
    output+="[${model_name}]"

    local ctx_color=$(color_for_pct "$ctx_pct")
    local ctx_used_fmt=$(format_tokens "$ctx_used")
    local ctx_total_fmt=$(format_tokens "$ctx_total")
    output+=" Ctx: ${ctx_color}${ctx_pct%%.*}%${RESET} (${ctx_used_fmt}/${ctx_total_fmt})"

    check_and_refresh_cache

    if [ -f "$CACHE_FILE" ]; then
        local usage_json
        usage_json=$(cat "$CACHE_FILE" 2>/dev/null || echo "{}")

        local five_hour_pct=$(echo "$usage_json" | jq -r '.five_hour.utilization // null' 2>/dev/null)
        if [ "$five_hour_pct" != "null" ] && [ -n "$five_hour_pct" ]; then
            local five_hour_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)
            local five_hour_time=$(format_reset_time "$five_hour_reset")
            local five_hour_color=$(color_for_pct "$five_hour_pct")
            output+=" ${DIM}|${RESET} 5hr: ${five_hour_color}${five_hour_pct%%.*}%${RESET} @${five_hour_time}"
        fi

        local seven_day_pct=$(echo "$usage_json" | jq -r '.seven_day.utilization // null' 2>/dev/null)
        if [ "$seven_day_pct" != "null" ] && [ -n "$seven_day_pct" ]; then
            local seven_day_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // ""' 2>/dev/null)
            local seven_day_time=$(format_reset_time "$seven_day_reset")
            local seven_day_color=$(color_for_pct "$seven_day_pct")
            output+=" ${DIM}|${RESET} Wk: ${seven_day_color}${seven_day_pct%%.*}%${RESET} @${seven_day_time}"
        fi

        local sonnet_pct=$(echo "$usage_json" | jq -r '.seven_day_sonnet.utilization // null' 2>/dev/null)
        if [ "$sonnet_pct" != "null" ] && [ -n "$sonnet_pct" ]; then
            local sonnet_reset=$(echo "$usage_json" | jq -r '.seven_day_sonnet.resets_at // ""' 2>/dev/null)
            local sonnet_time=$(format_reset_time "$sonnet_reset")
            local sonnet_color=$(color_for_pct "$sonnet_pct")
            output+=" ${DIM}|${RESET} Son: ${sonnet_color}${sonnet_pct%%.*}%${RESET} @${sonnet_time}"
        fi

    fi

    echo -e "$output"
}

main "$@"
STATUSLINE_SCRIPT

chmod +x "$STATUSLINE"
log "Statusline hook installed"

# --- Configure Claude Code to use statusline ---
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    if jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null; then
        log "Claude Code statusLine already configured"
    else
        jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline.sh"}}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        log "Added statusLine to Claude Code settings"
    fi
else
    echo '{"statusLine": {"type": "command", "command": "bash ~/.claude/statusline.sh"}}' > "$SETTINGS_FILE"
    log "Created Claude Code settings with statusLine"
fi

# --- Launch SwiftBar ---
log "Starting SwiftBar..."
killall SwiftBar 2>/dev/null || true
sleep 1
open -a SwiftBar

echo ""
echo -e "${BOLD}Setup complete!${RESET}"
echo ""
echo "  Menu bar: Claude icon + 5hr usage % + reset time"
echo "  Dropdown: Rate limits (5hr/weekly/sonnet) + token usage (today/monthly)"
echo "  Statusline: Model + context + all rate limits in Claude Code terminal"
echo ""
echo "  Plugin refreshes every 5 minutes."
echo "  OAuth cache refreshes every 60 seconds."
echo ""
