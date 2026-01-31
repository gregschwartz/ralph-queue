#!/bin/bash
# install-hooks.sh - Install Ralph's Claude Code hooks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq"
    exit 1
fi

# Create .claude directory if needed
mkdir -p "$CLAUDE_DIR"

# Backup existing settings
if [[ -f "$SETTINGS_FILE" ]]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
    echo "Backed up existing settings"
    EXISTING=$(cat "$SETTINGS_FILE")
else
    EXISTING='{}'
fi

# Build hooks configuration
HOOKS_CONFIG=$(cat <<EOF
{
  "PermissionRequest": [
    {"matcher": "Bash", "hooks": [{"type": "command", "command": "$SCRIPT_DIR/permission-request.sh"}]},
    {"matcher": "Edit", "hooks": [{"type": "command", "command": "$SCRIPT_DIR/permission-request.sh"}]},
    {"matcher": "Write", "hooks": [{"type": "command", "command": "$SCRIPT_DIR/permission-request.sh"}]}
  ],
  "Notification": [
    {"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": "$SCRIPT_DIR/notification.sh"}]},
    {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "$SCRIPT_DIR/notification.sh"}]},
    {"matcher": "idle_prompt", "hooks": [{"type": "command", "command": "$SCRIPT_DIR/notification.sh"}]}
  ],
  "Stop": [
    {"hooks": [{"type": "command", "command": "$SCRIPT_DIR/stop.sh"}]}
  ],
  "PostToolUseFailure": [
    {"hooks": [{"type": "command", "command": "$SCRIPT_DIR/tool-failure.sh"}]}
  ]
}
EOF
)

# Merge with existing settings
echo "$EXISTING" | jq --argjson hooks "$HOOKS_CONFIG" '.hooks = ($hooks + (.hooks // {}))' > "$SETTINGS_FILE"

echo "Installed hooks:"
echo "  - PermissionRequest: Ask via Telegram for Bash/Edit/Write"
echo "  - Notification: Forward questions and prompts to Telegram"
echo "  - Stop: Notify on completion/errors"
echo "  - PostToolUseFailure: Alert on tool failures"
echo ""
echo "Done! Claude Code will now notify you via Telegram."
