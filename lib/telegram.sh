#!/bin/bash
# telegram.sh - Telegram adapter for Ralph remote control
# Implements the remote_control.sh interface for Telegram
#
# To use:
#   1. Set TELEGRAM_ENABLED=true
#   2. Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
#   3. Set REMOTE_CONTROL_ADAPTER=telegram

# Source the generic interface (if not already sourced)
SCRIPT_DIR_TELEGRAM="$(dirname "${BASH_SOURCE[0]}")"
if [[ -z "${RC_ADAPTERS[*]:-}" ]]; then
    source "$SCRIPT_DIR_TELEGRAM/remote_control.sh"
fi

# Configuration (set via environment or .ralphrc)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-false}"
TELEGRAM_ASK_TIMEOUT="${TELEGRAM_ASK_TIMEOUT:-300}"  # 5 minutes default
TELEGRAM_POLL_INTERVAL="${TELEGRAM_POLL_INTERVAL:-5}"  # seconds
TELEGRAM_LAST_UPDATE_ID_FILE="${RALPH_DIR:-.ralph}/.telegram_last_update_id"

# User whitelist - comma-separated user IDs that can send commands
# If empty, only TELEGRAM_CHAT_ID is allowed (your chat)
# Get your user ID by messaging @userinfobot on Telegram
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS:-}"

# Check if a user ID is authorized
telegram_is_authorized() {
    local user_id="$1"

    # Always allow the configured chat ID
    if [[ "$user_id" == "$TELEGRAM_CHAT_ID" ]]; then
        return 0
    fi

    # If no whitelist, only allow chat ID
    if [[ -z "$TELEGRAM_ALLOWED_USERS" ]]; then
        return 1
    fi

    # Check whitelist
    local users
    IFS=',' read -ra users <<< "$TELEGRAM_ALLOWED_USERS"
    for allowed in "${users[@]}"; do
        allowed=$(echo "$allowed" | xargs)  # trim whitespace
        if [[ "$user_id" == "$allowed" ]]; then
            return 0
        fi
    done

    return 1
}

# Initialize Telegram - check config and connectivity
telegram_init() {
    if [[ "$TELEGRAM_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        echo "[telegram] Error: TELEGRAM_BOT_TOKEN not set" >&2
        return 1
    fi

    if [[ -z "$TELEGRAM_CHAT_ID" ]]; then
        echo "[telegram] Error: TELEGRAM_CHAT_ID not set" >&2
        return 1
    fi

    # Test connectivity
    local response
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")
    if ! echo "$response" | jq -e '.ok' > /dev/null 2>&1; then
        echo "[telegram] Error: Failed to connect to Telegram API" >&2
        echo "[telegram] Response: $response" >&2
        return 1
    fi

    local bot_name
    bot_name=$(echo "$response" | jq -r '.result.username')
    echo "[telegram] Connected as @${bot_name}"

    # Initialize last update ID if not exists
    if [[ ! -f "$TELEGRAM_LAST_UPDATE_ID_FILE" ]]; then
        echo "0" > "$TELEGRAM_LAST_UPDATE_ID_FILE"
    fi

    return 0
}

# Send a message to Telegram
telegram_send() {
    local message="$1"
    local parse_mode="${2:-}"  # Optional: "Markdown" or "HTML"
    local delay="${3:-5}"      # Default 5s delay to see on screen

    if [[ "$TELEGRAM_ENABLED" != "true" ]]; then
        return 0
    fi

    # Wait so user can see action on screen first
    if [[ "$delay" -gt 0 ]]; then
        sleep "$delay"
    fi

    local data="chat_id=${TELEGRAM_CHAT_ID}&text=${message}"
    if [[ -n "$parse_mode" ]]; then
        data="${data}&parse_mode=${parse_mode}"
    fi

    local response
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        ${parse_mode:+--data-urlencode "parse_mode=${parse_mode}"})

    if ! echo "$response" | jq -e '.ok' > /dev/null 2>&1; then
        echo "[telegram] Failed to send message: $response" >&2
        return 1
    fi

    return 0
}

# Send a notification (convenience wrapper with emoji)
telegram_notify() {
    local type="$1"
    local message="$2"

    local emoji
    case "$type" in
        start)    emoji="🚀" ;;
        complete) emoji="✅" ;;
        error)    emoji="❌" ;;
        warning)  emoji="⚠️" ;;
        question) emoji="❓" ;;
        blocked)  emoji="🛑" ;;
        progress) emoji="🔄" ;;
        *)        emoji="📢" ;;
    esac

    telegram_send "${emoji} ${message}"
}

