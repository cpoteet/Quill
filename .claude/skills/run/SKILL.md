---
description: Build and launch Quill (native macOS WordPress editor)
---

## Launch steps

1. Quit the running app: `pkill -f "^/Users/Chris/Documents/Claude/WP Mac App/Quill.app/Contents/MacOS/Quill" 2>/dev/null || true`
2. Build: `cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh`
3. Open: `open "/Users/Chris/Documents/Claude/WP Mac App/Quill.app"`

Build takes ~6 seconds. Warnings about `try?` and `evaluateJavaScript` are expected and harmless. The app is ready when `open` returns.
