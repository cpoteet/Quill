# Privacy Policy

**Quill** is a native macOS app for writing and publishing WordPress content. This page explains what data Quill stores, what it sends over the network, and what it never does.

---

## What stays on your Mac

Quill stores the following data locally in `~/Library/Application Support/Quill/`:

- **credentials.json** — your WordPress site URL and Application Password. Stored as a plain JSON file with restricted permissions (chmod 600). Quill deliberately does not use the macOS system keychain to avoid password prompts when the app relaunches.
- **ai_settings.json** — your Anthropic API key and AI preferences (if you use the AI writing feature), also chmod 600.
- **A local SQLite database** — drafts you've started but not yet published, and autosaved versions of posts and pages you're editing. This is local only; it is not synced anywhere.

---

## What Quill sends over the network

Quill makes two kinds of outbound connections:

**1. Your WordPress site**
Every read and write operation (loading posts, saving drafts, publishing, uploading media) goes directly to your WordPress site's REST API using the credentials you provide. Quill is the client; your site is the server. No third party is involved in this traffic.

**2. Anthropic's API (optional)**
If you enable AI writing features and provide an Anthropic API key, the text you select or the topic you describe is sent to Anthropic's API to generate or improve content. This uses your own API key and is subject to [Anthropic's privacy policy](https://www.anthropic.com/privacy). AI features are entirely opt-in and require you to supply your own key — Quill has no built-in key and makes no AI calls without one.

---

## What Quill never does

- **No analytics or telemetry.** Quill does not collect usage data, crash reports, or any metrics about how you use the app.
- **No accounts.** There is no Quill account, no sign-in, and no central server. The app has no way to identify you.
- **No cloud sync.** Your local drafts and settings never leave your Mac unless you explicitly publish them to your own WordPress site.
- **No advertising.** Quill is not ad-supported and shares no data with advertisers.

---

## Deleting your data

To remove everything Quill stores on your Mac:

1. Quit Quill.
2. Delete `~/Library/Application Support/Quill/` — this removes credentials, AI settings, and the local draft database.
3. Delete `Quill.app` from your Applications folder.

Nothing else needs to be cleaned up. Quill leaves no other traces on your system.

---

## Contact

Questions or concerns? Open an issue at [github.com/cpoteet/Quill-Releases](https://github.com/cpoteet/Quill-Releases/issues).