# Poll for new messages
telegram_poll() {
    if [[ "$TELEGRAM_ENABLED" != "true" ]]; then
        return 0
    fi

    local last_update_id
    last_update_id=$(cat "$TELEGRAM_LAST_UPDATE_ID_FILE" 2>/dev/null || echo "0")

    local offset=$((last_update_id + 1))
    local response
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${offset}&timeout=1")

    if ! echo "$response" | jq -e '.ok' > /dev/null 2>&1; then
        echo "[telegram] Poll failed: $response" >&2
        return 1
    fi

    # Update last_update_id if we got new messages
    local new_last_id
    new_last_id=$(echo "$response" | jq -r '.result[-1].update_id // empty')
    if [[ -n "$new_last_id" ]]; then
        echo "$new_last_id" > "$TELEGRAM_LAST_UPDATE_ID_FILE"
    fi

    echo "$response"
}

# Get the latest message text from authorized users only
telegram_get_latest_message() {
    local poll_result
    poll_result=$(telegram_poll)

    if [[ -z "$poll_result" ]]; then
        return 1
    fi

    # Get all new messages
    local messages
    messages=$(echo "$poll_result" | jq -c '.result[]?.message // empty' 2>/dev/null)

    if [[ -z "$messages" ]]; then
        return 1
    fi

    # Find the latest message from an authorized user
    local latest_text=""
    local latest_from=""

    while IFS= read -r msg; do
        [[ -z "$msg" ]] && continue

        local from_id
        from_id=$(echo "$msg" | jq -r '.from.id // empty')
        local chat_id
        chat_id=$(echo "$msg" | jq -r '.chat.id // empty')

        # Check authorization (by user ID or chat ID)
        if telegram_is_authorized "$from_id" || telegram_is_authorized "$chat_id"; then
            latest_text=$(echo "$msg" | jq -r '.text // empty')
            latest_from=$(echo "$msg" | jq -r '.from.username // .from.first_name // "unknown"')
        else
            echo "[telegram] Ignored message from unauthorized user: ${from_id}" >&2
        fi
    done <<< "$messages"

    if [[ -n "$latest_text" ]]; then
        echo "$latest_text"
        return 0
    fi

    return 1
}

# Ask a question and wait for human response (BLOCKING)
telegram_ask() {
    local question="$1"
    local timeout="${2:-$TELEGRAM_ASK_TIMEOUT}"

    if [[ "$TELEGRAM_ENABLED" != "true" ]]; then
        echo "[telegram] Telegram not enabled, skipping ask" >&2
        echo "SKIPPED"
        return 0
    fi

    # Clear any pending messages first
    telegram_poll > /dev/null 2>&1

    # Send the question
    telegram_notify "question" "Ralph needs input:

${question}

(Reply within ${timeout}s or I'll continue without input)"

    local start_time
    start_time=$(date +%s)

    while true; do
        local response
        response=$(telegram_get_latest_message)

        if [[ -n "$response" && "$response" != "null" ]]; then
            telegram_send "✓ Got it: ${response}"
            echo "$response"
            return 0
        fi

        local elapsed=$(( $(date +%s) - start_time ))
        if (( elapsed >= timeout )); then
            telegram_send "⏱️ Timeout - continuing without input"
            echo "TIMEOUT"
            return 1
        fi

        sleep "$TELEGRAM_POLL_INTERVAL"
    done
}

# Ask yes/no question with default
telegram_confirm() {
    local question="$1"
    local default="${2:-no}"  # "yes" or "no"
    local timeout="${3:-60}"

    local prompt
    if [[ "$default" == "yes" ]]; then
        prompt="${question} [Y/n]"
    else
        prompt="${question} [y/N]"
    fi

    local response
    response=$(telegram_ask "$prompt" "$timeout")

    case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in  # lowercase
        y|yes|yep|sure|ok|1|true)
            echo "yes"
            return 0
            ;;
        n|no|nope|nah|0|false)
            echo "no"
            return 1
            ;;
        timeout|skipped)
            echo "$default"
            [[ "$default" == "yes" ]] && return 0 || return 1
            ;;
        *)
            # Unclear response, use default
            echo "$default"
            [[ "$default" == "yes" ]] && return 0 || return 1
            ;;
    esac
}

# Send loop status update
telegram_loop_status() {
    local iteration="$1"
    local max_iterations="$2"
    local status="$3"
    local task_info="${4:-}"

    local message="Loop ${iteration}/${max_iterations}: ${status}"
    if [[ -n "$task_info" ]]; then
        message="${message}
Task: ${task_info}"
    fi

    telegram_notify "progress" "$message"
}

