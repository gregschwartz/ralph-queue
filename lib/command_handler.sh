#!/bin/bash
# command_handler.sh - Command parser and router for Ralph
#
# Parses incoming commands from any remote source and routes to ralph-task.
# This is remote-agnostic - it doesn't know if commands come from Telegram, Slack, or Web.
#
# Requires: remote_control.sh to be sourced first

# ============================================================================
# Configuration
# ============================================================================

COMMAND_PREFIX="${COMMAND_PREFIX:-/}"  # Command prefix (/ for Telegram/Slack style)

# Find ralph-task
_find_ralph_task() {
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")/.."

    if [[ -x "${script_dir}/ralph-task" ]]; then
        echo "${script_dir}/ralph-task"
    elif command -v ralph-task &> /dev/null; then
        echo "ralph-task"
    else
        echo ""
    fi
}

RALPH_TASK_CMD="$(_find_ralph_task)"

# ============================================================================
# Command Parsing
# ============================================================================

# Check if a message is a command
is_command() {
    local message="$1"
    [[ "$message" == "${COMMAND_PREFIX}"* ]]
}

# Parse command from message
# Returns: command name (without prefix)
parse_command() {
    local message="$1"
    echo "$message" | awk '{print $1}' | sed "s/^${COMMAND_PREFIX}//" | tr '[:upper:]' '[:lower:]'
}

# Parse arguments from message
# Returns: everything after the command
parse_args() {
    local message="$1"
    echo "$message" | cut -d' ' -f2- -s
}

# ============================================================================
# Command Handlers
# ============================================================================

# Handle: /task [priority] <description>
cmd_task() {
    local args="$1"

    if [[ -z "$args" ]]; then
        rc_send "Usage: ${COMMAND_PREFIX}task [h|m|l] <description>

Examples:
${COMMAND_PREFIX}task fix the login bug
${COMMAND_PREFIX}task h critical security fix
${COMMAND_PREFIX}task l update documentation"
        return
    fi

    # Check for priority prefix
    local priority="M"
    local description="$args"
    local first_word
    first_word=$(echo "$args" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

    case "$first_word" in
        h|high)
            priority="H"
            description=$(echo "$args" | cut -d' ' -f2-)
            ;;
        m|med|medium)
            priority="M"
            description=$(echo "$args" | cut -d' ' -f2-)
            ;;
        l|low)
            priority="L"
            description=$(echo "$args" | cut -d' ' -f2-)
            ;;
    esac

    if [[ -z "$description" ]]; then
        rc_send "Error: Task description required"
        return
    fi

    if [[ -z "$RALPH_TASK_CMD" ]]; then
        rc_send "Error: ralph-task not found"
        return
    fi

    local result
    result=$("$RALPH_TASK_CMD" add "$description" -p "$priority" 2>&1)

    rc_notify "complete" "Task added [${priority}]: ${description}

${result}"
}

