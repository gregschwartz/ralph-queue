#!/bin/bash
# Fix for log_task_attempt function - replace awk with simple append

# Create the new function
cat > /tmp/new_log_func.txt << 'FUNC'
log_task_attempt() {
    local task_file="$1"
    local attempt_num="$2"
    local error_msg="$3"
    local why="${4:-}"

    if [[ ! -f "$task_file" ]]; then
        return 1
    fi

    # Ensure Attempts section exists
    if ! grep -q "^## Attempts" "$task_file"; then
        echo "" >> "$task_file"
        echo "## Attempts" >> "$task_file"
    fi

    # Log this attempt
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Append at end of file (simpler and maintains chronological order)
    {
        echo ""
        echo "- **Attempt ${attempt_num}**: ${timestamp}"
        echo "  - Error: ${error_msg}"
        if [[ -n "$why" ]]; then
            echo "  - Why: ${why}"
        fi
    } >> "$task_file"
}
FUNC

echo "New function written to /tmp/new_log_func.txt"
