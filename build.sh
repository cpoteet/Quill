#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Quill"
BUNDLE_ID="com.siolon.quill"
MIN_MACOS="27.0"
SIGN_IDENTITY="Developer ID Application: CHRISTOPHER LEE POTEET (NRCW9A2622)"

RELEASE=false
[ "${1:-}" = "--release" ] && RELEASE=true

echo "▶ Closing $APP_NAME..."
pkill -f "^$PWD/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null && sleep 0.5 || true

if ! [ -d "$(xcode-select -p 2>/dev/null)/usr/bin" ] || ! xcrun -f actool >/dev/null 2>&1; then
  echo "✗ actool not found. build.sh compiles Assets.xcassets, which needs full Xcode --"
  echo "  the Command Line Tools alone do not provide it."
  echo "  Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

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
cp "Sources/QuillKit/Resources/tiptap-bundle.js" "$RESOURCES_DIR/tiptap-bundle.js"
cp "Sources/QuillKit/Resources/marked-bundle.js" "$RESOURCES_DIR/marked-bundle.js"
cp "Sources/QuillKit/Resources/editor-transforms.js" "$RESOURCES_DIR/editor-transforms.js"
cp "Sources/QuillKit/Resources/block-parser-bundle.js" "$RESOURCES_DIR/block-parser-bundle.js"
cp "Sources/QuillKit/Resources/block-serializer.js" "$RESOURCES_DIR/block-serializer.js"
cp "Sources/QuillKit/Resources/block-descriptors.js" "$RESOURCES_DIR/block-descriptors.js"
cp "Sources/QuillKit/Resources/block-settings.js" "$RESOURCES_DIR/block-settings.js"

# Accent colour and app icon. Compiled, not copied — NSAccentColorName and
# CFBundleIconName below only resolve out of Assets.car.
xcrun actool Assets.xcassets AppIcon.icon \
  --compile "$RESOURCES_DIR" \
  --platform macosx \
  --minimum-deployment-target "$MIN_MACOS" \
  --app-icon AppIcon \
  --output-partial-info-plist "$(mktemp -t quill-assets)" \
  --output-format human-readable-text > /dev/null

if [ ! -f "$RESOURCES_DIR/Assets.car" ]; then
  echo "✗ actool did not produce Assets.car -- the accent colour and app icon would be missing."
  exit 1
fi

# Info.plist
cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>2.0.0</string>
  <key>CFBundleShortVersionString</key><string>2.0.0</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Chris Poteet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>NSAccentColorName</key><string>AccentColor</string>
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

if $RELEASE; then
  echo "▶ Signing $APP_BUNDLE with Developer ID (hardened runtime)..."
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  echo "✓ Built: $APP_BUNDLE (release, not launched)"
  exit 0
fi

echo "▶ Signing $APP_BUNDLE..."
codesign --force --sign - "$APP_BUNDLE"

echo "✓ Built: $APP_BUNDLE"

echo "▶ Launching $APP_NAME..."
open "$APP_BUNDLE"
