#!/bin/bash
# install-hooks.sh - Install Ralph's Claude Code hooks
#
# This adds the PermissionRequest hook to your Claude Code settings.
# The hook intercepts permission dialogs and asks via Telegram instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PATH="$SCRIPT_DIR/permission-request.sh"

# Claude settings location
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "=== Ralph Hook Installer ==="
echo ""

# Check if Telegram is configured
if [[ -f ".ralphrc" ]]; then
    source ".ralphrc"
elif [[ -f "$HOME/.ralphrc" ]]; then
    source "$HOME/.ralphrc"
fi

if [[ "${TELEGRAM_ENABLED:-false}" != "true" ]]; then
    echo "Telegram not configured."
    echo ""
    read -p "Set up Telegram now? [Y/n] " setup
    if [[ "$(echo "${setup:-y}" | tr '[:upper:]' '[:lower:]')" != "n" ]]; then
        "$SCRIPT_DIR/setup-telegram.sh"
        # Reload config
        if [[ -f "$HOME/.ralphrc" ]]; then
            source "$HOME/.ralphrc"
        fi
    fi
fi

# Create .claude directory if needed
mkdir -p "$CLAUDE_DIR"

# Check existing settings
if [[ -f "$SETTINGS_FILE" ]]; then
    echo "Found existing settings at $SETTINGS_FILE"

    # Check if hook already exists
    if grep -q "permission-request.sh" "$SETTINGS_FILE" 2>/dev/null; then
        echo "Hook already installed!"
        exit 0
    fi

    # Backup existing
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
    echo "Backed up to $SETTINGS_FILE.bak"

    # Try to merge using jq
    if command -v jq &> /dev/null; then
        # Add hooks for Bash, Edit, Write
        HOOKS_JSON=$(cat <<EOF
[
  {"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]},
  {"matcher": "Edit", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]},
  {"matcher": "Write", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]}
]
EOF
)
        # Check if hooks.PermissionRequest exists
        if jq -e '.hooks.PermissionRequest' "$SETTINGS_FILE" > /dev/null 2>&1; then
            # Append to existing array
            jq ".hooks.PermissionRequest += $HOOKS_JSON" "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        else
            # Create hooks.PermissionRequest
            jq ".hooks.PermissionRequest = $HOOKS_JSON" "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        fi
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo "Added hooks for Bash, Edit, Write"
    else
        echo "jq not found - please manually add the hook config"
        echo ""
        echo "Add this to $SETTINGS_FILE under 'hooks':"
        cat <<EOF
"PermissionRequest": [
  {"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]},
  {"matcher": "Edit", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]},
  {"matcher": "Write", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]}
]
EOF
        exit 1
    fi
else
    # Create new settings file
    cat > "$SETTINGS_FILE" <<EOF
{
  "hooks": {
    "PermissionRequest": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]},
      {"matcher": "Edit", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]},
      {"matcher": "Write", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]}
    ]
  }
}
EOF
    echo "Created new settings at $SETTINGS_FILE"
fi

echo ""
echo "Hook installed!"
echo ""
echo "When Claude Code requests permission for Bash commands,"
echo "you'll now be asked via Telegram instead of the terminal."
echo ""
echo "Responses:"
echo "  yes/allow  - allow this command once"
echo "  all/always - always allow this pattern"
echo "  no/deny    - deny the request"
echo "  Bash(...)  - custom pattern to always allow"
