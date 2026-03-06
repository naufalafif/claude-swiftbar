# Claude SwiftBar

macOS menu bar plugin that shows your Claude Code rate limits and token usage at a glance.

![menu bar](https://img.shields.io/badge/macOS-menu%20bar-black?style=flat-square) ![swiftbar](https://img.shields.io/badge/SwiftBar-plugin-blue?style=flat-square)

## What it shows

**Menu bar:**

```
[claude icon] 0% @5pm
```

Shows 5-hour block usage percentage and when it resets.

**Dropdown:**

```
Rate Limits
  5hr Block: 0% (resets @5pm)       <- green
  Weekly: 73% (resets @1pm)          <- yellow
  Sonnet: 41% (resets @sun)          <- green

Token Usage
  Today: 34.6M . $17.46
  This Month: 904.6M . $511.44
```

Rate limit colors: green (<50%), yellow (50-80%), red (80%+).

The setup script also installs a **Claude Code terminal statusline** that shows the same rate limit info inline while you work.

## Quick Install

```bash
bash <(curl -sL https://raw.githubusercontent.com/naufalafif/claude-swiftbar/main/setup.sh)
```

Or clone and run:

```bash
git clone git@github.com:naufalafif/claude-swiftbar.git
cd claude-swiftbar
bash setup.sh
```

## What the setup does

1. Installs [SwiftBar](https://github.com/swiftbar/SwiftBar) (if not present)
2. Installs [ccusage](https://github.com/ryoppippi/ccusage) globally (for token/cost tracking)
3. Installs `jq` (if not present)
4. Downloads and embeds the Claude icon
5. Writes the SwiftBar plugin to `~/Plugins/SwiftBar/`
6. Writes the Claude Code statusline hook to `~/.claude/statusline.sh`
7. Configures Claude Code settings to use the statusline
8. Launches SwiftBar

## Prerequisites

- macOS
- [Homebrew](https://brew.sh)
- [Node.js](https://nodejs.org) (via nvm or system install)
- Python 3 (comes with macOS)
- Claude Code (logged in via OAuth)

## How it works

- **Rate limits** come from Anthropic's OAuth usage API (`/api/oauth/usage`), using your existing Claude Code credentials from macOS Keychain. No extra API keys needed.
- **Token counts and costs** come from [ccusage](https://github.com/ryoppippi/ccusage), which reads local Claude Code session files (`~/.claude/projects/`).
- The menu bar plugin refreshes every **5 minutes**.
- The OAuth cache refreshes every **60 seconds** (in background).
- No cookies harvested, no filesystem crawling — only reads what's needed.

## Files

| File | Description |
|------|-------------|
| `setup.sh` | One-command installer |
| `claude-usage.5m.sh` | SwiftBar plugin (reference copy — setup generates this with your Node.js path and icon) |
| `claude.png` | Claude icon source |

## Uninstall

```bash
rm ~/Plugins/SwiftBar/claude-usage.5m.sh
rm ~/.claude/statusline.sh
brew uninstall --cask swiftbar  # optional
npm uninstall -g ccusage        # optional
```

## License

MIT
