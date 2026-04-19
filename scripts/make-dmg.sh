#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="SmoothTox"
EXECUTABLE_NAME="Tox"
BUNDLE_ID="com.smoothtox.app"
VERSION="1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_STAGING_DIR="$DIST_DIR/dmg"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"

echo "[1/6] Building release binary..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

if [[ ! -f "$BIN_DIR/$EXECUTABLE_NAME" ]]; then
  echo "Release binary not found at: $BIN_DIR/$EXECUTABLE_NAME" >&2
  exit 1
fi

echo "[2/6] Preparing app bundle..."
rm -rf "$APP_DIR" "$DMG_STAGING_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DMG_STAGING_DIR"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

BUNDLE_RESOURCE=""
if [[ -d "$BIN_DIR/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle" ]]; then
  BUNDLE_RESOURCE="$BIN_DIR/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"
else
  FOUND_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -type d -name "*_${EXECUTABLE_NAME}.bundle" | head -n 1 || true)"
  if [[ -n "$FOUND_BUNDLE" ]]; then
    BUNDLE_RESOURCE="$FOUND_BUNDLE"
  fi
fi

if [[ -n "$BUNDLE_RESOURCE" ]]; then
  cp -R "$BUNDLE_RESOURCE" "$APP_DIR/Contents/Resources/"
fi

echo "[3/6] Writing Info.plist..."
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>${EXECUTABLE_NAME}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "[4/6] Signing app (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR"

echo "[5/6] Creating DMG staging folder..."
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

echo "[6/6] Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Done: $DMG_PATH"
