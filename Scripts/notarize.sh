#!/usr/bin/env bash
# Usage: Scripts/notarize.sh [output-dir] — writes a notarized Quill.zip there (default ~/Desktop)
set -euo pipefail

cd "$(dirname "$0")/.."

PROFILE="quill-notary"
OUT_DIR="${1:-$HOME/Desktop}"
APP="Quill.app"
WORK=$(mktemp -d -t quill-notarize)

VERSION=$(sed -n 's/.*<key>CFBundleShortVersionString<\/key><string>\(.*\)<\/string>.*/\1/p' build.sh)
BUILD=$(sed -n 's/.*<key>CFBundleVersion<\/key><string>\(.*\)<\/string>.*/\1/p' build.sh)
if [ "$VERSION" != "$BUILD" ]; then
  echo "✗ build.sh has version $VERSION but build number $BUILD; set both to the release version."
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "✗ v$VERSION is already released. Update the version in build.sh before notarizing."
  exit 1
fi
echo "▶ Notarizing Quill $VERSION"

./build.sh --release

echo "▶ Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
grep -q "flags=0x10000(runtime)" <<< "$SIGNATURE" \
  || { echo "✗ Hardened runtime is not enabled."; exit 1; }

echo "▶ Checking fixtures in WebKit against the signed build..."
"./$APP/Contents/MacOS/Quill" --check-fixtures "$PWD/Scripts/fixtures"

echo "▶ Submitting to Apple (this waits for the result)..."
ditto -c -k --keepParent "$APP" "$WORK/Quill-notarize.zip"
xcrun notarytool submit "$WORK/Quill-notarize.zip" \
  --keychain-profile "$PROFILE" --wait --output-format json > "$WORK/result.json"
STATUS=$(plutil -extract status raw -o - "$WORK/result.json")
SUBMISSION=$(plutil -extract id raw -o - "$WORK/result.json")
echo "  Submission $SUBMISSION: $STATUS"

if [ "$STATUS" != "Accepted" ]; then
  xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE"
  echo "✗ Notarization failed."
  exit 1
fi

echo "▶ Stapling..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▶ Packaging Quill.zip..."
mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/$APP"
cp LICENSE.md NOTICES.md "$WORK/stage/"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/Quill.zip"
ditto -c -k --norsrc --noextattr --noqtn "$WORK/stage" "$OUT_DIR/Quill.zip"

echo "▶ Checking the packaged app as a user would receive it..."
mkdir "$WORK/unpacked"
ditto -x -k "$OUT_DIR/Quill.zip" "$WORK/unpacked"
for f in LICENSE.md NOTICES.md; do [ -f "$WORK/unpacked/$f" ] || { echo "✗ $f missing from Quill.zip."; exit 1; }; done
spctl --assess --type execute -vv "$WORK/unpacked/$APP" 2>&1 | tee "$WORK/spctl.txt"
grep -q "source=Notarized Developer ID" "$WORK/spctl.txt" \
  || { echo "✗ Gatekeeper does not see a notarized app."; exit 1; }

rm -rf "$WORK"
echo "✓ Notarized: $OUT_DIR/Quill.zip"
