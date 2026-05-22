#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WPWriter"
BUNDLE_ID="com.wpwriter.app"
MIN_MACOS="13.0"

echo "Building $APP_NAME..."
swift build -c release 2>&1

BINARY=".build/release/$APP_NAME"
APP_DIR="$APP_NAME.app/Contents"

rm -rf "$APP_NAME.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp "$BINARY" "$APP_DIR/MacOS/$APP_NAME"

# Resources (skeleton — completed in Task 18)

cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "Done: $APP_NAME.app"
