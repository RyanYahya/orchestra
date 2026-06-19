#!/bin/bash
# notify.sh — Send a macOS notification and terminal alert
# Usage: bash .orchestra/scripts/orchestra/notify.sh "Your message here"

MESSAGE="${1:-Phase Runner needs attention}"
TITLE="Orchestra"

# Terminal bell + message
printf "\a"
echo ">>> NOTIFICATION: $MESSAGE"

# macOS notification via osascript
if command -v osascript &> /dev/null; then
  osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\"" 2>/dev/null || true
fi
