#!/bin/bash
# tool-failure.sh - Claude Code PostToolUseFailure hook
# Notifies when a tool fails
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

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
ERROR=$(echo "$INPUT" | jq -r '.error // "unknown error"' | head -c 200)

telegram_send "❌ Tool failed: $TOOL_NAME
$ERROR"
