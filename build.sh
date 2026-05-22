#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WPWriter"
BUNDLE_ID="com.wpwriter.app"
MIN_MACOS="13.0"

echo "▶ Building $APP_NAME..."
swift build -c release 2>&1

BINARY=".build/release/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"
APP_DIR="$APP_BUNDLE/Contents"
RESOURCES_DIR="$APP_DIR/Resources"

echo "▶ Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$RESOURCES_DIR"

# Binary
cp "$BINARY" "$APP_DIR/MacOS/$APP_NAME"
chmod +x "$APP_DIR/MacOS/$APP_NAME"

# Resources
cp "Sources/WPWriterKit/Resources/editor.html" "$RESOURCES_DIR/editor.html"

# Info.plist
cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
    <key>NSExceptionDomains</key>
    <dict>
      <key>localhost</key>
      <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
        <key>NSIncludesSubdomains</key><false/>
      </dict>
    </dict>
  </dict>
</dict>
</plist>
EOF

echo "✓ Built: $APP_BUNDLE"
echo "  Run with: open $APP_BUNDLE"
echo "  Install:  cp -r $APP_BUNDLE /Applications/"
