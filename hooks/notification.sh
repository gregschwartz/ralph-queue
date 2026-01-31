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

# Clear idle timestamp for non-idle notifications (Claude is active)
IDLE_TIMESTAMP_FILE=".ralph/.idle_start_time"
if [[ "$NOTIFICATION_TYPE" != "idle_prompt" ]] && [[ -f "$IDLE_TIMESTAMP_FILE" ]]; then
    rm -f "$IDLE_TIMESTAMP_FILE"
fi

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
        # 5-minute delay before sending idle alert
        IDLE_TIMESTAMP_FILE=".ralph/.idle_start_time"
        IDLE_DELAY_SECONDS=300  # 5 minutes
        CURRENT_TIME=$(date +%s)

        if [[ -f "$IDLE_TIMESTAMP_FILE" ]]; then
            # Read when idle started
            IDLE_START=$(cat "$IDLE_TIMESTAMP_FILE")
            ELAPSED=$((CURRENT_TIME - IDLE_START))

            if [[ $ELAPSED -ge $IDLE_DELAY_SECONDS ]]; then
                # 5 minutes have passed, send alert
                telegram_send "💤 Claude is idle and waiting for input (idle for $((ELAPSED / 60)) minutes)"
                # Don't delete the file - keep tracking idle time
            fi
            # else: still within 5-minute grace period, don't send alert
        else
            # First time seeing idle, record the timestamp
            mkdir -p .ralph
            echo "$CURRENT_TIME" > "$IDLE_TIMESTAMP_FILE"
        fi
        ;;

    auth_success)
        telegram_send "✅ Authentication successful"
        ;;

    *)
        # Log unknown notification types for debugging
        telegram_send "📢 Notification: $NOTIFICATION_TYPE"
        ;;
esac
