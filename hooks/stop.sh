#!/bin/bash
# stop.sh - Claude Code Stop hook
# Notifies when Claude finishes responding
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

# Parse stop reason
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "unknown"')
NUM_TURNS=$(echo "$INPUT" | jq -r '.num_turns // 0')

case "$STOP_REASON" in
    end_turn)
        # Normal completion - only notify if significant work done
        if (( NUM_TURNS > 1 )); then
            telegram_send "✅ Claude finished ($NUM_TURNS turns)"
        fi
        ;;

    max_turns)
        telegram_send "⚠️ Claude hit max turns limit ($NUM_TURNS)"
        ;;

    interrupt)
        telegram_send "🛑 Claude was interrupted"
        ;;

    error)
        ERROR=$(echo "$INPUT" | jq -r '.error // "unknown error"')
        telegram_send "❌ Claude stopped with error: $ERROR"
        ;;

    *)
        # Don't spam for every stop
        ;;
esac
