#!/usr/bin/env bash
# Capture a post's raw post_content from WordPress and diff two captures, to
# prove a Quill save with no edits is byte-identical. Reads credentials.json
# itself; the app password is never printed.
#
#   ./Scripts/roundtrip-check.sh 18166 before   # then save in Quill, no edits
#   ./Scripts/roundtrip-check.sh 18166 after    # prints the verdict
set -euo pipefail

POST_ID="${1:?usage: roundtrip-check.sh <postId> <before|after>}"
PHASE="${2:?usage: roundtrip-check.sh <postId> <before|after>}"
CRED="$HOME/Library/Application Support/Quill/credentials.json"
OUT="${TMPDIR:-/tmp}/quill-roundtrip-$POST_ID"
mkdir -p "$OUT"

SITE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["siteURL"].rstrip("/"))' "$CRED")
AUTH=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["username"]+":"+d["appPassword"])' "$CRED")

for TYPE in posts pages; do
  CODE=$(curl -sS -u "$AUTH" -o "$OUT/raw.json" -w '%{http_code}' \
    "$SITE/wp-json/wp/v2/$TYPE/$POST_ID?context=edit&_fields=content,modified")
  [ "$CODE" = "200" ] && break
done
if [ "$CODE" != "200" ]; then echo "HTTP $CODE fetching $POST_ID — is the id right?" >&2; exit 1; fi

python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));sys.stdout.write(d["content"]["raw"])' \
  "$OUT/raw.json" > "$OUT/$PHASE.html"
echo "captured $PHASE: $(wc -c < "$OUT/$PHASE.html" | tr -d ' ') bytes"

if [ "$PHASE" = "after" ]; then
  if [ ! -f "$OUT/before.html" ]; then echo "no 'before' capture found" >&2; exit 1; fi
  if cmp -s "$OUT/before.html" "$OUT/after.html"; then
    echo "BYTE-IDENTICAL ✓"
  else
    echo "DIFFERS ✗ — first differences:"
    diff <(fold -w 120 "$OUT/before.html") <(fold -w 120 "$OUT/after.html") | head -40
  fi
fi
