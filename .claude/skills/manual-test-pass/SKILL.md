---
name: manual-test-pass
description: Use when running or resuming a manual test pass of Quill from docs/testing-plan.md §7 with computer use and the REST API against the local Studio site, including re-verifying bugs and writing the run log.
---

# Manual test pass (Quill)

An agent can drive most of `docs/testing-plan.md` §7 with computer use, the WordPress REST API, SQLite and the validator. This skill is how to set a pass up, what works, what does not, how to log, and how to leave things.

Read first: "Running the manual pass with an agent" in `docs/testing-plan.md`, and, when resuming, the latest `docs/manual-test-run-<date>.md` (Progress, Resume here, Issues, Observations).

**Announce at start:** "Running a manual test pass."

## Ground rules

- Do not fix code during a pass. Read the source for root causes of bugs and note them in the log.
- Do not commit. Summarize and wait.
- Log as you go so another agent can pick up where you stop.
- Before declaring an item blocked, try a workaround from "Techniques". "Blocked" is for things that need a system setting, a password typed into a browser, VoiceOver, or a second physical condition (Wi-Fi off).
- Prohibited for the agent even with permission: changing System Settings (dark mode, Wi-Fi), typing passwords to authenticate in a browser. Entering a throw-away application password for a local Studio site into Quill's Settings is allowed only when the user has said so in chat; if the permission check denies it, stop and ask.

## Setup

1. Record the sha256 of `~/Library/Application Support/Quill/credentials.json` and `ai_settings.json` and copy both to the scratchpad (`orig/`). Quill rewrites them with a different key order whenever it launches, so restore the copies byte-for-byte at the end and do not relaunch Quill afterwards.
2. Build and run exactly as the project `CLAUDE.md` says. Check the site with `curl http://localhost:8881/wp-json/`.
3. Request full-screen control and access to Quill, Finder and Mail (Mail only if testing `mailto:`). Never grant a terminal or browser; use Bash for shell work.
4. Make a REST helper in the scratchpad that reads `credentials.json` inside the script and never prints it. Note that it follows whatever site Quill is currently connected to; read the saved copy in `orig/` when you need site A while Quill points at site B.
5. Keep test files in `~/Documents/Claude/QuillTestFiles/` (PNG, JPEG, GIF, TIFF, `IMG_1234.HEIC`, `other.heic`, a 12 MB PNG, `.pdf`, `.docx`, `.txt`, `.csv`, `rich.rtf`, `rich.html`).
6. Do computer-use testing on new local drafts or on QA posts, never on a published post.

## Techniques that work

**Reading what was saved**
- Remote post: REST `…/posts/<id>?context=edit`. Local draft: `sqlite3 ~/Library/Application\ Support/Quill/drafts.db "select content from local_drafts …"`. Footnote bodies are in `local_drafts.footnotes` or `meta.footnotes`.
- Validate with `Scripts/wp-validator.js` (`problems(html)` returns `[]` when clean).
- Seed posts from `Scripts/fixtures/*.html` by `POST /posts`, open in Quill, type one character, ⌘S, and diff the raw content. Concatenating the `settings-*` fixtures into one post checks every preserved block setting in one go (byte-identical is the pass).

**Driving the UI**
- Wait one second between typing and the next click; clicks soon after typing are dropped.
- After a Finder `open`, Quill is behind Finder. Click the Finder Dock icon to bring Finder forward before a drag, and a Quill sidebar row to return.
- Finder drag: `left_mouse_down`, then `mouse_move` steps with 0.2–0.3 s waits, then `left_mouse_up`. Without waits Finder rubber-bands. Click a row once and drag; a second click on a selected row starts a rename.
- `left_click_drag` works for the image resize handles and for a gallery-sheet row grip dragged downwards. It does not work for Finder drags.
- Open panels: ⌘⇧G types a path; the first click on Open after selecting a row is swallowed.
- Settings buttons shift when a caption line appears; re-screenshot before clicking Save.
- A toolbar button keeps its hover highlight while the pointer is on it; move the caret to see the true state.
- Toasts last 2–6 s. Capture every second, not every five.
- The sidebar search stays set across ⌘N and section switches; clear it before tests that need the full list.

**Clipboards**
- Plain text: `write_clipboard`. A PNG: `osascript -e 'set the clipboard to (read (POSIX file "…") as «class PNGf»)'`.
- HTML with its plain-text flavor: build `Scripts/paste-harness/setpb.swift` with `swiftc -O` and run `setpb clip.html clip.txt`. Reuse the captured pairs in `Scripts/fixtures/paste/` for Word, Google Docs, WordPress front end, VS Code, ChatGPT, Claude and Apple Notes. Make small hand-made clips for list-item, empty-paragraph, outside-ProseMirror (`data-pm-slice`) and `data:` image cases.
- Put the Anthropic key or any secret on the clipboard only through `pbcopy` from a script, and overwrite the clipboard afterwards.

