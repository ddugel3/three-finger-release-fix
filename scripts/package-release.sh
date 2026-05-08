#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/3FDragUnstuck.app"
DIST_DIR="$ROOT_DIR/dist"
INFO_PLIST="$ROOT_DIR/3FDragUnstuck/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO_PLIST")"
ZIP_NAME="3FDragUnstuck-v${VERSION}-macos-arm64.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

"$ROOT_DIR/3FDragUnstuck/build.sh" >/dev/null

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "$ZIP_PATH"
cat "$ZIP_PATH.sha256"
