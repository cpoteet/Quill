# WPWriter

Native macOS app for writing and managing WordPress content. Built with Swift Package Manager (no Xcode needed).

## Status

Design and planning complete. Ready to implement.

## Where to start

Read the implementation plan and execute it task by task:

```
docs/superpowers/plans/2026-05-21-wp-writer-implementation.md
```

Use the `superpowers:subagent-driven-development` or `superpowers:executing-plans` skill to work through the 19 tasks in order.

## Key decisions

- **Stack:** Swift 6, SwiftUI (macOS 13+), WKWebView, URLSession async/await
- **Editor:** Tiptap 2.x inside a WKWebView, loaded from esm.sh CDN (no npm needed). Supports bold/italic/underline/strike, headings H1–H3, blockquote, code block, bullet/ordered/task lists, tables (with row/column controls), links, and image insertion via native media picker.
- **API:** WordPress REST API with Application Passwords (no plugin required)
- **Storage:** SQLite.swift for local drafts and autosaves
- **Build:** `./build.sh` → produces `WPWriter.app` (no Xcode required, Swift 6.3.1 is already installed)

## Docs

- Spec: `docs/superpowers/specs/2026-05-21-wp-mac-app-design.md`
- Plan: `docs/superpowers/plans/2026-05-21-wp-writer-implementation.md`
