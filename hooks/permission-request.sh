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

# Build message
SUGGESTED=$(suggest_pattern "$TOOL_NAME" "$COMMAND")
MESSAGE="🔐 Permission Request

Tool: $TOOL_NAME
$DETAILS

Reply with:
• yes / allow - allow this once
• all / always - always allow '$SUGGESTED'
• no / deny - deny this request
• Or type a custom pattern like 'Bash(npm *)'"

# Send and wait for response
telegram_send "$MESSAGE"

TIMEOUT="${TELEGRAM_ASK_TIMEOUT:-120}"
START_TIME=$(date +%s)

while true; do
    RESPONSE=$(telegram_get_latest_message 2>/dev/null || echo "")

    if [[ -n "$RESPONSE" ]]; then
        RESPONSE_LOWER=$(echo "$RESPONSE" | tr '[:upper:]' '[:lower:]')

        case "$RESPONSE_LOWER" in
            yes|y|allow|ok|1)
                telegram_send "✅ Allowed (once)"
                output_allow
                exit 0
                ;;
            all|always|allow_all|"allow all")
                telegram_send "✅ Always allow: $SUGGESTED"
                output_allow "$SUGGESTED"
                exit 0
                ;;
            no|n|deny|0)
                telegram_send "❌ Denied"
                output_deny "User denied via Telegram"
                exit 0
                ;;
            bash\(*|"bash ("*|edit\(*|write\(*|read\(*)
                # Custom pattern provided
                PATTERN="$RESPONSE"
                telegram_send "✅ Always allow: $PATTERN"
                output_allow "$PATTERN"
                exit 0
                ;;
            *)
                # Could be a question or unclear - ask for clarification
                telegram_send "❓ Unclear. Reply: yes, no, all, or a pattern like 'Bash(npm *)'"
                ;;
        esac
    fi

    ELAPSED=$(( $(date +%s) - START_TIME ))
    if (( ELAPSED >= TIMEOUT )); then
        telegram_send "⏱️ Timeout - denying request"
        output_deny "Timeout waiting for user response"
        exit 0
    fi

    sleep "${TELEGRAM_POLL_INTERVAL:-5}"
done
