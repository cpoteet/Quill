#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

run() {
  local label="$1"
  shift
  echo ""
  echo "▶ $label"
  if "$@"; then
    echo "✓ $label passed"
    PASS=$((PASS + 1))
  else
    echo "✗ $label FAILED"
    FAIL=$((FAIL + 1))
  fi
}

run "Swift tests"  swift test
run "JS block serializer tests"  node --test Scripts/test-block-serializer.js
run "JS editor tests"  node --test Scripts/test-editor.js
run "JS editor keyboard tests"  node --test Scripts/test-editor-keyboard.js
run "JS gallery tests"  node --test Scripts/test-editor-gallery.js
run "JS passthrough tests"  node --test Scripts/test-editor-passthrough.js
run "JS paste tests"  node --test Scripts/test-editor-paste.js

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✓ All test suites passed ($PASS/$((PASS + FAIL)))"
else
  echo "✗ $FAIL suite(s) failed — $PASS/$((PASS + FAIL)) passed"
  exit 1
fi
