#!/bin/bash
# install-ralph-task.sh - Install ralph-tasks CLI and set up aliases
#
# Usage: ./install-ralph-task.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"
SHELL_RC=""

# Detect shell
detect_shell() {
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        SHELL_RC="$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == *"bash"* ]]; then
        SHELL_RC="$HOME/.bashrc"
    else
        SHELL_RC="$HOME/.profile"
    fi
}

# Install ralph-tasks to PATH
install_binary() {
    mkdir -p "$INSTALL_DIR"

    # Symlink ralph-tasks (primary command)
    ln -sf "${SCRIPT_DIR}/ralph-tasks" "${INSTALL_DIR}/ralph-tasks"
    echo "✓ Installed: ${INSTALL_DIR}/ralph-tasks"

    # Symlink ralph-task (singular, for typos/muscle memory)
    ln -sf "${SCRIPT_DIR}/ralph-tasks" "${INSTALL_DIR}/ralph-task"
    echo "✓ Installed: ${INSTALL_DIR}/ralph-task (alias)"

    # Check if INSTALL_DIR is in PATH
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        echo ""
        echo "⚠ ${INSTALL_DIR} is not in your PATH"
        echo "  Add this to your ${SHELL_RC}:"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi
}

# Add aliases to shell rc
install_aliases() {
    local aliases='
# Ralph task management aliases
alias rt="ralph-tasks"
alias rta="ralph-tasks add"
alias rtli="ralph-tasks list"
alias rtn="ralph-tasks next"
alias rtd="ralph-tasks done"
alias rtq="ralph-tasks queue"
alias rts="ralph-tasks start"

# Quick add by priority
alias rth="ralph-tasks add h"
alias rtm="ralph-tasks add m"
alias rtl="ralph-tasks add l"'

    if grep -q "Ralph task management aliases" "$SHELL_RC" 2>/dev/null; then
        echo "✓ Aliases already in ${SHELL_RC}"
        return
    fi

    echo "$aliases" >> "$SHELL_RC"
    echo "✓ Added aliases to ${SHELL_RC}"
    echo ""
    echo "  Basic:"
    echo "    rt    = ralph-tasks"
    echo "    rta   = ralph-tasks add"
    echo "    rtli  = ralph-tasks list"
    echo "    rtn   = ralph-tasks next"
    echo "    rtd   = ralph-tasks done"
    echo "    rtq   = ralph-tasks queue"
    echo "    rts   = ralph-tasks start"
    echo ""
    echo "  Quick add by priority:"
    echo "    rth   = ralph-tasks add h  (high)"
    echo "    rtm   = ralph-tasks add m  (medium)"
    echo "    rtl   = ralph-tasks add l  (low)"
}

# Main
main() {
    echo "Installing ralph-tasks..."
    echo ""

    detect_shell
    install_binary
    echo ""

    read -p "Add shell aliases (rt, rta, rtl, etc)? [Y/n] " add_aliases
    add_aliases=$(echo "$add_aliases" | tr '[:upper:]' '[:lower:]')
    if [[ "$add_aliases" != "n" ]]; then
        install_aliases
    fi

    echo ""
    echo "Done! Run 'source ${SHELL_RC}' or open a new terminal."
    echo ""
    echo "Quick start:"
    echo "  ralph-tasks add h \"fix critical bug\""
    echo "  ralph-tasks list"
    echo "  ralph-tasks start"
    echo ""
    echo "Note: Both 'ralph-task' and 'ralph-tasks' work (installed as aliases)"
}

main "$@"
