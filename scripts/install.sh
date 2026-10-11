#!/usr/bin/env bash
# Build, package, and install agent-usage CLI + Agent Usage Bar.app.

set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

CLI_NAME="agent-usage"
APP_NAME="Agent Usage Bar"
APP_BUNDLE="${APP_NAME}.app"

# Pick the first writable bin directory on PATH.
pick_bin_dir() {
  for dir in "/opt/homebrew/bin" "/usr/local/bin" "$HOME/.local/bin" "$HOME/bin"; do
    if [[ -d "$dir" && -w "$dir" ]]; then
      echo "$dir"
      return 0
    fi
  done
  mkdir -p "$HOME/.local/bin"
  echo "$HOME/.local/bin"
}

BIN_DIR="$(pick_bin_dir)"
CLI_DEST="$BIN_DIR/$CLI_NAME"
APP_DEST="/Applications/$APP_BUNDLE"

echo "==> Building release..."
swift build -c release

echo "==> Packaging menu bar .app bundle..."
./scripts/package-app.sh

echo "==> Installing CLI to $CLI_DEST ..."
cp ".build/release/$CLI_NAME" "$CLI_DEST"
chmod +x "$CLI_DEST"

source "$REPO_ROOT/scripts/sign-identity.sh"
echo "==> Signing CLI with $SIGN_IDENTITY ..."
codesign --force --sign "$SIGN_IDENTITY" "$CLI_DEST"

echo "==> Installing menu bar app to $APP_DEST ..."
rm -rf "$APP_DEST"
cp -R ".build/release/$APP_BUNDLE" "$APP_DEST"

echo "==> Registering as Login Item (auto-start on boot) ..."
osascript <<OSA >/dev/null 2>&1 || true
tell application "System Events"
  if login item "${APP_NAME}" exists then
    delete login item "${APP_NAME}"
  end if
  make login item at end with properties {path:"${APP_DEST}", hidden:false}
end tell
OSA

echo "==> Launching app ..."
open "$APP_DEST"

echo ""
echo "Install complete."
echo "  CLI: $CLI_DEST"
echo "  App: $APP_DEST (registered as Login Item, launched)"
echo ""
case ":$PATH:" in
  *":$BIN_DIR:"*) echo "Run '$CLI_NAME' to test the CLI." ;;
  *)
    echo "WARNING: $BIN_DIR is not on your PATH."
    echo "  Add it, for example: echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
    echo "  Or run the CLI by its full path: $CLI_DEST"
    ;;
esac
