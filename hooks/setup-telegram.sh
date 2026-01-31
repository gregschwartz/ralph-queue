#!/bin/bash
# setup-telegram.sh - Interactive Telegram bot setup for Ralph
set -euo pipefail

echo "=== Ralph Telegram Setup ==="
echo ""
echo "Step 1: Create a Telegram Bot"
echo "────────────────────────────"
echo "1. Open Telegram and search for @BotFather"
echo "2. Send: /newbot"
echo "3. Choose a name (e.g., 'Ralph Assistant')"
echo "4. Choose a username (e.g., 'my_ralph_bot')"
echo "5. Copy the token BotFather gives you"
echo ""
read -p "Paste your bot token: " TOKEN

if [[ -z "$TOKEN" ]]; then
    echo "Cancelled."
    exit 1
fi

# Validate token
RESPONSE=$(curl -s "https://api.telegram.org/bot${TOKEN}/getMe")
if ! echo "$RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
    echo "Invalid token. Check and try again."
    exit 1
fi

BOT_NAME=$(echo "$RESPONSE" | jq -r '.result.username')
echo "✓ Connected to @${BOT_NAME}"
echo ""

echo "Step 2: Get Your Chat ID"
echo "────────────────────────"
echo "1. Open Telegram and start a chat with @${BOT_NAME}"
echo "2. Send any message (e.g., 'hello')"
echo ""
read -p "Press Enter after sending a message..."

# Get chat ID from recent messages
RESPONSE=$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates")
CHAT_ID=$(echo "$RESPONSE" | jq -r '.result[-1].message.chat.id // empty')
USER_ID=$(echo "$RESPONSE" | jq -r '.result[-1].message.from.id // empty')
USERNAME=$(echo "$RESPONSE" | jq -r '.result[-1].message.from.username // "unknown"')

if [[ -z "$CHAT_ID" ]]; then
    echo "No messages found. Send a message to @${BOT_NAME} first."
    exit 1
fi

echo "✓ Found chat ID: ${CHAT_ID}"
echo "✓ Your user: @${USERNAME} (ID: ${USER_ID})"
echo ""

echo "Step 3: Save Configuration"
echo "──────────────────────────"
echo ""
echo "Where to save?"
echo "  1) ~/.ralphrc (global - all projects)"
echo "  2) .ralphrc (current directory only)"
echo ""
read -p "Choice [1]: " CHOICE
CHOICE="${CHOICE:-1}"

if [[ "$CHOICE" == "2" ]]; then
    TARGET=".ralphrc"
else
    TARGET="$HOME/.ralphrc"
fi

# Check if already configured
if grep -q "TELEGRAM_BOT_TOKEN" "$TARGET" 2>/dev/null; then
    echo ""
    echo "Warning: $TARGET already has Telegram config."
    read -p "Overwrite? [y/N] " OVERWRITE
    if [[ "$(echo "$OVERWRITE" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
        echo "Cancelled."
        exit 1
    fi
    # Remove old config (macOS compatible)
    grep -v "TELEGRAM_" "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
fi

# Append config
cat >> "$TARGET" <<EOF

# Telegram integration (added by setup-telegram.sh)
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN=${TOKEN}
TELEGRAM_CHAT_ID=${CHAT_ID}
EOF

echo "✓ Saved to $TARGET"
echo ""

# Send test message
echo "Sending test message..."
curl -s "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=🤖 Ralph connected! You'll receive permission requests here." > /dev/null

echo "✓ Test message sent!"
echo ""
echo "Done! Ralph will now ask for permissions via Telegram."