# Handle: /tasks
cmd_tasks() {
    local args="$1"

    if [[ -z "$RALPH_TASK_CMD" ]]; then
        rc_send "Error: ralph-task not found"
        return
    fi

    local result
    result=$("$RALPH_TASK_CMD" list 2>&1)

    if [[ -z "$result" ]]; then
        rc_send "No pending tasks"
    else
        # Truncate if too long (most platforms have limits)
        if [[ ${#result} -gt 3500 ]]; then
            result="${result:0:3500}

... (truncated)"
        fi

        rc_send "Tasks:

${result}"
    fi
}

# Handle: /next
cmd_next() {
    local args="$1"

    if [[ -z "$RALPH_TASK_CMD" ]]; then
        rc_send "Error: ralph-task not found"
        return
    fi

    local result
    result=$("$RALPH_TASK_CMD" next 2>&1)

    if [[ -z "$result" || "$result" == *"No pending"* ]]; then
        rc_send "No pending tasks"
    else
        if [[ ${#result} -gt 3500 ]]; then
            result="${result:0:3500}

... (truncated)"
        fi

        rc_send "Next task:

${result}"
    fi
}

# Handle: /done [task-id]
cmd_done() {
    local task_id="$1"

    if [[ -z "$RALPH_TASK_CMD" ]]; then
        rc_send "Error: ralph-task not found"
        return
    fi

    local result
    if [[ -n "$task_id" ]]; then
        result=$("$RALPH_TASK_CMD" done "$task_id" 2>&1)
    else
        result=$("$RALPH_TASK_CMD" done 2>&1)
    fi

    if [[ "$result" == *"Done:"* ]]; then
        rc_notify "complete" "$result"
    else
        rc_notify "error" "$result"
    fi
}

# Handle: /skip
cmd_skip() {
    if [[ -z "$RALPH_TASK_CMD" ]]; then
        rc_send "Error: ralph-task not found"
        return
    fi

    local result
    result=$("$RALPH_TASK_CMD" skip 2>&1)
    rc_send "$result"
}

# Handle: /queue [load]
cmd_queue() {
    local args="$1"

    if [[ -z "$RALPH_TASK_CMD" ]]; then
        rc_send "Error: ralph-task not found"
        return
    fi

    local load_flag=""
    [[ "$args" == *"load"* ]] && load_flag="--load"

    local result
    result=$("$RALPH_TASK_CMD" queue $load_flag 2>&1)

    if [[ -n "$load_flag" ]]; then
        rc_notify "progress" "$result"
    else
        if [[ ${#result} -gt 3500 ]]; then
            result="${result:0:3500}

... (truncated)"
        fi
        rc_send "Queue:

${result}"
    fi
}

# Handle: /status
cmd_status() {
    local ralph_status="Unknown"
    local current_task="None"
    local task_count=0

    if [[ -f "${RALPH_DIR:-.ralph}/status.json" ]]; then
        ralph_status=$(jq -r '.status // "Unknown"' "${RALPH_DIR:-.ralph}/status.json" 2>/dev/null || echo "Unknown")
    fi

    if [[ -f "${RALPH_DIR:-.ralph}/.current_task" ]]; then
        local current_file
        current_file=$(cat "${RALPH_DIR:-.ralph}/.current_task")
        if [[ -f "$current_file" ]]; then
            current_task=$(grep -m1 '^# ' "$current_file" 2>/dev/null | sed 's/^# //' || basename "$current_file" .md)
        fi
    fi

    if [[ -n "$RALPH_TASK_CMD" ]]; then
        task_count=$("$RALPH_TASK_CMD" count 2>/dev/null || echo "?")
    fi

    rc_send "Ralph Status

Status: ${ralph_status}
Current: ${current_task}
Pending: ${task_count} tasks

Commands: ${COMMAND_PREFIX}help"
}

# Handle: /help
cmd_help() {
    rc_send "Ralph Commands

TASKS:
${COMMAND_PREFIX}task <text>     Add task (medium priority)
${COMMAND_PREFIX}task h <text>   Add high priority
${COMMAND_PREFIX}task l <text>   Add low priority

QUEUE:
${COMMAND_PREFIX}tasks           List pending
${COMMAND_PREFIX}next            Show next task
${COMMAND_PREFIX}done [id]       Mark done
${COMMAND_PREFIX}skip            Skip current
${COMMAND_PREFIX}queue           Show queue

OTHER:
${COMMAND_PREFIX}status          Ralph status
${COMMAND_PREFIX}help            This help"
}

# ============================================================================
# Main Handler
# ============================================================================

# Handle an incoming message
# Usage: handle_command "message" [from_user]
handle_command() {
    local message="$1"
    local from_user="${2:-}"

    # Check if it's a command
    if ! is_command "$message"; then
        return 1  # Not a command
    fi

    local cmd
    cmd=$(parse_command "$message")
    local args
    args=$(parse_args "$message")

    case "$cmd" in
        task|t|add)
            cmd_task "$args"
            ;;
        tasks|list|ls)
            cmd_tasks "$args"
            ;;
        next|n)
            cmd_next "$args"
            ;;
        done|d|complete)
            cmd_done "$args"
            ;;
        skip)
            cmd_skip
            ;;
        queue|q)
            cmd_queue "$args"
            ;;
        status)
            cmd_status
            ;;
        help|start|h)
            cmd_help
            ;;
        *)
            rc_send "Unknown command: ${COMMAND_PREFIX}${cmd}
Use ${COMMAND_PREFIX}help for available commands"
            ;;
    esac

    return 0
}

# Start the command handling loop
# Usage: start_command_loop
start_command_loop() {
    rc_poll_loop "handle_command"
}
