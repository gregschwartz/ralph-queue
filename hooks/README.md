# Ralph Claude Code Hooks

Hooks that intercept Claude Code's permission requests and route them through Telegram (or other remote control adapters).

## Quick Install

```bash
./install-hooks.sh
```

This adds the PermissionRequest hook to `~/.claude/settings.json`.

## Manual Install

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [{
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": "/path/to/ralph-queue/hooks/permission-request.sh"}]
    }]
  }
}
```

## How It Works

1. Claude Code wants to run a Bash command
2. Instead of showing terminal prompt, hook fires
3. Hook sends permission request to Telegram
4. You respond via Telegram (yes/no/always)
5. Hook returns decision to Claude Code

## Telegram Responses

| Response | Action |
|----------|--------|
| `yes`, `allow`, `y` | Allow this command once |
| `all`, `always` | Always allow this pattern |
| `no`, `deny`, `n` | Deny the request |
| `Bash(npm *)` | Always allow custom pattern |

## Setup

Run the installer - it will prompt to set up Telegram if not configured:

```bash
./install-hooks.sh
```

Or set up Telegram separately:

```bash
./setup-telegram.sh
```

## Requirements

- `jq` installed (for JSON parsing)
- `curl` for Telegram API calls

## Fallback

If Telegram is not enabled/configured, the hook exits silently and Claude Code shows the normal terminal permission prompt.
