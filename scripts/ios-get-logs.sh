#!/bin/bash
# Pull app.log from iOS device
# Requires: brew install libimobiledevice ideviceinstaller

BUNDLE_ID="com.viberunner.app.local"
APP_LOG="app.log"
OUTPUT="/tmp/viberunner-app.log"

echo "📱 Pulling logs from device..."

# Use ideviceinstaller to get app data or use devicectl
if command -v ideviceinstaller &> /dev/null; then
    # Try to pull the file using AFC (Apple File Conduit)
    # This requires the app to have file sharing enabled
    echo "Attempting to pull logs via AFC..."
fi

# Alternative: Use devicectl to copy files
xcrun devicectl device copy from --device "$(xcrun devicectl list devices 2>/dev/null | grep -oE '[A-F0-9-]{36}' | head -1)" \
    --source "/private/var/mobile/Containers/Data/Application/*/Documents/app.log" \
    --destination "$OUTPUT" 2>/dev/null

if [ -f "$OUTPUT" ]; then
    echo "✅ Logs saved to: $OUTPUT"
    echo "----------------------------------------"
    cat "$OUTPUT"
else
    echo "❌ Could not pull logs. Try using macOS Console.app instead:"
    echo "   1. Open Console.app"
    echo "   2. Select your iPhone from the sidebar"
    echo "   3. Filter by 'viberunner'"
fi