# Send message with inline keyboard buttons
telegram_send_buttons() {
    local message="$1"
    shift
    local buttons=("$@")  # Array of "label:callback_data" pairs

    if [[ "$TELEGRAM_ENABLED" != "true" ]]; then
        return 0
    fi

    # Build inline keyboard JSON
    local keyboard='{"inline_keyboard":[['
    local first=true
    for btn in "${buttons[@]}"; do
        local label="${btn%%:*}"
        local data="${btn#*:}"
        if [[ "$first" != "true" ]]; then
            keyboard+=','
        fi
        keyboard+="{\"text\":\"${label}\",\"callback_data\":\"${data}\"}"
        first=false
    done
    keyboard+=']]}'

    local response
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"${message}\",\"reply_markup\":${keyboard}}")

    if ! echo "$response" | jq -e '.ok' > /dev/null 2>&1; then
        echo "[telegram] Failed to send buttons: $response" >&2
        return 1
    fi

    # Return message_id for later reference
    echo "$response" | jq -r '.result.message_id'
}

# Wait for button callback
telegram_wait_for_callback() {
    local timeout="${1:-$TELEGRAM_ASK_TIMEOUT}"

    local start_time
    start_time=$(date +%s)

    while true; do
        local poll_result
        poll_result=$(telegram_poll)

        if [[ -n "$poll_result" ]]; then
            # Check for callback_query (button press)
            local callback
            callback=$(echo "$poll_result" | jq -r '.result[]?.callback_query // empty' 2>/dev/null | head -1)

            if [[ -n "$callback" && "$callback" != "null" ]]; then
                local from_id
                from_id=$(echo "$callback" | jq -r '.from.id')

                if telegram_is_authorized "$from_id"; then
                    local data
                    data=$(echo "$callback" | jq -r '.data')

                    # Answer the callback to remove "loading" state
                    local callback_id
                    callback_id=$(echo "$callback" | jq -r '.id')
                    curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/answerCallbackQuery" \
                        -d "callback_query_id=${callback_id}" > /dev/null

                    echo "$data"
                    return 0
                fi
            fi

            # Also check for text messages as fallback
            local text
            text=$(telegram_get_latest_message)
            if [[ -n "$text" ]]; then
                echo "$text"
                return 0
            fi
        fi

        local elapsed=$(( $(date +%s) - start_time ))
        if (( elapsed >= timeout )); then
            echo "TIMEOUT"
            return 1
        fi

        sleep "$TELEGRAM_POLL_INTERVAL"
    done
}

# Ask yes/no with buttons
telegram_ask_yes_no() {
    local question="$1"
    local timeout="${2:-60}"

    # Clear pending updates
    telegram_poll > /dev/null 2>&1

    telegram_send_buttons "$question" "Yes:yes" "No:no"

    local response
    response=$(telegram_wait_for_callback "$timeout")

    case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in
        yes|y|1|true)
            telegram_send "✓ Yes"
            echo "yes"
            return 0
            ;;
        no|n|0|false)
            telegram_send "✓ No"
            echo "no"
            return 1
            ;;
        timeout)
            telegram_send "⏱️ Timeout - defaulting to No"
            echo "no"
            return 1
            ;;
        *)
            telegram_send "? Unclear - treating as No"
            echo "no"
            return 1
            ;;
    esac
}

# Ask permission with Allow/Deny buttons
telegram_ask_permission() {
    local action="$1"
    local details="${2:-}"
    local timeout="${3:-120}"

    local message="🔐 Permission Request

Action: ${action}"

    if [[ -n "$details" ]]; then
        message+="

Details: ${details}"
    fi

    message+="

(Auto-deny in ${timeout}s)"

    # Clear pending updates
    telegram_poll > /dev/null 2>&1

    telegram_send_buttons "$message" "✅ Allow:allow" "❌ Deny:deny" "⏭️ Allow All:allow_all"

    local response
    response=$(telegram_wait_for_callback "$timeout")

    case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in
        allow)
            telegram_send "✅ Allowed: ${action}"
            echo "allow"
            return 0
            ;;
        allow_all)
            telegram_send "✅ Allowed all future permissions"
            echo "allow_all"
            return 0
            ;;
        deny|timeout)
            telegram_send "❌ Denied: ${action}"
            echo "deny"
            return 1
            ;;
        *)
            telegram_send "❌ Unknown response - denying"
            echo "deny"
            return 1
            ;;
    esac
}

