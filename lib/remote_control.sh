#!/bin/bash
# remote_control.sh - Generic remote control interface for Ralph
#
# This defines the interface that adapters (Telegram, Slack, Web) must implement.
# Adapters register themselves and the command handler uses this abstraction.
#
# To implement an adapter:
#   1. Source this file
#   2. Implement the rc_* functions
#   3. Call rc_register_adapter "adapter_name"

# ============================================================================
# Configuration
# ============================================================================

REMOTE_CONTROL_ENABLED="${REMOTE_CONTROL_ENABLED:-false}"
REMOTE_CONTROL_ADAPTER="${REMOTE_CONTROL_ADAPTER:-}"  # telegram, slack, web, etc.
REMOTE_CONTROL_POLL_INTERVAL="${REMOTE_CONTROL_POLL_INTERVAL:-5}"
REMOTE_CONTROL_ASK_TIMEOUT="${REMOTE_CONTROL_ASK_TIMEOUT:-300}"

# Registered adapters (using dynamic variables for Bash 3.2 compatibility)
# Instead of associative array, we use: RC_ADAPTER_<name>=prefix

# ============================================================================
# Adapter Registration
# ============================================================================

# Register an adapter
# Usage: rc_register_adapter "telegram" "telegram_"
#   - name: adapter name (telegram, slack, web)
#   - prefix: function prefix for this adapter's implementations
rc_register_adapter() {
    local name="$1"
    local prefix="${2:-${name}_}"
    # Use eval for dynamic variable names (Bash 3.2 compatible)
    eval "RC_ADAPTER_${name}=\"${prefix}\""
    echo "[remote_control] Registered adapter: $name (prefix: $prefix)"
}

# Get current adapter's function prefix
_rc_prefix() {
    if [[ -z "$REMOTE_CONTROL_ADAPTER" ]]; then
        echo ""
        return 1
    fi
    # Use eval for dynamic variable lookup (Bash 3.2 compatible)
    local var_name="RC_ADAPTER_${REMOTE_CONTROL_ADAPTER}"
    eval "echo \"\${${var_name}:-}\""
}

# ============================================================================
# Interface Functions (delegates to active adapter)
# ============================================================================

# Initialize the remote control system
rc_init() {
    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ -z "$REMOTE_CONTROL_ADAPTER" ]]; then
        echo "[remote_control] Error: REMOTE_CONTROL_ADAPTER not set" >&2
        return 1
    fi

    local prefix
    prefix=$(_rc_prefix)
    if [[ -z "$prefix" ]]; then
        echo "[remote_control] Error: Unknown adapter: $REMOTE_CONTROL_ADAPTER" >&2
        return 1
    fi

    # Call adapter's init function
    local init_fn="${prefix}init"
    if declare -f "$init_fn" > /dev/null; then
        "$init_fn"
    else
        echo "[remote_control] Warning: ${init_fn} not implemented" >&2
    fi
}

# Send a message
# Usage: rc_send "message" [format]
rc_send() {
    local message="$1"
    local format="${2:-text}"  # text, markdown, html

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "$message"
        return 0
    fi

    local prefix
    prefix=$(_rc_prefix) || return 0

    local send_fn="${prefix}send"
    if declare -f "$send_fn" > /dev/null; then
        "$send_fn" "$message" "$format"
    else
        echo "$message"
    fi
}

# Send a notification with type
# Usage: rc_notify "type" "message"
#   types: start, complete, error, warning, question, blocked, progress, info
rc_notify() {
    local type="$1"
    local message="$2"

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "[$type] $message"
        return 0
    fi

    local prefix
    prefix=$(_rc_prefix) || { echo "[$type] $message"; return 0; }

    local notify_fn="${prefix}notify"
    if declare -f "$notify_fn" > /dev/null; then
        "$notify_fn" "$type" "$message"
    else
        rc_send "[$type] $message"
    fi
}

# Receive the latest message/command
# Returns: message text or empty string
rc_receive() {
    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        return 1
    fi

    local prefix
    prefix=$(_rc_prefix) || return 1

    local receive_fn="${prefix}receive"
    if declare -f "$receive_fn" > /dev/null; then
        "$receive_fn"
    else
        return 1
    fi
}

# Ask a question and wait for response (blocking)
# Usage: rc_ask "question" [timeout_seconds]
# Returns: response text or "TIMEOUT"
rc_ask() {
    local question="$1"
    local timeout="${2:-$REMOTE_CONTROL_ASK_TIMEOUT}"

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "SKIPPED"
        return 0
    fi

    local prefix
    prefix=$(_rc_prefix) || { echo "SKIPPED"; return 0; }

    local ask_fn="${prefix}ask"
    if declare -f "$ask_fn" > /dev/null; then
        "$ask_fn" "$question" "$timeout"
    else
        # Default implementation using send/receive
        rc_send "❓ $question (reply within ${timeout}s)"

        local start_time
        start_time=$(date +%s)

        while true; do
            local response
            response=$(rc_receive)

            if [[ -n "$response" ]]; then
                echo "$response"
                return 0
            fi

            local elapsed=$(( $(date +%s) - start_time ))
            if (( elapsed >= timeout )); then
                echo "TIMEOUT"
                return 1
            fi

            sleep "$REMOTE_CONTROL_POLL_INTERVAL"
        done
    fi
}

