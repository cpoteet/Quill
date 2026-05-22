# Spec: Post/Page Type Awareness, Draft Publishing, and Scheduling

**Date:** 2026-05-22  
**Branch:** feature/wp-writer-implementation

## Overview

Four related improvements to how WPWriter handles post types, local drafts, and publishing status.

---

## 1. Contextual New Button

**Problem:** The ⌘N "New Draft" button always creates a post-type local draft, even when the user is browsing Pages.

**Behavior after fix:**
- New button pressed while in the Posts section → creates a local draft of type "post"
- New button pressed while in the Pages section → creates a local draft of type "page"
- Local drafts section is unaffected (always shows drafts of both types)
- When a typed local draft is published to WordPress, it routes to the correct endpoint (posts or pages)

**Data change:** `LocalDraft` gets a `type` field ("post" or "page"). The SQLite drafts table gets a `type` column; existing rows default to "post" via a schema migration.

---

## 2. Type Labels in the Drafts List

**Problem:** All local drafts show "local draft" as the subtitle with the same color dot, making it impossible to tell posts from pages.

**Behavior after fix:**
- Post drafts: purple dot, subtitle reads "post draft"
- Page drafts: indigo dot, subtitle reads "page draft"
- Breadcrumb in the editor toolbar shows "Posts ›" or "Pages ›" (instead of "Drafts ›") based on the draft's type

---

## 3. Publish Button Respects Status Picker

**Problem:** The main toolbar button always publishes live, ignoring the Status picker in the settings panel. There is no way to upload a local draft to WordPress with "draft" status using the Publish button.

**Behavior after fix:**
- The main button label changes based on the Status picker:
  - Status = Draft → button reads "Save as Draft"
  - Status = Scheduled → button reads "Schedule"
  - Status = Published, post is already live → button reads "Update"
  - Status = Published, post is new/local → button reads "Publish"
- Clicking the button saves to WordPress using whatever status is selected
- The Save Draft shortcut (⌘S) is unchanged — it remains a quick "save with draft status" action

---

## 4. Schedule Toggle and Status Picker Stay in Sync

**Problem:** The Schedule toggle and the Status picker are independent. A user can turn on scheduling without the status changing to "Scheduled", causing WordPress to reject the request. Opening an already-scheduled post doesn't restore its scheduled date.

**Behavior after fix:**
- Turning the Schedule toggle ON automatically sets status to "Scheduled" and pre-fills the date to 1 hour from now if no date is set
- Turning the Schedule toggle OFF clears the date and reverts status to "Draft" (if it was "Scheduled")
- Selecting "Scheduled" in the status picker automatically enables the date picker with a default date
- Selecting "Draft" or "Published" in the status picker clears the scheduled date
- Opening a post that is already scheduled on WordPress restores its scheduled date in the picker

---

## Files Affected

- `Storage/Database.swift` — schema migration v1 → v2 (add `type` column)
- `Storage/DraftStore.swift` — `create()` and `fetchAll()` gain `type` support
- `App/AppState.swift` — `LocalDraft.type` field; `PostItem.statusBadge` differentiation
- `Views/Sidebar/SidebarView.swift` — `createNewDraft()` passes type from active section
- `Views/Sidebar/PostListRow.swift` — subtitle and dot color based on type
- `Views/Editor/PostEditorView.swift` — breadcrumb, button label, `publish()` logic, `loadItem()` date restore
- `Views/Settings/PostSettingsPanel.swift` — schedule/status coupling