# Send completion summary
telegram_complete() {
    local iterations="$1"
    local tasks_completed="$2"
    local duration="$3"

    telegram_notify "complete" "Ralph finished!
• Iterations: ${iterations}
• Tasks completed: ${tasks_completed}
• Duration: ${duration}"
}

# Send error alert
telegram_error() {
    local error_msg="$1"
    local context="${2:-}"

    local message="Error: ${error_msg}"
    if [[ -n "$context" ]]; then
        message="${message}
Context: ${context}"
    fi

    telegram_notify "error" "$message"
}

# Interactive setup wizard
telegram_setup() {
    echo "=== Telegram Bot Setup ==="
    echo ""
    echo "1. Create a bot via @BotFather on Telegram"
    echo "2. Copy the bot token"
    echo ""
    read -p "Enter your bot token: " token

    if [[ -z "$token" ]]; then
        echo "Cancelled."
        return 1
    fi

    # Test token
    local response
    response=$(curl -s "https://api.telegram.org/bot${token}/getMe")
    if ! echo "$response" | jq -e '.ok' > /dev/null 2>&1; then
        echo "Invalid token. Please check and try again."
        return 1
    fi

    local bot_name
    bot_name=$(echo "$response" | jq -r '.result.username')
    echo "Connected to @${bot_name}"
    echo ""
    echo "3. Start a chat with your bot and send any message"
    echo "4. Then come back here and press Enter"
    read -p "Press Enter when ready..."

    # Get chat ID and user ID from recent messages
    response=$(curl -s "https://api.telegram.org/bot${token}/getUpdates")
    local chat_id
    chat_id=$(echo "$response" | jq -r '.result[-1].message.chat.id // empty')
    local user_id
    user_id=$(echo "$response" | jq -r '.result[-1].message.from.id // empty')
    local username
    username=$(echo "$response" | jq -r '.result[-1].message.from.username // empty')

    if [[ -z "$chat_id" ]]; then
        echo "No messages found. Please send a message to the bot first."
        return 1
    fi

    echo "Found chat ID: ${chat_id}"
    echo "Your user ID: ${user_id} (@${username})"
    echo ""
    echo "The bot will ONLY respond to messages from this chat/user."
    echo "To allow additional users, add their IDs to TELEGRAM_ALLOWED_USERS"
    echo ""
    echo "Add these to your .ralphrc or environment:"
    echo ""
    echo "TELEGRAM_ENABLED=true"
    echo "TELEGRAM_BOT_TOKEN=${token}"
    echo "TELEGRAM_CHAT_ID=${chat_id}"
    echo "# TELEGRAM_ALLOWED_USERS=${user_id}  # Add more user IDs comma-separated"
    echo ""

    read -p "Add to .ralphrc now? [Y/n] " add_now
    if [[ "$(echo "$add_now" | tr '[:upper:]' '[:lower:]')" != "n" ]]; then
        {
            echo ""
            echo "# Telegram integration"
            echo "TELEGRAM_ENABLED=true"
            echo "TELEGRAM_BOT_TOKEN=${token}"
            echo "TELEGRAM_CHAT_ID=${chat_id}"
            echo "# Only your chat is allowed by default. Uncomment to add more users:"
            echo "# TELEGRAM_ALLOWED_USERS=${user_id}"
        } >> .ralphrc
        echo "Added to .ralphrc"
    fi

    # Send test message
    TELEGRAM_BOT_TOKEN="$token"
    TELEGRAM_CHAT_ID="$chat_id"
    TELEGRAM_ENABLED="true"
    telegram_send "🤖 Ralph bot connected successfully!"
    echo "Test message sent!"

    return 0
}

# ============================================================================
# Remote Control Interface Implementation
# ============================================================================

# Alias for remote_control.sh interface compatibility
telegram_receive() {
    telegram_get_latest_message
}

# Register this adapter with remote_control
# This is called when the script is sourced
_telegram_register() {
    if declare -f rc_register_adapter > /dev/null 2>&1; then
        rc_register_adapter "telegram" "telegram_"

        # Also set up remote control config if telegram is enabled
        if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
            REMOTE_CONTROL_ENABLED="true"
            REMOTE_CONTROL_ADAPTER="telegram"
            REMOTE_CONTROL_POLL_INTERVAL="$TELEGRAM_POLL_INTERVAL"
            REMOTE_CONTROL_ASK_TIMEOUT="$TELEGRAM_ASK_TIMEOUT"
        fi
    fi
}

# ============================================================================
# Task Management Commands
# ============================================================================