# Ask yes/no question with optional buttons
# Usage: rc_ask_yes_no "question" [default] [timeout]
# Returns: "yes" or "no"
rc_ask_yes_no() {
    local question="$1"
    local default="${2:-no}"
    local timeout="${3:-60}"

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "$default"
        return 0
    fi

    local prefix
    prefix=$(_rc_prefix) || { echo "$default"; return 0; }

    local ask_yn_fn="${prefix}ask_yes_no"
    if declare -f "$ask_yn_fn" > /dev/null; then
        "$ask_yn_fn" "$question" "$default" "$timeout"
    else
        # Default: use rc_ask and parse response
        local response
        response=$(rc_ask "$question [y/n]" "$timeout")

        case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in
            y|yes|yep|sure|ok|1|true) echo "yes"; return 0 ;;
            n|no|nope|nah|0|false) echo "no"; return 1 ;;
            timeout|skipped) echo "$default"; [[ "$default" == "yes" ]] && return 0 || return 1 ;;
            *) echo "$default"; [[ "$default" == "yes" ]] && return 0 || return 1 ;;
        esac
    fi
}

# Ask permission (for tool approvals, etc.)
# Usage: rc_ask_permission "action" [details] [timeout]
# Returns: "allow", "deny", or "allow_all"
rc_ask_permission() {
    local action="$1"
    local details="${2:-}"
    local timeout="${3:-120}"

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "allow"  # Auto-allow when remote control disabled
        return 0
    fi

    local prefix
    prefix=$(_rc_prefix) || { echo "allow"; return 0; }

    local ask_perm_fn="${prefix}ask_permission"
    if declare -f "$ask_perm_fn" > /dev/null; then
        "$ask_perm_fn" "$action" "$details" "$timeout"
    else
        # Default implementation
        local message="🔐 Permission Request: ${action}"
        [[ -n "$details" ]] && message+="\n${details}"

        local response
        response=$(rc_ask "$message\n\nAllow? [y/n/all]" "$timeout")

        case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in
            y|yes|allow) echo "allow"; return 0 ;;
            all|allow_all|always) echo "allow_all"; return 0 ;;
            *) echo "deny"; return 1 ;;
        esac
    fi
}

# Send with buttons/options
# Usage: rc_send_buttons "message" "label1:data1" "label2:data2" ...
# Returns: message ID (adapter-specific)
rc_send_buttons() {
    local message="$1"
    shift
    local buttons=("$@")

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "$message"
        echo "Options: ${buttons[*]}"
        return 0
    fi

    local prefix
    prefix=$(_rc_prefix) || { echo "$message"; return 0; }

    local buttons_fn="${prefix}send_buttons"
    if declare -f "$buttons_fn" > /dev/null; then
        "$buttons_fn" "$message" "${buttons[@]}"
    else
        # Fallback: just send message with options listed
        local opts=""
        for btn in "${buttons[@]}"; do
            opts+="  • ${btn%%:*}\n"
        done
        rc_send "${message}\n\nOptions:\n${opts}"
    fi
}

# Wait for button/callback response
# Usage: rc_wait_for_callback [timeout]
# Returns: callback data or "TIMEOUT"
rc_wait_for_callback() {
    local timeout="${1:-$REMOTE_CONTROL_ASK_TIMEOUT}"

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "SKIPPED"
        return 0
    fi

    local prefix
    prefix=$(_rc_prefix) || { echo "SKIPPED"; return 0; }

    local callback_fn="${prefix}wait_for_callback"
    if declare -f "$callback_fn" > /dev/null; then
        "$callback_fn" "$timeout"
    else
        # Default: fall back to receive
        local start_time
        start_time=$(date +%s)

        while true; do
            local response
            response=$(rc_receive)

            if [[ -n "$response" ]]; then
                echo "$response"
                return 0
            fi

            local elapsed=$(( $(date +%s) - start_time ))
            if (( elapsed >= timeout )); then
                echo "TIMEOUT"
                return 1
            fi

            sleep "$REMOTE_CONTROL_POLL_INTERVAL"
        done
    fi
}

# Check if user is authorized (adapter handles user management)
# Usage: rc_is_authorized "user_id"
rc_is_authorized() {
    local user_id="$1"

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        return 0  # Allow all when disabled
    fi

    local prefix
    prefix=$(_rc_prefix) || return 0

    local auth_fn="${prefix}is_authorized"
    if declare -f "$auth_fn" > /dev/null; then
        "$auth_fn" "$user_id"
    else
        return 0  # Default: allow
    fi
}

# ============================================================================
# Command Polling Loop
# ============================================================================

# Start polling for commands
# Usage: rc_poll_loop "command_handler_function"
rc_poll_loop() {
    local handler="$1"
    local interval="${REMOTE_CONTROL_POLL_INTERVAL:-5}"

    if [[ "$REMOTE_CONTROL_ENABLED" != "true" ]]; then
        echo "[remote_control] Remote control disabled, not starting poll loop"
        return 0
    fi

    echo "[remote_control] Starting command poll loop (${interval}s interval)..."

    while true; do
        local message
        message=$(rc_receive)

        if [[ -n "$message" ]]; then
            if declare -f "$handler" > /dev/null; then
                "$handler" "$message"
            else
                echo "[remote_control] Warning: Handler '$handler' not found" >&2
            fi
        fi

        sleep "$interval"
    done
}
