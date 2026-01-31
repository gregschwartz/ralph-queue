#!/bin/bash
# permission-request.sh - Claude Code PermissionRequest hook
# Intercepts permission requests and asks via Telegram (or other remote control)
#
# Install: Add to .claude/settings.json:
# {
#   "hooks": {
#     "PermissionRequest": [{
#       "matcher": "Bash",
#       "hooks": [{"type": "command", "command": "/path/to/permission-request.sh"}]
#     }]
#   }
# }

set -euo pipefail

# Debug logging (set TELEGRAM_DEBUG=true in .ralphrc to enable)
telegram_debug() {
    if [[ "${TELEGRAM_DEBUG:-false}" == "true" ]]; then
        echo "[$(date '+%H:%M:%S')] $*" >> .ralph/telegram_debug.log
    fi
}

# Find ralph-queue directory (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_QUEUE_DIR="$(dirname "$SCRIPT_DIR")"

# Load config from .ralphrc in current dir or home
if [[ -f ".ralphrc" ]]; then
    source ".ralphrc"
elif [[ -f "$HOME/.ralphrc" ]]; then
    source "$HOME/.ralphrc"
fi

# Source telegram adapter
if [[ -f "$RALPH_QUEUE_DIR/lib/telegram.sh" ]]; then
    source "$RALPH_QUEUE_DIR/lib/telegram.sh"
fi

# Read JSON input from stdin
INPUT=$(cat)

# Parse input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}')

# Extract details based on tool type
case "$TOOL_NAME" in
    Bash)
        COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // "unknown command"')
        DESCRIPTION=$(echo "$TOOL_INPUT" | jq -r '.description // ""')
        DETAILS="Command: $COMMAND"
        [[ -n "$DESCRIPTION" ]] && DETAILS="$DETAILS\nDescription: $DESCRIPTION"
        ;;
    Edit|Write)
        FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
        DETAILS="File: $FILE_PATH"
        COMMAND="$FILE_PATH"  # For pattern suggestion
        ;;
    Read)
        FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
        DETAILS="File: $FILE_PATH"
        COMMAND="$FILE_PATH"
        ;;
    *)
        DETAILS=$(echo "$TOOL_INPUT" | jq -c '.' | head -c 200)
        COMMAND="$TOOL_NAME"
        ;;
esac

# Generate suggested pattern for auto-allow
suggest_pattern() {
    local tool="$1"
    local cmd="$2"

    case "$tool" in
        Bash)
            local first_word="${cmd%% *}"
            case "$first_word" in
                npm|pnpm|yarn|bun) echo "Bash($first_word *)" ;;
                git) echo "Bash(git *)" ;;
                python|python3) echo "Bash(python*)" ;;
                pip|pip3) echo "Bash(pip*)" ;;
                cargo) echo "Bash(cargo *)" ;;
                go) echo "Bash(go *)" ;;
                make) echo "Bash(make *)" ;;
                docker) echo "Bash(docker *)" ;;
                kubectl) echo "Bash(kubectl *)" ;;
                curl|wget) echo "Bash(curl *)" ;;
                *) echo "Bash($first_word *)" ;;
            esac
            ;;
        Edit|Write)
            # Suggest allowing edits to this directory
            local dir=$(dirname "$cmd")
            echo "$tool($dir/*)"
            ;;
        Read)
            echo "Read(*)"
            ;;
        *)
            echo "$tool(*)"
            ;;
    esac
}

# Output JSON response
output_allow() {
    local pattern="${1:-}"
    if [[ -n "$pattern" ]]; then
        # Allow with permission update
        cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"toolAlwaysAllow","tool":"$TOOL_NAME","arguments":"$pattern"}]}}}
EOF
    else
        # Simple allow
        echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    fi
}

output_deny() {
    local message="${1:-Permission denied by user}"
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"$message"}}}
EOF
}

# If Telegram not enabled, fall through to normal prompt
if [[ "${TELEGRAM_ENABLED:-false}" != "true" ]]; then
    # Exit with no output = show normal permission prompt
    exit 0
fi

# Initialize Telegram (quietly)
telegram_init 2>/dev/null || {
    # If init fails, fall through to normal prompt
    exit 0
}