# Handle /add commands for tasks
telegram_handle_add_command() {
    local message="$1"

    # Check if it's an add command
    if [[ ! "$message" =~ ^/add ]]; then
        return 1
    fi

    local priority=""
    local description=""

    # Parse command
    if [[ "$message" =~ ^/add-high[[:space:]]+(.*) ]] || [[ "$message" =~ ^/add-h[[:space:]]+(.*) ]]; then
        priority="H"
        description="${BASH_REMATCH[1]}"
    elif [[ "$message" =~ ^/add-med[[:space:]]+(.*) ]] || [[ "$message" =~ ^/add-m[[:space:]]+(.*) ]]; then
        priority="M"
        description="${BASH_REMATCH[1]}"
    elif [[ "$message" =~ ^/add-low[[:space:]]+(.*) ]] || [[ "$message" =~ ^/add-l[[:space:]]+(.*) ]]; then
        priority="L"
        description="${BASH_REMATCH[1]}"
    elif [[ "$message" =~ ^/add[[:space:]]+(.*) ]]; then
        # Generic /add - need to ask for priority
        description="${BASH_REMATCH[1]}"
        priority=""  # Will ask
    else
        return 1
    fi

    # If no description, error
    if [[ -z "$description" ]]; then
        telegram_send "❌ Error: Task description required

Usage:
/add-high <description>
/add-med <description>
/add-low <description>
or
/add <description> (will ask for priority)"
        return 1
    fi

    # Ask for priority if not specified
    if [[ -z "$priority" ]]; then
        telegram_poll > /dev/null 2>&1  # Clear pending
        telegram_send_buttons "Select priority for: ${description}" \
            "🔴 High:/high" \
            "🟡 Medium:/med" \
            "🔵 Low:/low"

        local response
        response=$(telegram_wait_for_callback 60)

        case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in
            /high|high|h) priority="H" ;;
            /med|medium|m) priority="M" ;;
            /low|low|l) priority="L" ;;
            timeout)
                telegram_send "⏱️ Timeout - defaulting to Medium priority"
                priority="M"
                ;;
            *)
                telegram_send "❓ Unknown response - defaulting to Medium priority"
                priority="M"
                ;;
        esac
    fi

    # Add the task using ralph-tasks
    local task_file
    if command -v ralph-tasks &> /dev/null; then
        task_file=$(ralph-tasks add "$description" -p "$priority" 2>&1 | tail -1)

        local pri_emoji
        case "$priority" in
            H) pri_emoji="🔴" ;;
            M) pri_emoji="🟡" ;;
            L) pri_emoji="🔵" ;;
        esac

        telegram_send "✅ Task added ${pri_emoji}

Priority: ${priority}
Description: ${description}

File: ${task_file}"
    else
        telegram_send "❌ Error: ralph-tasks command not found"
        return 1
    fi

    return 0
}

# Process incoming Telegram messages for commands
telegram_process_commands() {
    if [[ "$TELEGRAM_ENABLED" != "true" ]]; then
        return 0
    fi

    local message
    message=$(telegram_get_latest_message)

    if [[ -z "$message" || "$message" == "null" ]]; then
        return 0
    fi

    # Handle /add commands
    if telegram_handle_add_command "$message"; then
        return 0
    fi

    # Add more command handlers here in the future
    # telegram_handle_list_command "$message"
    # telegram_handle_status_command "$message"

    return 0
}

# Send persistent keyboard with task management buttons
telegram_send_task_menu() {
    if [[ "$TELEGRAM_ENABLED" != "true" ]]; then
        return 0
    fi

    # Reply keyboard (persistent buttons at bottom of chat)
    local keyboard='{
        "keyboard": [
            [{"text": "/add-high"}, {"text": "/add-med"}, {"text": "/add-low"}],
            [{"text": "/list"}, {"text": "/status"}, {"text": "/help"}]
        ],
        "resize_keyboard": true,
        "persistent": true
    }'

    local response
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${TELEGRAM_CHAT_ID}\",
            \"text\": \"📋 Task Management Menu\n\nQuick add commands:\n• /add-high - Add high priority task\n• /add-med - Add medium priority task\n• /add-low - Add low priority task\n\nOr use /add <description> to choose priority\",
            \"reply_markup\": ${keyboard}
        }")

    if ! echo "$response" | jq -e '.ok' > /dev/null 2>&1; then
        echo "[telegram] Failed to send task menu: $response" >&2
        return 1
    fi

    return 0
}

# Auto-register on source
_telegram_register
