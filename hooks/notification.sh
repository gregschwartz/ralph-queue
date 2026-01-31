#!/bin/bash
# notification.sh - Claude Code Notification hook
# Sends notifications to Telegram when Claude needs attention
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_QUEUE_DIR="$(dirname "$SCRIPT_DIR")"

# Load config
if [[ -f ".ralphrc" ]]; then
    source ".ralphrc"
elif [[ -f "$HOME/.ralphrc" ]]; then
    source "$HOME/.ralphrc"
fi

# Source telegram
if [[ -f "$RALPH_QUEUE_DIR/lib/telegram.sh" ]]; then
    source "$RALPH_QUEUE_DIR/lib/telegram.sh"
fi

# Exit if Telegram not enabled
if [[ "${TELEGRAM_ENABLED:-false}" != "true" ]]; then
    exit 0
fi

# Read JSON input
INPUT=$(cat)

# Parse notification type
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')

case "$NOTIFICATION_TYPE" in
    elicitation_dialog)
        # Claude is asking user a question!
        TITLE=$(echo "$INPUT" | jq -r '.title // "Question"')
        MESSAGE=$(echo "$INPUT" | jq -r '.message // ""')
        OPTIONS=$(echo "$INPUT" | jq -r '.options // [] | map(.label) | join(", ")')

        telegram_send "❓ Claude needs input:

$TITLE
$MESSAGE

Options: $OPTIONS

Reply with your choice or answer."
        ;;

    permission_prompt)
        # Already handled by permission-request.sh, but notify anyway
        telegram_send "🔐 Permission prompt shown in terminal"
        ;;

    idle_prompt)
        telegram_send "💤 Claude is idle and waiting for input"
        ;;

    auth_success)
        telegram_send "✅ Authentication successful"
        ;;

    *)
        # Log unknown notification types for debugging
        telegram_send "📢 Notification: $NOTIFICATION_TYPE"
        ;;
esac