# Clear pending messages
telegram_poll > /dev/null 2>&1 || true

# Mark the current time - only accept messages sent after this
PERMISSION_START_TIME=$(date +%s)

# Immediately notify that we're handling via Telegram (prevents terminal prompt)
echo "[Ralph] Asking for permission via Telegram..." >&2
telegram_debug "Permission request: $TOOL_NAME - $COMMAND"

# Build message
SUGGESTED=$(suggest_pattern "$TOOL_NAME" "$COMMAND")
MESSAGE="🔐 permission request, tool: $TOOL_NAME
Description: $DESCRIPTION
Command: $COMMAND

/yes - allow this once
/always - always allow '$SUGGESTED'
/no - deny this request
Or type a custom pattern like 'Bash(npm *)'"

# Send and wait for response
if ! telegram_send "$MESSAGE"; then
    echo "[Ralph] Failed to send Telegram message, falling back to terminal" >&2
    exit 0  # Fall through to normal prompt
fi

# Small delay to let Telegram message send before polling
sleep 2

TIMEOUT="${TELEGRAM_ASK_TIMEOUT:-60}"  # 60 seconds default, configurable via .ralphrc
START_TIME=$(date +%s)
POLL_FAILURES=0
MAX_POLL_FAILURES=3

while true; do
    RESPONSE=$(telegram_get_latest_message 2>/dev/null || echo "")
    POLL_EXIT_CODE=$?

    # Track consecutive polling failures
    if [[ $POLL_EXIT_CODE -ne 0 ]]; then
        POLL_FAILURES=$((POLL_FAILURES + 1))
        telegram_debug "Poll failed ($POLL_FAILURES/$MAX_POLL_FAILURES)"
        if [[ $POLL_FAILURES -ge $MAX_POLL_FAILURES ]]; then
            echo "[Ralph] Telegram polling failing repeatedly, denying and falling back" >&2
            telegram_debug "Giving up after $MAX_POLL_FAILURES failures"
            output_deny "Telegram polling failed"
            exit 0
        fi
    else
        POLL_FAILURES=0  # Reset on successful poll
    fi

    if [[ -n "$RESPONSE" ]]; then
        telegram_debug "Got response: $RESPONSE"
        RESPONSE_LOWER=$(echo "$RESPONSE" | tr '[:upper:]' '[:lower:]')

        case "$RESPONSE_LOWER" in
            /yes|yes|y|allow|ok|1)
                telegram_debug "User allowed (once)"
                output_allow
                telegram_send "✅ Allowed (once)" &
                exit 0
                ;;
            /always|all|always|a|allow_all|"allow all")
                telegram_debug "User allowed always: $SUGGESTED"
                output_allow "$SUGGESTED"
                telegram_send "✅ Always allow: $SUGGESTED" &
                exit 0
                ;;
            /no|no|n|deny|0)
                telegram_debug "User denied"
                output_deny "User denied via Telegram"
                telegram_send "❌ Denied" &
                exit 0
                ;;
            bash\(*|"bash ("*|edit\(*|write\(*|read\(*)
                # Custom pattern provided
                PATTERN="$RESPONSE"
                telegram_debug "User provided custom pattern: $PATTERN"
                output_allow "$PATTERN"
                telegram_send "✅ Always allow: $PATTERN" &
                exit 0
                ;;
            *)
                # Could be a question or unclear - ask for clarification
                telegram_send "❓ Unclear. Reply: /yes, /no, /always, or a pattern like 'Bash(npm *)'"
                ;;
        esac
    fi

    ELAPSED=$(( $(date +%s) - START_TIME ))
    if (( ELAPSED >= TIMEOUT )); then
        telegram_debug "Timeout after ${ELAPSED}s (limit: ${TIMEOUT}s) - tool: $TOOL_NAME, command: $COMMAND"
        output_deny "Timeout waiting for user response"
        telegram_send "⏱️ Timeout (${TIMEOUT}s) - denying request for: $COMMAND" &
        exit 0
    fi

    sleep "${TELEGRAM_POLL_INTERVAL:-5}"
done