**Faults and slow networks (no Wi-Fi change)**
- `Scripts/qa-fault-injector.php` as a mu-plugin in `~/Dev/Studio/wp-content/mu-plugins/` with `qa-fault.json` (`status`, `delay_ms`, `match`, `method`, `warn`, `log`). It holds one rule at a time, so a case needing two faults cannot be built. Write the JSON with `rm -f` then `echo >`; the shell hook refuses `>` over an existing file.
- `cd ~/Dev/Studio && studio site stop` / `start` gives a real "can't connect". `start` prints the admin password and may open Safari; filter the output.
- A second site: `studio site start` in `~/Studio/codex` (port 8882), make a throw-away application password with `studio wp user application-password create admin "<name>" --porcelain`, and revoke it with `… delete admin <uuid>`. That site answers in several seconds per request; bump its IDs with draft posts, not uploads.
- Media paging and the 500+ grid: seed with a loop of tiny PNG `POST /media` calls, then delete them by ID at the end.

**Other**
- Forcing the block-risk banner: in code view, replace the content with a paragraph plus `<!-- wp:heading --><p>Not a heading</p><!-- /wp:heading -->` and leave code view. Deleting a card does not raise it.
- AI checks use the real key and cost a little. Cut-off needs a very long Generate request; the model sometimes shortens the post and finishes inside the limit.
- Thumbnail bandwidth: `nettop` does not count Quill's loopback traffic, but `nettop -m tcp -n -x -s 1 -L 14 -J bytes_in,bytes_out` shows the Studio node and PHP processes' byte counts.
- Plain `pkill` and `pgrep -f` match your own shell command text; use `pgrep -x Quill`.
- Safari or other apps the agent has no grant for may open and be hidden from screenshots; ignore them.

## What needs a person

WordPress's Authorize Application page; dark mode and every "light and dark" check; full screen and animation watching; VoiceOver; Wi-Fi-off wording ("Mac is offline"); clicking links that open the browser. Opening posts in Gutenberg is a quick manual check: switch the editor to Visual (it remembers Code editor mode) and look for "unexpected or invalid content".

## Logging

Keep two separate tables in the run log, each numbered on its own, plus a results section.

### Bugs (Issues table)

A bug is behaviour that is wrong, loses data, shows false information, contradicts the plan or the code's own comment, or can be reproduced to a wrong result. Columns: `# | Sev | Area | What happens, repro steps, and root cause if read`. Severities: Moderate (wrong data or state saved), Low–Moderate, Low, Question (the plan does not say what is right).

Rules for a row:
- Reproduce it twice, or re-verify with fresh steps, before logging.
- Write the steps so someone else can follow them, with the exact input and the observed output.
- For a bug you read the code for, add the file and line and the likely cause, marked as a read, not a confirmation.
- Never edit an existing row's number. Number new rows after the last one.

### Observations and improvements (separate table)

An observation is behaviour that is correct or arguable but worth recording: wording that differs from the plan, harmless quirks, WordPress or macOS behaviour, harness limits, positive confirmations that go beyond the plan (for example "unsafe hrefs are stripped on load"), and small UX improvements. Columns: `# | Type | Area | Note`. Types: Improvement, Plan fix (the plan was wrong; edit the plan too), Quirk, Platform (WordPress or macOS, not Quill), Harness (a limit of the test method), Positive.

Do not put these in the Issues table. If an observation later turns out to lose data or show wrong information, move it to Bugs with a new number and leave a pointer.

### Results detail

Per section, one line per check: `PASS`, `FAIL (issue N)`, `BLOCKED (reason)`, `SKIP (reason)`, `N/A`. Say how it was verified (REST, SQLite, validator, screenshot, source read). Record weak passes as weak, and sampled checks as sampled with what was and was not covered.

### Progress and handoff

Keep at the top of the log: a Progress table (section, status, one-line notes), "Resume here" (state when paused, what an agent can still do, what needs a person), the Issues table, the Observations table, "Test plan edits made", and "Final state". Update the plan wherever its wording is wrong or unclear for an agent, and say so in the log.

## Re-verifying bugs

Re-run each open bug from a clean start with fresh steps. Record "re-verified" with the steps used, or "no longer reproduces" with what changed. For bugs where the cause is a race, make several attempts and say how many reproduced.

## Finish

1. Quit Quill, then restore `credentials.json` and `ai_settings.json` from `orig/` and confirm with `cmp` and the recorded sha256. Check that `credentials.json` points at site A.
2. Remove the fault injector, `qa-fault.json` and `qa-fault.log`; delete seeded bulk media; stop any second site and revoke its application password; delete test users; revoke application passwords the pass created (list them with `GET /users/me/application-passwords`).
3. Empty the `local_drafts` table. Delete only the `autosaves` rows you created (rows with older `saved_at` belong to the user).
4. Overwrite the clipboard. Close Finder windows you opened. Quit Mail if you started it.
5. Fill "Final state" in the log: what is running, file hashes, what was left on the site, uncommitted repo changes.
6. Report: updated bug list, observations added, what is still blocked on the user, and the exact state left behind.
