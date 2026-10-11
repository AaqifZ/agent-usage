#!/usr/bin/env bash
# Clean removal of the agent-usage CLI and Agent Usage Bar.app.

set -euo pipefail
IFS=$'\n\t'

CLI_NAME="agent-usage"
APP_NAME="Agent Usage Bar"
BIN_NAME="AgentUsageBar"
APP_DEST="/Applications/${APP_NAME}.app"

# Stop the running menu bar app.
if pgrep -x "$BIN_NAME" >/dev/null; then
  echo "==> Terminating $BIN_NAME..."
  pkill -x "$BIN_NAME" || true
  sleep 1
fi

# Remove the Login Item registration.
echo "==> Removing Login Item registration (if any) ..."
osascript <<OSA >/dev/null 2>&1 || true
tell application "System Events"
  if login item "${APP_NAME}" exists then
    delete login item "${APP_NAME}"
  end if
end tell
OSA

# Remove the CLI from any bin dir the installer may have used.
for dir in "/opt/homebrew/bin" "/usr/local/bin" "$HOME/.local/bin" "$HOME/bin"; do
  if [[ -f "$dir/$CLI_NAME" ]]; then
    echo "==> Removing $dir/$CLI_NAME"
    rm -f "$dir/$CLI_NAME"
  fi
done

if [[ -d "$APP_DEST" ]]; then
  echo "==> Removing $APP_DEST"
  rm -rf "$APP_DEST"
fi

# One-time migration: early builds used the bundle ID
# ai.aaqifz.sovereign-agent-usage-bar. Remove any app bundle that still
# carries it, and its Login Item. Matches the exact ID only.
OLD_BUNDLE_ID="ai.aaqifz.sovereign-agent-usage-bar"
for app in /Applications/*.app "$HOME"/Applications/*.app; do
  [[ -f "$app/Contents/Info.plist" ]] || continue
  id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$id" == "$OLD_BUNDLE_ID" ]]; then
    name="$(basename "$app" .app)"
    echo "==> Removing $app (old bundle ID)"
    osascript <<OSA >/dev/null 2>&1 || true
tell application "System Events"
  if login item "${name}" exists then
    delete login item "${name}"
  end if
end tell
OSA
    rm -rf "$app"
  fi
done

# Remove agent-usage's own Keychain item (set by --set-claude-token).
if security delete-generic-password -s "agent-usage-claude-token" >/dev/null 2>&1; then
  echo "==> Removed Keychain item agent-usage-claude-token"
fi

echo "Uninstall complete."
echo "Note: this tool stores no config, caches, or preferences."
echo "Nothing further to clean."
