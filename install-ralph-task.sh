#!/bin/bash
# install-ralph-task.sh - Install ralph-task CLI and set up aliases
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

# Install ralph-task to PATH
install_binary() {
    mkdir -p "$INSTALL_DIR"

    # Symlink ralph-task
    ln -sf "${SCRIPT_DIR}/ralph-task" "${INSTALL_DIR}/ralph-task"
    echo "✓ Installed: ${INSTALL_DIR}/ralph-task"

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
alias rt="ralph-task"
alias rta="ralph-task add"
alias rtl="ralph-task list"
alias rtn="ralph-task next"
alias rtd="ralph-task done"
alias rtq="ralph-task queue"'

    if grep -q "ralph-task" "$SHELL_RC" 2>/dev/null; then
        echo "✓ Aliases already in ${SHELL_RC}"
        return
    fi

    echo "$aliases" >> "$SHELL_RC"
    echo "✓ Added aliases to ${SHELL_RC}"
    echo ""
    echo "  rt   = ralph-task"
    echo "  rta  = ralph-task add"
    echo "  rtl  = ralph-task list"
    echo "  rtn  = ralph-task next"
    echo "  rtd  = ralph-task done"
    echo "  rtq  = ralph-task queue"
}

# Main
main() {
    echo "Installing ralph-task..."
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
    echo "  ralph-task add \"my first task\" -p h"
    echo "  ralph-task list"
    echo "  ralph-task queue --load"
}

main "$@"
