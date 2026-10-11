#!/usr/bin/env bash
# Wrap the menu bar executable into a macOS .app bundle with Info.plist
# and sign it (see sign-identity.sh). Pure bash, no Xcode required.

set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR=".build/release"
APP_NAME="Agent Usage Bar.app"
APP_PATH="$BUILD_DIR/$APP_NAME"
BIN_NAME="AgentUsageBar"

if [[ ! -f "$BUILD_DIR/$BIN_NAME" ]]; then
  echo "error: $BUILD_DIR/$BIN_NAME not found. Run 'swift build -c release' first."
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILD_DIR/$BIN_NAME" "$APP_PATH/Contents/MacOS/$BIN_NAME"
cp "Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

source "$REPO_ROOT/scripts/sign-identity.sh"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "Built: $APP_PATH"
echo "Signature:"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Authority|Identifier"
