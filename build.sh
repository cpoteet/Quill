#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Quill"
BUNDLE_ID="com.quill.app"
MIN_MACOS="13.0"

echo "▶ Closing $APP_NAME..."
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true

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
cp "Sources/QuillKit/Resources/editor.html" "$RESOURCES_DIR/editor.html"
cp "Sources/QuillKit/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "Sources/QuillKit/Resources/tiptap-bundle.js" "$RESOURCES_DIR/tiptap-bundle.js"
cp "Sources/QuillKit/Resources/editor-transforms.js" "$RESOURCES_DIR/editor-transforms.js"

# Info.plist
cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1.3.0</string>
  <key>CFBundleShortVersionString</key><string>1.3.0</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Chris Poteet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoadsInWebContent</key><true/>
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

echo "▶ Signing $APP_BUNDLE..."
codesign --force --sign - "$APP_BUNDLE"

echo "✓ Built: $APP_BUNDLE"

echo "▶ Launching $APP_NAME..."
open "$APP_BUNDLE"
