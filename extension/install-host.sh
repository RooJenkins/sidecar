#!/bin/bash
set -euo pipefail

# Sidecar Native Messaging Host Installer
# Registers the native messaging host with Chrome/Chromium browsers

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_SCRIPT="$SCRIPT_DIR/host/sidecar-host.sh"
HOST_NAME="com.sidecar.menu"

# Make host script executable
chmod +x "$HOST_SCRIPT"

# Detect Chrome native messaging directories
CHROME_DIRS=()

if [[ "$(uname)" == "Darwin" ]]; then
  CHROME_DIRS+=(
    "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
    "$HOME/Library/Application Support/Arc/User Data/NativeMessagingHosts"
  )
else
  CHROME_DIRS+=(
    "$HOME/.config/google-chrome/NativeMessagingHosts"
    "$HOME/.config/chromium/NativeMessagingHosts"
    "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    "$HOME/.config/microsoft-edge/NativeMessagingHosts"
  )
fi

INSTALLED=0

for DIR in "${CHROME_DIRS[@]}"; do
  # Only install if the parent browser directory exists
  PARENT_DIR="$(dirname "$DIR")"
  if [[ -d "$PARENT_DIR" ]]; then
    mkdir -p "$DIR"

    cat > "$DIR/$HOST_NAME.json" <<MANIFEST
{
  "name": "$HOST_NAME",
  "description": "Sidecar context injection for AI chat platforms",
  "path": "$HOST_SCRIPT",
  "type": "stdio",
  "allowed_origins": []
}
MANIFEST

    echo "Installed to: $DIR/$HOST_NAME.json"
    INSTALLED=$((INSTALLED + 1))
  fi
done

if [[ $INSTALLED -eq 0 ]]; then
  echo "No Chrome-based browsers found."
  echo ""
  echo "To install manually, create this file:"
  echo "  ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/$HOST_NAME.json"
  echo ""
  echo "With contents:"
  echo '  {'
  echo "    \"name\": \"$HOST_NAME\","
  echo '    "description": "Sidecar context injection for AI chat platforms",'
  echo "    \"path\": \"$HOST_SCRIPT\","
  echo '    "type": "stdio",'
  echo '    "allowed_origins": []'
  echo '  }'
  exit 1
fi

echo ""
echo "Installed native messaging host for $INSTALLED browser(s)."
echo ""
echo "Next steps:"
echo "  1. Load the extension in Chrome: chrome://extensions -> Load unpacked -> select $SCRIPT_DIR"
echo "  2. Copy the extension ID from the extensions page"
echo "  3. Run: $0 --set-extension-id <extension-id>"
echo "     (or manually add it to allowed_origins in the manifest)"
echo ""

# Handle --set-extension-id flag
if [[ "${1:-}" == "--set-extension-id" ]] && [[ -n "${2:-}" ]]; then
  EXT_ID="$2"
  ORIGIN="chrome-extension://$EXT_ID/"

  for DIR in "${CHROME_DIRS[@]}"; do
    MANIFEST_FILE="$DIR/$HOST_NAME.json"
    if [[ -f "$MANIFEST_FILE" ]]; then
      # Use node to update the JSON properly
      node -e "
        const fs = require('fs');
        const m = JSON.parse(fs.readFileSync('$MANIFEST_FILE', 'utf-8'));
        m.allowed_origins = ['$ORIGIN'];
        fs.writeFileSync('$MANIFEST_FILE', JSON.stringify(m, null, 2) + '\n');
      "
      echo "Updated $MANIFEST_FILE with extension ID: $EXT_ID"
    fi
  done
fi
