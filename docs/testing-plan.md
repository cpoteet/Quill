# Quill — Test Suite Reference

_Last updated: 2026-07-10 — 333 Swift tests + 177 JS tests, all passing._

This document is the authoritative reference for Quill's automated test suite and manual testing checklists. It covers how to run every test, what each test covers, and which manual checks to run before a release.

---

## Running the tests

### Full suite (recommended after every code change)

```bash
./test.sh
```

`test.sh` runs both test layers in sequence and prints a pass/fail summary:

1. **Swift tests** — `swift test` (all 333 tests across 22 suites)
2. **JS editor tests** — `node --test Scripts/test-editor.js` (120 tests via Node's built-in runner + jsdom)
3. **JS keyboard tests** — `node --test Scripts/test-editor-keyboard.js` (38 tests — live Tiptap editor in jsdom)
4. **JS gallery tests** — `node --test Scripts/test-editor-gallery.js` (19 tests — live Tiptap editor in jsdom)

If either layer fails, `test.sh` exits non-zero and reports which suite failed.

### Run Swift tests only

```bash
swift test
```

### Run one Swift suite

```bash
swift test --filter WordPressClientTests
swift test --filter AIPromptBuilderTests
# etc. — filter matches the @Suite struct name
```

### Run JS editor tests only

```bash
node --test Scripts/test-editor.js
```

Requires `node` and the `jsdom` package (already installed in the project root via `npm install`).

---

## Swift test suite (333 tests, 22 suites)

Framework: `swift-testing`. Target: `Tests/QuillTests/`. Support files: `Tests/QuillTests/Support/`.

### Suite summary

| # | Suite | File | Tests | What it covers |
|---|---|---|---|---|
| 1 | `WPPostDecodingTests` | `WPPostDecodingTests.swift` | 33 | `WPPost` JSON decoding, optional-field defaults, `editorHTML` fallback, wpautop for classic content, HTML entity decoding, `excerptText` plain-text extraction, empty content from `_fields` list fetch |
| 2 | `WPMediaDecodingTests` | `WPMediaDecodingTests.swift` | 15 | `WPMedia`/`MediaDetails`/`MediaSize` float-dimensions gotcha, `thumbnailURL` fallback, `sizedURL(for:)` size resolution incl. "full" slug and blank-URL fallback |
| 3 | `PostPayloadTests` | `PostPayloadTests.swift` | 11 | `PostPayload` encoding, scheduling key names, nil omission |
| 4 | `CredentialsTests` | `CredentialsTests.swift` | 4 | `Credentials.basicAuthHeader` base64 encoding |
| 5 | `WordPressClientTests` | `WordPressClientTests.swift` | 51 | URL construction (incl. literal `+` escaped to `%2B` in query values), `_fields` filter, HTTP error mapping, `searchLinks`, auth headers, Content-Disposition escaping, media fetch/upload/delete/alt-text, streaming uploads |
| 6 | `JSONFileStoreTests` | `JSONFileStoreTests.swift` | 8 | Round-trip, chmod 600, atomic write, nil-on-absent |
| 7 | `CredentialsStoreTests` | `CredentialsStoreTests.swift` | 10 | Credentials persistence, `AppSupportDirectory`, `AISettingsStore` |
| 8 | `DraftStoreTests` | `DraftStoreTests.swift` | 13 | Local draft CRUD, ordering, unicode, non-existent ID safety |
| 9 | `AutosaveStoreTests` | `AutosaveStoreTests.swift` | 8 | Autosave CRUD, one-per-post, `serverModified`, `savedAt` ordering |
| 10 | `TaxonomyCacheTests` | `TaxonomyCacheTests.swift` | 12 | Category/tag cache, TTL boundary, replace semantics, collision guard |
| 11 | `AppDatabaseTests` | `AppDatabaseTests.swift` | 2 | Migration idempotency, old-schema `type` column backfill |
| 12 | `AIPromptBuilderTests` | `AIPromptBuilderTests.swift` | 66 | `parseGenerateResponse` edge cases (incl. `<cite>` wrapper stripped while inner citation text is preserved, even across a nested inline tag), system prompt, all prompt builders (incl. list/table context with correct `<ul>`/`<ol>` tags), evaluation ANCHOR parsing, style guide injection, typographic entity decoding, content exclusion filters, phantom punctuation-spacing suppression |
| 13 | `AnthropicClientTests` | `AnthropicClientTests.swift` | 21 | Request headers, web search, multi-block joining, error handling (incl. optional `stop_reason` decoding and `AnthropicError.networkError` wrapping with friendly offline messaging) |
| 14 | `PostItemTests` | `AppStateTests.swift` | 10 | `PostItem.id`, `.title`, `.statusBadge` computed properties |
| 15 | `SidebarSectionTests` | `AppStateTests.swift` | 8 | `SidebarSection.icon` and `.shortTitle` for all cases |
| 16 | `AppStateLoadingTests` | `AppStateTests.swift` | 2 | `AppState` initial loading flags (`isLoadingList`, `hasLoadedList`, `isLoadingMedia`, `hasLoadedMedia`) |
| 17 | `AppStateFilteredItemsTests` | `AppStateTests.swift` | 10 | `AppState.filteredItems` per section, search filtering |
| 18 | `SectionIsEmptyTests` | `AppStateTests.swift` | 5 | `AppState.sectionIsEmpty` per section |
| 19 | `EditorCoordinatorTests` | `EditorCoordinatorTests.swift` | 7 | `isAllowedExternalURL` URL scheme allowlist |
| 20 | `PostEditorHelpersTests` | `PostEditorHelpersTests.swift` | 14 | `previewURL` query/fragment handling; status helpers (`publishButtonTitle`, `toastMessage`, `statusDidChange` for future/private/pending); `PostStats` reading time |
| 21 | `UpdateCheckerTests` | `UpdateCheckerTests.swift` | 7 | `isNewer` semantic version comparison: major/minor/patch, equal, older, different segment counts, large numbers |
| 22 | `MimeTypeTests` | `MimeTypeTests.swift` | 12 | `MimeType.forExtension`/`forFile` UTType-backed lookups, case-insensitivity, unknown/empty extension fallback to `application/octet-stream` |

---

### 1. Model decoding — `WPPostDecodingTests` (33 tests)

File: `Tests/QuillTests/WPPostDecodingTests.swift`

Guards the `WPPost` decoding path, which contains `decodeIfPresent` defaults that have caused production bugs. Also covers `editorHTML` wpautop for classic content and `decodingHTMLEntities()` for title display.

| Test | What it checks |
|---|---|
| `fullPostDecodesAllFields` | All standard fields decode from a complete JSON fixture |
| `pageOmittingCategoriesAndTagsDefaultsToEmpty` | Pages endpoint omits `categories`/`tags` → both default to `[]` without throwing |
| `missingTypeDefaultsToPost` | `type` absent → `"post"` |
| `missingFeaturedMediaDefaultsToZero` | `featured_media` absent → `0` |
| `missingDateGmtDefaultsToEmptyString` | `date_gmt` absent → `""` |
| `missingParentDefaultsToZero` | `parent` absent → `0` |
| `missingCommentStatusDefaultsToOpen` | `comment_status` absent → `"open"` |
| `contentRawPreferredOverRendered` | `content.raw` decoded when present; `editorHTML` returns `raw` |
| `emptyContentRawFallsBackToRenderedForEditorHTML` | `raw == ""` → `editorHTML` returns `rendered` |
| `whitespaceContentRawFallsBackToRenderedForEditorHTML` | `raw == "\n  "` → `editorHTML` returns `rendered` |
| `missingRequiredFieldThrows` | Omitting `id` → decoding throws (required field guard) |
| `futureStatusDecodes` | `status: "future"` decodes without error |
| `classicContentGetsWpautop` | Double-newline classic content → `<p>` wrapped paragraphs |
| `classicContentSingleNewlineBecomesBr` | Single newline → `<br />` within paragraph |
| `classicContentWithInlineHTML` | Inline HTML (`<a>`, `<strong>`) preserved inside `<p>` wrapping |
| `classicContentBlockElementNotWrapped` | Block elements (`<blockquote>`) not double-wrapped in `<p>` |
| `gutenbergContentUnchanged` | Content with `<!-- wp:` comments passed through unchanged |
| `contentWithParagraphTagsUnchanged` | Content already containing `<p>` tags not re-wrapped |
| `classicContentShortcodePreserved` | WordPress shortcodes preserved inside `<p>` wrapping |
| `classicContentListNotCorrupted` | `<ul>/<li>` not wrapped in `<p>` or injected with `<br>` |
| `classicContentListWithAttributes` | `<ol start="3">` attributes preserved through wpautop |
| `classicExcerptGetsWpautop` | Classic excerpt (no `<p>`, no block comments) gets wpautop |
| `classicContentTableNotCorrupted` | `<table>` elements not wrapped in `<p>` |
| `decodesNumericEntities` | `&#8217;` → `'` (right single quotation mark) |
| `decodesHexEntities` | `&#x26;` → `&` |
| `decodesNamedEntities` | `&ldquo;`, `&rdquo;`, `&amp;`, `&lt;`, `&gt;` decode correctly |
| `noEntitiesPassthrough` | Plain text without entities passes through unchanged |
| `decodesMultipleMixed` | Multiple numeric and named entities in one string |
| `excerptTextReturnsRawStrippingHTML` | `excerptText` strips HTML from `raw`, ignores `rendered` |
| `excerptTextReturnsEmptyWhenRawEmpty` | `raw == ""` → `excerptText` returns `""` (no fallback to auto-generated `rendered`) |
| `excerptTextReturnsEmptyWhenRawNil` | `raw == nil` → `excerptText` returns `""` |
| `excerptTextDecodesEntities` | `excerptText` decodes HTML entities (e.g. `&#8217;` → `'`) |
| `missingContentAndExcerptDefaultToEmpty` | No `content`/`excerpt` keys (list fetch with `_fields`) → both default to empty `RenderedString` without throwing |
| `blockGalleryContentSurvivesEditorHTML` | `raw` content containing real `<!-- wp:gallery -->`/`<!-- wp:image -->` block comments survives `editorHTML` unchanged (regression guard — `wpautop`'s classic-content detection must never touch content that already has `<!-- wp:` comments) |

---

### 2. Model decoding — `WPMediaDecodingTests` (15 tests)

File: `Tests/QuillTests/WPMediaDecodingTests.swift`

Guards the float-dimensions gotcha: WordPress returns `width`/`height` as JSON floats (`2560.0`) which Swift's `Int` decoder rejects without the try-Int-then-Double fallback. Also covers `altText`, `thumbnailURL`, and `sizedURL(for:)`.

| Test | What it checks |
|---|---|
| `integerDimensionsDecode` | `"width": 2560` → `Int` |
| `floatDimensionsDecodeToInt` | `"width": 2560.0` → `Int` via the fallback path (regression guard) |
| `missingMediaDetailsIsNil` | `media_details` absent → `nil`, no throw |
| `missingTitleDefaultsToEmpty` | `title` absent → empty `RenderedString` |
| `sizesMapDecodes` | `sizes` dict with named sizes → `[String: MediaSize]` |
| `sizesDimensionsAsFloatsDecode` | Float `width`/`height` inside `sizes` entries also decode |
| `malformedSizesDoesNotCrash` | `sizes: []` (wrong type) → `try?` swallows it, whole `WPMedia` still decodes |
| `altTextDecodesFromAltText` | `alt_text` key → `altText` property |
| `missingAltTextDefaultsToEmpty` | `alt_text` absent → `""` |
| `thumbnailURLUsesThumbnailSizeWhenPresent` | `sizes["thumbnail"].source_url` present → `thumbnailURL` returns it, not `sourceURL` |
| `thumbnailURLFallsBackToSourceURLWhenNoThumbnailSize` | No `media_details` → `thumbnailURL` returns `sourceURL` |
| `sizedURLUsesMatchingSizeWhenPresent` | `sizedURL(for: "medium")` returns that size's `source_url` when present |
| `sizedURLFallsBackToSourceURLWhenSizeMissing` | Requested slug absent from `sizes` → falls back to `sourceURL` |
| `sizedURLFallsBackToSourceURLWhenMatchedSizeHasBlankURL` | Matched size entry exists but its `source_url` is `""` → falls back to `sourceURL` (regression: a bare `??` on the optional chain would not catch this, since `""` is non-nil) |
| `sizedURLAlwaysUsesSourceURLForFullSlugEvenWhenAFullSizeEntryExists` | `sizedURL(for: "full")` always returns `sourceURL`, ignoring any `sizes["full"]` entry |

---

### 3. Model encoding — `PostPayloadTests` (11 tests)

File: `Tests/QuillTests/PostPayloadTests.swift`

Guards `PostPayload` encoding — encoding bugs corrupt published content silently. Tests decode the emitted JSON back into a dictionary to assert key names and presence.

| Test | What it checks |
|---|---|
| `schedulingUsesDateGmtKeyNotDate` | Scheduling uses key `date_gmt`, never `date` (scheduling gotcha) |
| `nilDateGmtOmitsKeyFromJSON` | `dateGmt: nil` → key absent from JSON |
| `nilSlugOmitsKeyFromJSON` | `slug: nil` → key absent (preserves server value on update) |
| `nonEmptySlugIncludedInJSON` | Non-nil slug → key present |
| `nilFeaturedMediaOmitsKey` | `featuredMedia: nil` → `featured_media` absent |
| `featuredMediaIncludedWhenSet` | Non-nil `featuredMedia` → key present |
| `nilParentOmitsKey` | `parent: nil` → key absent (posts have no parent) |
| `parentIncludedForPages` | `parent: 5` → key present (pages can have parent) |
| `emptyCategoriesAndTagsEncodeAsEmptyArrays` | `[]` → still encodes as `[]`, not omitted |
| `categoriesAndTagsPopulated` | Non-empty arrays encode correctly |
| `codingKeyNamesAreCorrect` | `featured_media`, `comment_status`, `date_gmt` exact key names asserted |

---

### 4. Auth — `CredentialsTests` (4 tests)

File: `Tests/QuillTests/CredentialsTests.swift`

| Test | What it checks |
|---|---|
| `basicAuthHeaderKnownVector` | `user:pass` → exact base64 `"Basic dXNlcjpwYXNz"` |
| `appPasswordWithSpacesEncodedVerbatim` | Spaces in WordPress app passwords encoded as-is, not stripped |
| `basicAuthHeaderHasCorrectPrefix` | Header starts with `"Basic "` |
| `unicodeUsernameEncodedAsUTF8` | Non-ASCII username encoded via UTF-8 bytes |

---

### 5. Networking — `WordPressClientTests` (51 tests)

File: `Tests/QuillTests/WordPressClientTests.swift`
Support: `Tests/QuillTests/Support/MockURLProtocol.swift`

`@Suite(.serialized)` — runs sequentially because `MockURLProtocol.requestHandler` is a shared static. Uses `URLSessionConfiguration.ephemeral` with `MockURLProtocol` as the protocol class.

#### URL & request construction (13 tests)

| Test | What it checks |
|---|---|
| `fetchPostsDecodesList` | `fetchPosts` decodes a list of posts |
| `fetchPostsIncludesRequiredQueryParams` | `per_page`, `page`, `context=edit`, `status=…` all present |
| `createPostUsesPostMethodWithJsonContentType` | `POST /posts`, `Content-Type: application/json` |
| `updatePostUsesPutMethodOnPostsId` | `PUT /posts/{id}` |
| `createPageUsesPostMethodOnPagesEndpoint` | `POST /pages` |
| `updatePageUsesPutMethodOnPagesId` | `PUT /pages/{id}` |
| `authorizationHeaderIncludedInRequests` | `Authorization: Basic …` on all requests |
| `uploadMediaSetsContentTypeFromMimeType` | `Content-Type` matches passed mime type |
| `uploadMediaSetsContentDispositionWithFilename` | `Content-Disposition` includes `filename="…"` |
| `uploadMediaSpacesInFilenameArePercentEncoded` | Spaces in filenames percent-encoded in `filename*` part |
| `contentDispositionFallbackPassesThroughNormalFilename` | Plain filename unchanged in quoted fallback |
| `contentDispositionFallbackEscapesDoubleQuote` | `"` → `\"` in quoted fallback |
| `contentDispositionFallbackEscapesBackslash` | `\` → `\\` in quoted fallback |
| `contentDispositionFallbackStripsNewlines` | Newlines removed from quoted fallback |
| `contentDispositionFallbackStripsControlCharacters` | Control chars (< 32) removed from quoted fallback |
| `contentDispositionFallbackPreservesUnicode` | Unicode (e.g. `café.jpg`) passes through unchanged |
| `uploadMediaEscapesQuotesInContentDispositionFilename` | End-to-end: quoted filename with `"` produces valid `Content-Disposition` header |
| `uploadMediaStreamsFromFileNotHttpBody` | `uploadMedia(fileURL:)` uses `URLSession.upload(fromFile:)`, not `httpBody` (streaming regression guard) |
| `fetchMediaItemHitsCorrectEndpointWithEditContext` | `GET /media/{id}?context=edit`, returns decoded `WPMedia` |
| `updateMediaAltTextSendsPostToMediaEndpoint` | `POST /media/{id}` with `application/json` |
| `updateMediaAltTextBodyContainsAltText` | Request body has `{"alt_text":"…"}` |
| `updateMediaAltTextReturnsDecodedMedia` | Response decoded into `WPMedia` |
| `deleteMediaSendsDeleteWithForceTrueQuery` | `DELETE /media/{id}?force=true` (permanent — vs trash's `force=false`) |
| `createAutosaveSendsToPostAutosavesEndpoint` | `POST /posts/{id}/autosaves` |
| `createPageAutosaveSendsToPageAutosavesEndpoint` | `POST /pages/{id}/autosaves` |
| `fetchAllPostsRequestIncludesFieldsFilter` | `fetchAllPosts` query includes `_fields=` (list fetch omits content body) |
| `fetchPostRequestOmitsFieldsFilter` | `fetchPost` has no `_fields=` (full content required for editor) |

#### Taxonomy (6 tests)

| Test | What it checks |
|---|---|
| `fetchAllCategoriesHitsCategoriesEndpointWithPerPage100` | `per_page=100` |
| `fetchAllCategoriesPaginatesAcrossMultiplePages` | Follows `X-WP-TotalPages` to page 2 |
| `fetchAllTagsHitsTagsEndpointWithPerPage100` | `/tags` endpoint |
| `fetchAllTagsPaginatesAcrossMultiplePages` | Tags pagination |
| `createCategoryUsesPostMethodOnCategoriesEndpoint` | `POST /categories` with `{"name":…}` |
| `createTagUsesPostMethodOnTagsEndpoint` | `POST /tags` with `{"name":…}` |

#### Error mapping (7 tests)

| Test | What it checks |
|---|---|
| `fetchPostsThrowsOnHTTPError` | Non-2xx → `APIError.httpError` |
| `trashPostThrowsOnHTTPError` | DELETE non-2xx → error |
| `httpErrorPreservesStatusCode` | Status code in `APIError.httpError(statusCode:body:)` |
| `httpErrorPreservesBodyString` | Body string preserved in error |
| `nonUtf8ResponseBodyBecomesEmptyString` | Non-UTF8 body → `body = ""`, no crash |
| `successWithMalformedJsonThrowsDecodingError` | 200 + garbage JSON → `APIError.decodingError` (not `httpError`) |
| `networkFailureThrowsNetworkError` | `URLError` from mock → `APIError.networkError` |

#### Cancellation (1 test)

| Test | What it checks |
|---|---|
| `urlErrorCancelledRethrowsAsCancellationError` | `URLError(.cancelled)` → `CancellationError`, not wrapped in `APIError.networkError` |

#### Trash (2 tests)

| Test | What it checks |
|---|---|
| `trashPostSendsDeleteRequest` | `DELETE /posts/{id}?force=false` (recoverable) |
| `trashPageSendsDeleteRequest` | `DELETE /pages/{id}?force=false` |

#### `searchLinks` (8 tests)

| Test | What it checks |
|---|---|
| `searchLinksReturnsMergedResults` | All three sub-requests succeed → merged list |
| `searchLinksIgnoresSubrequestFailures` | Media/term failure → others still returned |
| `searchLinksAllSubrequestsFailReturnsEmptyArray` | All fail → `[]`, no throw |
| `searchLinksPostsFailWhileTermsSucceed` | Posts sub-request fails → terms/media still returned |
| `searchLinksPageSubtypeMapsToPageType` | `subtype == "page"` → `.page` result type |
| `searchLinksTagSubtypeMapsToTagType` | `subtype == "tag"` → `.tag` result type |
| `searchLinksUnknownTermSubtypeFallsToCategory` | Unknown term subtype → `.category` |
| `searchQueryPlusCharacterIsPercentEscaped` | A `+` in the search term is escaped to `%2B` in the query string (WordPress/PHP decodes a literal `+` as a space) |

---

### 6. Storage — `JSONFileStoreTests` (8 tests)

File: `Tests/QuillTests/JSONFileStoreTests.swift`

Tests use an `in: baseDirectory` parameter pointing to a per-test temp dir — fully isolated, no global state.

| Test | What it checks |
|---|---|
| `roundTrip` | `save` → `load` returns equal value |
| `loadReturnsNilWhenAbsent` | No file → `nil`, no throw |
| `deleteRemovesFile` | File gone after `delete()` |
| `deleteWhenAbsentDoesNotThrow` | `delete()` on missing file is a no-op |
| `overwriteKeepsLatestValue` | Save twice → one file with the latest value |
| `savedFileHasChmod600` | Posix permissions after save are `0o600` (security regression guard) |
| `decodeFailureThrows` | Malformed JSON on disk → `load()` throws |
| `distinctFilenamesDontCollide` | Two stores with different names are independent |

---

### 7. Storage — `CredentialsStoreTests` (10 tests)

File: `Tests/QuillTests/CredentialsStoreTests.swift`

`@Suite(.serialized)` — uses `AppSupportDirectory.override` (a global) so only one test at a time writes to the temp dir. Override is set in `init` and cleared in `deinit`.

#### `CredentialsStore` / credentials (3 tests)

| Test | What it checks |
|---|---|
| `saveAndLoad` | Credentials round-trip through `CredentialsStore` |
| `loadReturnsNilWhenEmpty` | No stored creds → `nil` |
| `deleteRemovesCredentials` | Credentials gone after delete |

#### `AppSupportDirectory` (4 tests)

| Test | What it checks |
|---|---|
| `appSupportDirectoryCreatesDir` | `directory()` creates the dir and returns it |
| `appSupportDirectoryIsIdempotent` | Calling `directory()` twice doesn't error |
| `appSupportFileURLJoinsCorrectly` | `fileURL(name:)` appends the name to the dir path |
| `appSupportOverrideKeepsFilesInTempDir` | With override set, no files created under real `~/Library/Application Support/Quill` |

#### `AISettingsStore` (3 tests)

| Test | What it checks |
|---|---|
| `aiSettingsRoundTrip` | Full `AISettings` (apiKey, styleGuide, samplePostIDs, siteURL) round-trips |
| `aiSettingsLoadReturnsNilWhenAbsent` | No file → `nil` |
| `aiSettingsDeleteRemovesSettings` | File gone after delete |

---

### 8. Storage — `DraftStoreTests` (13 tests)

File: `Tests/QuillTests/DraftStoreTests.swift`

Uses `AppDatabase.inMemory()` — each test gets an isolated DB.

| Test | What it checks |
|---|---|
| `createAndFetch` | Create → `fetchAll` returns it |
| `createPageDraft` | `type: "page"` stored correctly |
| `fetchAllPreservesType` | Multiple types returned with correct type field |
| `update` | Updated title/content reflected on next fetch |
| `delete` | Draft gone after delete |
| `loadByIdReturnsNilForUnknownId` | Unknown id → `nil` |
| `loadByIdReturnsCorrectDraft` | Correct draft by id |
| `loadByIdReflectsUpdates` | Load after update returns new content |
| `emptyTitleAndContentRoundTrip` | Blank strings store and load correctly |
| `updateNonExistentIdDoesNotThrow` | Update on missing id → no-op |
| `deleteNonExistentIdDoesNotThrow` | Delete on missing id → no-op |
| `fetchAllOrderedByUpdatedAtDesc` | Most recently updated sorts first |
| `unicodeAndEmojiRoundTrip` | Non-ASCII text, emoji, curly quotes preserved byte-exact |

---

### 9. Storage — `AutosaveStoreTests` (8 tests)

File: `Tests/QuillTests/AutosaveStoreTests.swift`

Uses `AppDatabase.inMemory()`.

| Test | What it checks |
|---|---|
| `saveAndLoad` | Autosave round-trip |
| `loadReturnsNilForUnknownPost` | Unknown post id → `nil` |
| `saveOverwritesExisting` | Second save for same post replaces first (one row per post) |
| `deleteRemovesAutosave` | Gone after delete |
| `deleteOnMissingPostIDDoesNotThrow` | Delete on unknown id → no-op |
| `oneSavePerPostID` | Save twice for same id → exactly one row |
| `serverModifiedPreservedExactly` | `serverModified` timestamp stored and returned intact |
| `laterSaveHasNewerSavedAt` | `savedAt` on second save is ≥ first |

---

### 10. Storage — `TaxonomyCacheTests` (12 tests)

File: `Tests/QuillTests/TaxonomyCacheTests.swift`

Uses `AppDatabase.inMemory()`.

| Test | What it checks |
|---|---|
| `saveAndLoadCategories` | Category list round-trip |
| `staleAfterTTL` | Cache is stale after 25h |
| `freshWithinTTL` | Cache is fresh within 24h |
| `saveAndLoadTags` | Tag list round-trip |
| `staleTagsAfterTTL` | Tags stale after TTL |
| `freshTagsWithinTTL` | Tags fresh within TTL |
| `staleJustAfterTTLBoundary` | Stale at exactly 24h01m |
| `freshJustBeforeTTLBoundary` | Fresh at exactly 23h59m |
| `saveCategoriesReplacesAll` | Save `[1,2]` then `[2,3]` → only `[2,3]` remain (full replace, not merge) |
| `categoryAndTagWithSameIDCoexist` | Category wp_id=1 and tag wp_id=1 don't collide (type is part of PK) |
| `saveEmptyCategoriesYieldsEmptyLoad` | `save([])` → `load()` returns `[]` |
| `isStaleWhenNoDataExists` | No data ever saved → `isStale` returns `true` |

---

### 11. Storage — `AppDatabaseTests` (2 tests)

File: `Tests/QuillTests/AppDatabaseTests.swift`

| Test | What it checks |
|---|---|
| `migrationIsIdempotent` | Running `migrate()` twice on same schema doesn't throw |
| `typeColumnMigratedFromOldSchema` | Old DB (without `type` column) → migrate adds it; existing rows default to `"post"` |

---

### 12. AI — `AIPromptBuilderTests` (65 tests)

File: `Tests/QuillTests/AIPromptBuilderTests.swift`

Pure function tests — no network, no async. `parseGenerateResponse` has been patched twice for real production bugs; these tests pin every edge case.

#### `parseGenerateResponse` (14 tests)

| Test | What it checks |
|---|---|
| `happyPathParsesCorrectly` | Standard `TITLE:…CONTENT:…` structure |
| `markdownFencesStripped` | ` ```html … ``` ` fences removed before parsing |
| `webSearchPreambleGluedDirectlyToTitle` | Preamble text joined to `TITLE:` without newline still parsed (uses `range(of:)`, not `hasPrefix`) |
| `caseInsensitiveMarkers` | `title:`/`content:` lowercase → still parsed |
| `missingTitleMarkerReturnsNil` | No `TITLE:` → `nil` |
| `missingContentMarkerReturnsNil` | No `CONTENT:` → `nil` |
| `emptyTitleReturnsNil` | `TITLE:` with no text → `nil` |
| `emptyContentReturnsNil` | `CONTENT:` with no text → `nil` |
| `titleIsTrimmed` | Leading/trailing whitespace stripped from title |
| `contentIsTrimmerd` | Content trimmed via `whitespacesAndNewlines` |
| `contentMarkerScopedAfterTitleMarker` | Stray `CONTENT:` before `TITLE:` doesn't fool parser |
| `citeTagWrapperStrippedButTextKept` | `<cite index="…">…</cite>` wrapper from web search citations is removed but the sentence inside it is kept in the generated HTML |
| `citeTagWithNestedInlineTagStillStripped` | A citation wrapping a nested inline tag (e.g. `<a>`) still has its `<cite>` wrapper stripped — regression guard for the `[^<]*` capture group that used to fail to match (and therefore fail to strip) any citation containing markup |
| `emptyCiteTagRemovedEntirely` | An empty `<cite>` tag is removed with no leftover text |

#### `systemPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `systemPromptWithoutStyleGuide` | `nil` guide → no style block |
| `systemPromptWithEmptyStyleGuideExcludesStyleBlock` | Empty string guide → same as nil |
| `systemPromptWithStyleGuideIncludesIt` | Non-empty guide appended to prompt |

#### `generatePostPrompt` & `operationPrompt` (12 tests)

| Test | What it checks |
|---|---|
| `generatePostPromptNamesHTMLElements` | Prompt contains `<h2>`, `<h3>`, `<p>`, `<ul>`, `<li>` (prevents headings-only-p regression) |
| `generatePostPromptIncludesUserPrompt` | User's prompt string embedded |
| `operationPromptIncludesSelectedHTML` | Selected HTML embedded after "Content to transform:" |
| `makeLongerInstructionPresent` | "longer" in `makeLonger` operation prompt |
| `makeShorterInstructionPresent` | "shorter" in `makeShorter` operation prompt |
| `convertToTableMentionsTableTags` | Table-related tags in `convertToTable` prompt |
| `convertToListMentionsListTags` | List-related tags in `convertToList` prompt |
| `makeLongerWithBulletListContextUsesUlTag` | `context: "bulletList"` → list-specific expansion prompt with `<ul>` |
| `makeLongerWithOrderedListContextUsesOlTag` | `context: "orderedList"` → list-specific expansion prompt with `<ol>` (not `<ul>`) |
| `makeShorterWithOrderedListContextUsesOlTag` | `context: "orderedList"` → list-specific condensation prompt with `<ol>` |
| `makeShorterWithBulletListContextUsesUlTag` | `context: "bulletList"` → list-specific condensation prompt with `<ul>` |
| `makeLongerWithTableContextUsesTableInstruction` | `context: "table"` → table cell expansion prompt |
| `makeShorterWithTableContextUsesTableInstruction` | `context: "table"` → table cell condensation prompt |
| `operationPromptWithNilContextUsesDefaultInstruction` | `context: nil` → default "expand this content" (not list/table-specific) |

#### `styleGuideGenerationPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `styleGuidePromptNumbersSamples` | `--- Sample 1 ---` / `--- Sample 2 ---` numbering |
| `styleGuidePromptWithEmptySamples` | 0 samples → no crash, empty content |
| `styleGuidePromptWordLimit` | 150-word limit mentioned in prompt |

#### `parseEvaluationResponse` (15 tests)

| Test | What it checks |
|---|---|
| `happyPathTwoFindings` | Standard format parsed to `EvaluationResult` with 2 findings |
| `emptyFindingsReturnsResultWithNoFindings` | Empty `FINDINGS:` block → result with 0 findings, not nil |
| `missingSummaryMarkerReturnsNil` | No `SUMMARY:` → `nil` |
| `missingFindingsMarkerReturnsNil` | No `FINDINGS:` → `nil` |
| `emptySummaryReturnsNil` | `SUMMARY:` with no text → `nil` |
| `caseInsensitiveMarkers` | `summary:` / `findings:` lowercase accepted |
| `findingWithoutSuggestionHasNilSuggestion` | Omitting `SUGGESTION` field → `finding.suggestion == nil` |
| `findingWithEmptySuggestionFieldHasNilSuggestion` | `SUGGESTION:` with no text → `nil` |
| `nonQuoteLinesBetweenFindingsAreSkipped` | Non-`QUOTE:` lines between findings ignored |
| `findingsMarkerScopedAfterSummaryMarker` | Stray `FINDINGS:` before `SUMMARY:` not used as real marker |
| `anchorFieldIsParsedIntoFinding` | Full `ANCHOR:` field parsed into `finding.anchor` |
| `anchorFieldIsNilWhenOmitted` | No `ANCHOR:` field → `finding.anchor == nil` |
| `anchorFieldStripsOuterQuotes` | Surrounding `"` stripped from ANCHOR value |
| `anchorFieldEmptyStringBecomesNil` | `ANCHOR: ""` → `nil` (not empty string) |
| `anchorFieldCaseInsensitivePrefix` | Lowercase `anchor:` accepted |

#### `evaluatePostPrompt` (15 tests)

| Test | What it checks |
|---|---|
| `promptIncludesTitle` | Post title embedded in prompt |
| `promptStripsHTMLTags` | HTML removed, text content preserved |
| `promptDecodesHTMLEntities` | `&amp;` / `&lt;` / `&gt;` decoded |
| `promptDecodesSmartQuoteEntities` | `&ldquo;` / `&rdquo;` / `&rsquo;` decoded to Unicode typography chars |
| `promptDecodesTypographicDashAndEllipsis` | `&ndash;` / `&mdash;` / `&hellip;` decoded |
| `promptNamesAllFiveCategories` | Grammar, Clarity, Readability, Wordiness, Tone all named |
| `promptIncludesSummaryAndFindingsFormatInstructions` | `SUMMARY:` / `FINDINGS:` / `QUOTE:` / `ISSUE:` format spec present |
| `promptIncludesAnchorFormatSpec` | `ANCHOR:` format instruction present |
| `promptIncludesStyleGuideWhenProvided` | Non-nil guide embedded with "established writing style" framing |
| `promptOmitsStyleGuideBlockWhenNil` | `nil` guide → no style block in prompt |
| `promptOmitsStyleGuideBlockWhenEmpty` | Empty string guide → no style block |
| `promptExcludesImageCaptionText` | Image caption text excluded from the content sent to Claude |
| `promptExcludesCodeBlockContent` | Code block content excluded from the content sent to Claude |
| `promptExcludesEmbedFigureContent` | Embed figure content excluded from the content sent to Claude |
| `promptExcludesFootnoteMarkersAndBackrefs` | Footnote markers and backref links excluded from content sent to Claude |
| `promptDoesNotInjectSpaceBeforePunctuationAfterInlineTags` | Inline tags (`<a>`) followed by commas don't leave phantom spaces in stripped text |
| `promptStripsSpaceBeforeClosingPunctuation` | Phantom spaces before `;`, `)`, `!`, etc. from inline tag stripping are removed |

---

### 13. AI — `AnthropicClientTests` (21 tests)

File: `Tests/QuillTests/AnthropicClientTests.swift`
Support: `Tests/QuillTests/Support/AnthropicMockURLProtocol.swift`

`@Suite(.serialized)` — uses its own `AnthropicMockURLProtocol` subclass with a separate `static var requestHandler` to avoid races with `WordPressClientTests`' `MockURLProtocol`. Body reconstruction: URLSession clears `httpBody` in URLProtocol; `AnthropicMockURLProtocol.startLoading()` reads the body from `httpBodyStream`.

#### Request headers (3 tests)

| Test | What it checks |
|---|---|
| `requestHasApiKeyHeader` | `x-api-key` header set |
| `requestHasVersionHeader` | `anthropic-version: 2023-06-01` |
| `requestHasContentTypeHeader` | `content-type: application/json` |

#### Beta headers & web search (3 tests)

| Test | What it checks |
|---|---|
| `noBetaHeaderSent` | No `anthropic-beta` header sent (prompt caching and web search are GA, no longer need beta header) |
| `toolsAbsentWhenWebSearchOff` | `tools` key absent from body |
| `toolsPresentWhenWebSearchOn` | `tools` array contains `web_search_20250305` |

#### Prompt caching (1 test)

| Test | What it checks |
|---|---|
| `systemBlockHasCacheControlEphemeral` | System block has `cache_control: {"type":"ephemeral"}` |

#### Response handling (8 tests)

| Test | What it checks |
|---|---|
| `singleTextBlockReturnsText` | Single `type:"text"` block → its text |
| `multipleTextBlocksAreJoinedInOrder` | Multiple text blocks → joined in order (web-search fragmentation gotcha) |
| `nonTextBlocksExcludedFromJoin` | `server_tool_use` and `web_search_tool_result` blocks excluded |
| `allNonTextBlocksThrowsNoTextContent` | All non-text blocks → `AnthropicError.noTextContent` |
| `truncatedTrueWhenStopReasonIsMaxTokens` | `stop_reason: "max_tokens"` → `truncated: true` |
| `truncatedFalseWhenStopReasonIsEndTurn` | `stop_reason: "end_turn"` → `truncated: false` |
| `missingStopReasonFieldDoesNotThrowAndIsNotTruncated` | Response JSON omitting `stop_reason` entirely still decodes (field is `Optional`) and reports `truncated: false` |
| `nonOkStatusThrowsHttpError` | Non-200 → `AnthropicError.httpError(code, body)` |

#### Error handling (6 tests)

| Test | What it checks |
|---|---|
| `httpErrorPreservesBodyString` | Error body string preserved |
| `malformedJsonThrows` | Garbage JSON → decoding throws |
| `networkFailureThrows` | `URLError` from mock → error surfaced |
| `networkFailureWrapsAsAnthropicNetworkError` | Any transport error from `session.data(for:)` is wrapped as `AnthropicError.networkError`, not left as a raw `URLError` |
| `networkErrorShowsFriendlyMessageWhenUnderlyingDescriptionMentionsOffline` | `errorDescription` returns the friendly "Couldn't reach the Anthropic API…" message when the underlying error's description mentions being offline/unable to connect (tested via a controlled fake error, since `URLError.localizedDescription` under `swift test` is a generic fallback string rather than CFNetwork's real text) |
| `networkErrorPassesThroughUnrecognizedMessage` | `errorDescription` passes through the underlying error's message verbatim when it doesn't match the offline/connectivity heuristic |

---

### 14. View-model — `PostItemTests` (10 tests)

File: `Tests/QuillTests/AppStateTests.swift`

| Test | What it checks |
|---|---|
| `remotePostIdFormatsAsRemoteDashId` | `PostItem.remote(post).id == "remote-5"` |
| `localDraftIdFormatsAsLocalDashId` | `PostItem.local(draft).id == "local-5"` |
| `remoteAndLocalWithSameNumericIdDoNotCollide` | `"remote-5" != "local-5"` (sidebar selection guard) |
| `remotePostTitleUsesRenderedTitle` | `post.title.rendered` used as display title |
| `remotePostWithEmptyTitleReturnsUntitled` | Empty rendered title → `"Untitled"` |
| `localDraftTitleUsesDraftTitle` | `draft.title` used as display title |
| `localDraftWithEmptyTitleReturnsUntitled` | Empty draft title → `"Untitled"` |
| `remoteStatusBadgeIsPostStatus` | `post.status` (e.g. `"draft"`) used directly |
| `localPostStatusBadgeIsLocalPost` | `type="post"` → `"local-post"` |
| `localPageStatusBadgeIsLocalPage` | `type="page"` → `"local-page"` |

### 15. View-model — `SidebarSectionTests` (8 tests)

File: `Tests/QuillTests/AppStateTests.swift`

| Test | What it checks |
|---|---|
| `postsIcon` | `.posts.icon == "doc.text"` |
| `pagesIcon` | `.pages.icon == "doc.plaintext"` |
| `localDraftsIcon` | `.localDrafts.icon == "pencil"` |
| `mediaIcon` | `.media.icon == "photo"` |
| `postsShortTitle` | `.posts.shortTitle == "Posts"` |
| `pagesShortTitle` | `.pages.shortTitle == "Pages"` |
| `localDraftsShortTitle` | `.localDrafts.shortTitle == "Drafts"` |
| `mediaShortTitle` | `.media.shortTitle == "Media"` |

### 16. View-model — `AppStateLoadingTests` (2 tests)

File: `Tests/QuillTests/AppStateTests.swift`

Tests that `AppState` initializes with loading flags set correctly — `isLoadingList`/`isLoadingMedia` start `true` and `hasLoadedList`/`hasLoadedMedia` start `false`, so views show a spinner instead of flashing an empty state before the first fetch completes.

| Test | What it checks |
|---|---|
| `initialListStateWaitsForFirstLoad` | `isLoadingList == true`, `hasLoadedList == false` on fresh `AppState` |
| `initialMediaStateWaitsForFirstLoad` | `isLoadingMedia == true`, `hasLoadedMedia == false` on fresh `AppState` |

### 17. View-model — `AppStateFilteredItemsTests` (10 tests)

File: `Tests/QuillTests/AppStateTests.swift`

| Test | What it checks |
|---|---|
| `postsSectionMapsRemotePosts` | `.posts` section → `[.remote(…)]` items |
| `pagesSectionMapsRemotePages` | `.pages` section → `[.remote(…)]` items |
| `localDraftsSectionMapsLocalDrafts` | `.localDrafts` section → `[.local(…)]` items |
| `mediaSectionReturnsEmpty` | `.media` section → always `[]` |
| `emptySearchReturnsAllItems` | `searchText == ""` → guard exits early, all items returned |
| `searchFiltersCaseInsensitively` | `"hello"` matches title `"Hello World"` |
| `searchReturnsEmptyForNoMatch` | `"zzz"` matches nothing |
| `partialTitleMatchReturnsItem` | `"World"` matches `"Hello World"` |
| `whitespaceOnlySearchFiltersOutAllNormalTitles` | `"   "` is non-empty so filtering applies; normal titles have no 3-space run → empty result |
| `searchOnlyAppliesToActiveSection` | Search on `.posts` doesn't bleed into `.pages` data |

---

### 18. View-model — `SectionIsEmptyTests` (5 tests)

File: `Tests/QuillTests/AppStateTests.swift`

Tests the `sectionIsEmpty` computed property on `AppState`, used by `SidebarEmptyState` and `EmptyEditorPlaceholder` to show contextual empty-state messages.

| Test | What it checks |
|---|---|
| `postsEmptyWhenNoPosts` | `.posts` section with no posts → `true` |
| `postsNotEmptyWhenPostsExist` | `.posts` section with posts → `false` |
| `pagesEmptyWhenNoPages` | `.pages` section with no pages → `true` |
| `localDraftsEmptyWhenNoDrafts` | `.localDrafts` section with no drafts → `true` |
| `mediaEmptyWhenNoMedia` | `.media` section with no media → `true` |

---

### 19. Security — `EditorCoordinatorTests` (11 tests)

File: `Tests/QuillTests/EditorCoordinatorTests.swift`

Guards the `isAllowedExternalURL` scheme allowlist (linked to the S2 security finding: clicked links in the editor must not be handed to `NSWorkspace.shared.open` with arbitrary schemes) and `mediaSizesDict(for:)`, the pure helper `handleRequestMediaSizes` uses to build the size dict sent to `setMediaSizes` in the JS editor.

| Test | What it checks |
|---|---|
| `httpURLIsAllowed` | `http://` → allowed |
| `httpsURLIsAllowed` | `https://` → allowed |
| `mailtoURLIsAllowed` | `mailto:` → allowed |
| `fileURLIsNotAllowed` | `file:///` → blocked |
| `javascriptURLIsNotAllowed` | `javascript:` → blocked |
| `ftpURLIsNotAllowed` | `ftp://` → blocked |
| `schemeCheckIsCaseInsensitive` | `HTTPS://` → allowed (lowercased before compare) |
| `mediaSizesDictAddsFullFallbackWhenSizesOmitsIt` | `media_details.sizes` missing a `"full"` entry gets one synthesized from `source_url`/top-level width/height |
| `mediaSizesDictPreservesExistingFullEntry` | A server-provided `"full"` entry in `sizes` is not overwritten |
| `mediaSizesDictFallsBackToSourceURLWhenNoSizesAtAll` | No `media_details.sizes` at all still yields a single `"full"` entry from `source_url` |
| `mediaSizesDictReturnsNilWhenSourceURLIsEmpty` | Empty `source_url` → `nil` (no usable size data) |

---

### 20. Editor helpers — `PostEditorHelpersTests` (14 tests)

File: `Tests/QuillTests/PostEditorHelpersTests.swift`

Tests `PostEditorView` static helpers that are pure functions and can be exercised without instantiating the SwiftUI view.

#### `previewURL` (5 tests)

| Test | What it checks |
|---|---|
| `previewURLAppendsFreshQueryToCleanURL` | Pretty permalink gets `?preview=true` appended |
| `previewURLAppendsPreviewAlongsideExistingQuery` | Plain permalink `/?p=123` becomes `/?p=123&preview=true` (not double `?`) |
| `previewURLReplacesExistingPreviewFalseParam` | Existing `preview=false` is replaced, not duplicated |
| `previewURLPreservesMultipleExistingParams` | Other query params survive the transformation |
| `previewURLPreservesFragment` | `#section` fragment is preserved alongside the new query |

#### `PostStats` (3 tests)

| Test | What it checks |
|---|---|
| `readingTimeZeroWordsIsZero` | Zero-word post → `readingMinutes == 0` |
| `readingTimeShortTextIsOneMinute` | Word count ≤ 238 → `readingMinutes == 1` |
| `readingTimeRoundsUp` | Word count that doesn't divide evenly → reading time rounds up (e.g. 239 words → 2 min) |

#### Status helpers (6 tests)

| Test | What it checks |
|---|---|
| `publishButtonTitlePerStatus` | Each status value maps to the correct button label (`"Publish Draft"`, `"Update"`, `"Schedule"`, `"Submit for Review"`, `"Publish Privately"`, etc.) |
| `toastMessagePerStatus` | Each status transition maps to the correct toast string |
| `statusChangeToFutureSetsDefaultDate` | Switching to `future` when no date exists → `publishDate` set to a non-nil default |
| `statusChangeToFuturePreservesExistingDate` | Switching to `future` when a date already exists → existing date preserved |
| `statusChangeToPrivateClearsScheduledDate` | Switching from `future` to `private` → `publishDate` cleared to `nil` |
| `statusChangeToPendingClearsScheduledDate` | Switching from `future` to `pending` → `publishDate` cleared to `nil` |

### 21. App — `UpdateCheckerTests` (7 tests)

File: `Tests/QuillTests/UpdateCheckerTests.swift`

Tests the `isNewer(remote:local:)` semantic version comparison used by the update checker.

| Test | What it checks |
|---|---|
| `newerMajorVersion` | `2.0.0` > `1.0.0` → `true` |
| `newerMinorVersion` | `1.1.0` > `1.0.0` → `true` |
| `newerPatchVersion` | `1.0.1` > `1.0.0` → `true` |
| `sameVersionIsNotNewer` | `1.0.0` == `1.0.0` → `false` |
| `olderVersionIsNotNewer` | `1.0.0` < `2.0.0` → `false` |
| `differentSegmentCounts` | `1.0.1` > `1.0` → `true`; `1.0` < `1.0.1` → `false` |
| `largeVersionNumbers` | `10.20.30` > `10.20.29` → `true`; `10.20.30` == `10.20.30` → `false` |

### 22. API — `MimeTypeTests` (12 tests)

File: `Tests/QuillTests/MimeTypeTests.swift`

Tests the single shared `MimeType.forExtension`/`forFile` helper (backed by `UTType.preferredMIMEType`) that replaced three independently-drifted `mimeType(for:)` functions in `PostEditorView`, `MediaSidebarSection`, and `MediaPickerView`.

| Test | What it checks |
|---|---|
| `jpegExtension` | `jpg`/`jpeg` → `image/jpeg` |
| `pngExtension` | `png` → `image/png` |
| `gifExtension` | `gif` → `image/gif` |
| `webpExtension` | `webp` → `image/webp` |
| `pdfExtension` | `pdf` → `application/pdf` |
| `heicExtension` | `heic` → `image/heic` |
| `tiffExtension` | `tiff`/`tif` → `image/tiff` |
| `extensionIsCaseInsensitive` | `JPG`/`PNG` → same result as lowercase |
| `unknownExtensionFallsBackToOctetStream` | Unrecognized extension → `application/octet-stream` |
| `emptyExtensionFallsBackToOctetStream` | Empty string → `application/octet-stream` |
| `forFileUsesURLPathExtension` | `forFile(url:)` reads the extension from the URL's path |
| `forFileWithNoExtensionFallsBackToOctetStream` | File URL with no extension → `application/octet-stream` |

---

## JS editor tests (120 tests)

File: `Scripts/test-editor.js`
Transforms file: `Sources/QuillKit/Resources/editor-transforms.js`

Tests run under Node's built-in test runner with jsdom for DOM support. They test `toWordPressHTML`, `extractAlignment`, `formatHTML`, `countStats`, `findMatches`, `findMatchesLoose`, `fuzzyAnchorRegex`, `detectEmbedProvider`, and `embedClassFor` from `editor-transforms.js`.

### `extractAlignment` (6 tests)

| Test | What it checks |
|---|---|
| `alignleft returns left` | `"alignleft"` → `"left"` |
| `alignright returns right` | `"alignright"` → `"right"` |
| `aligncenter returns center` | `"aligncenter"` → `"center"` |
| `empty string returns null` | `""` → `null` |
| `unrelated class returns null` | `"wp-block-image"` → `null` |
| `alignment class mixed with others is still detected` | `"wp-block-image alignright size-large"` → `"right"` |

### `toWordPressHTML` — headings (4 tests)

| Test | What it checks |
|---|---|
| `h1 gains wp-block-heading class` | `<h1>` → `class="wp-block-heading"` |
| `h2 through h6 each gain wp-block-heading` | All heading levels |
| `existing classes on heading are preserved` | Pre-existing classes kept alongside new class |
| `headings are idempotent` | Running twice doesn't duplicate the class |

### `toWordPressHTML` — lists (2 tests)

| Test | What it checks |
|---|---|
| `ul gains wp-block-list` | `<ul>` → `wp-block-list` |
| `ol gains wp-block-list` | `<ol>` → `wp-block-list` |

### `toWordPressHTML` — list item `<p>` unwrapping (2 tests)

| Test | What it checks |
|---|---|
| `single-child <p> inside <li> is unwrapped` | `<li><p>text</p></li>` → `<li>text</li>` |
| `multi-child <li> is left untouched` | Two `<p>` in one `<li>` → unchanged |

### `toWordPressHTML` — blockquote & cite (5 tests)

| Test | What it checks |
|---|---|
| `blockquote gains wp-block-quote class` | `<blockquote>` → `wp-block-quote` |
| `empty cite is stripped` | `<cite></cite>` → removed from saved HTML |
| `whitespace-only cite is stripped` | `<cite>   </cite>` → removed |
| `non-empty cite is preserved` | `<cite>— Author</cite>` → survives |
| `cite stripping only applies inside blockquote` | `<cite>` outside blockquote not touched |

### `toWordPressHTML` — code blocks (1 test)

| Test | What it checks |
|---|---|
| `pre gains wp-block-code class` | `<pre>` → `wp-block-code` |

### `toWordPressHTML` — horizontal rules (2 tests)

| Test | What it checks |
|---|---|
| `hr gains wp-block-separator class` | `<hr>` → `wp-block-separator has-alpha-channel-opacity` |
| `hr class is idempotent` | Running twice doesn't duplicate the class |

### `toWordPressHTML` — images (10 tests)

| Test | What it checks |
|---|---|
| `figure with plain img gets wp-block-image class` | `<figure><img></figure>` gains `wp-block-image` class |
| `data-media-id produces wp-image-{id} class on img inside figure` | `data-media-id="42"` → `class="wp-image-42"` on `<img>` |
| `alignleft on img is moved to figure class` | `alignleft` moved from `<img>` to `<figure>` |
| `alignright on img is moved to figure class` | `alignright` moved from `<img>` to `<figure>` |
| `aligncenter on img is moved to figure class` | `aligncenter` moved from `<img>` to `<figure>` |
| `both alignment and media-id: figure gets align class, img gets wp-image class` | Both transforms applied together |
| `empty figcaption is removed from output` | `<figcaption></figcaption>` stripped |
| `non-empty figcaption gets wp-element-caption class` | Non-empty caption → `class="wp-element-caption"` |
| `whitespace-only figcaption is removed` | `<figcaption>   </figcaption>` treated as empty |
| `table figure is not treated as image figure` | `<figure class="wp-block-table">` → image transforms not applied |

### `toWordPressHTML` — tables (8 tests)

| Test | What it checks |
|---|---|
| `table is wrapped in figure.wp-block-table` | `<table>` → `<figure class="wp-block-table">` |
| `all-th first row is promoted from tbody to thead` | All-`<th>` row moves to `<thead>` |
| `mixed th/td first row is NOT promoted to thead` | Mixed `<th>`/`<td>` → no promotion |
| `table already having thead is not modified` | Pre-existing `<thead>` → untouched |
| `table already inside wp-block-table is not double-wrapped` | Idempotency: one `wp-block-table` after two passes |
| `Tiptap table style and colgroup are stripped` | `style` attribute and `<colgroup>` removed from tables |
| `default colspan=1 and rowspan=1 are stripped from cells` | `colspan="1"` and `rowspan="1"` removed; non-default values preserved |
| `paragraph wrapper inside table cells is unwrapped` | Single `<p>` in `<td>` unwrapped; multi-`<p>` left as-is |

### `toWordPressHTML` — idempotency & edge cases (3 tests)

| Test | What it checks |
|---|---|
| `full document is idempotent across all transform types` | `toWordPressHTML(toWordPressHTML(x)) == toWordPressHTML(x)` for all element types |
| `empty paragraph is stable` | `<p></p>` → `<p></p>` |
| `unicode and emoji in text are preserved` | café, 🎉, curly quotes survive |

### `formatHTML` — block elements (4 tests)

`formatHTML` is the HTML pretty-printer used by code view (`_enterCodeView`). Tests verify structural indentation and inline element handling.

| Test | What it checks |
|---|---|
| `single paragraph renders on one line with no surrounding blank lines` | `<p>text</p>` → one line, no extra blank lines |
| `two top-level blocks are separated by a blank line` | Adjacent block elements have a blank line between them |
| `inline elements stay on the same line as their parent block` | `<strong>`, `<em>` etc. not moved to their own lines |
| `links stay inline` | `<a>` treated as inline, not block |

### `formatHTML` — nested block elements (3 tests)

| Test | What it checks |
|---|---|
| `list items are indented inside ul` | `<li>` indented one level inside `<ul>` |
| `table cells are indented under their row and section` | `<td>` indented inside `<tr>` inside `<tbody>` |
| `blockquote with p and cite each on their own indented lines` | `<p>` and `<cite>` inside `<blockquote>` each on own indented line |

### `formatHTML` — special elements (5 tests)

| Test | What it checks |
|---|---|
| `img void element has no closing tag` | `<img>` serialized without `</img>` |
| `img is indented inside figure` | `<img>` child of `<figure>` gets proper indentation |
| `pre content is preserved verbatim without re-indenting` | Content of `<pre>` not touched (code block gotcha) |
| `empty input returns empty string` | `formatHTML("")` → `""` |
| `unicode and emoji are preserved` | Non-ASCII content survives pretty-printing |

### `formatHTML` — entity escaping (5 tests)

Guards the C1 code-view corruption bug: text nodes and attribute values must be re-escaped when serializing, since the DOM decodes entities on parse.

| Test | What it checks |
|---|---|
| `text node with < is escaped so it round-trips safely` | `5 < 10` → `5 &lt; 10` in output |
| `text node with & is escaped` | `a & b` → `a &amp; b` |
| `text node with > is escaped` | `a > b` → `a &gt; b` |
| `attribute value with " is escaped` | `"` inside attribute value → `&quot;` |
| `attribute value with & is escaped` | `&` inside attribute value → `&amp;` |

### `formatHTML` — HTML comments (5 tests)

Guards block comment preservation: WordPress block comments (`<!-- wp:paragraph -->` etc.) are HTML comment nodes (nodeType 8); if `formatHTML` drops them, code view silently strips all Gutenberg block markup.

| Test | What it checks |
|---|---|
| `block comment before an element is preserved` | `<!-- wp:paragraph -->` and `<!-- /wp:paragraph -->` survive `formatHTML` |
| `block comment with JSON attributes is preserved` | `<!-- wp:image {"id":42,"sizeSlug":"full"} -->` — JSON payload inside comment is not mangled |
| `opening comment appears on its own line before the element` | Opening comment is a separate line above the element, not concatenated inline |
| `closing comment appears on its own line after the element` | Closing comment is a separate line below the element, not concatenated inline |
| `multiple wrapped blocks each keep their block comments` | Two blocks each wrapped in open/close comments: all four comments present, in correct order |

### `countStats` (8 tests)

| Test | What it checks |
|---|---|
| `empty string returns zero counts` | `""` → `{ words: 0, chars: 0, readingTime: 1 }` |
| `null/undefined input returns zero counts` | `null` and `undefined` both return zero stats without throwing |
| `single word` | `"Hello"` → `words: 1` |
| `multiple words counted correctly` | `"Hello world foo"` → `words: 3` |
| `whitespace-only returns zero words` | `"   \t\n"` → `words: 0` |
| `chars counts all non-whitespace characters` | Punctuation and letters counted, spaces excluded |
| `unicode words counted correctly` | Multi-byte characters treated as words correctly |
| `reading time rounds up` | 400-word text → `readingTime: 2` (at 200 wpm, ceil) |

### `findMatches` (7 tests)

| Test | What it checks |
|---|---|
| `case-insensitive match by default` | `"hello"` matches `"Hello World"` |
| `case-sensitive flag respected` | `caseSensitive: true` → `"hello"` does not match `"Hello"` |
| `empty query returns no matches` | `""` → `[]` |
| `no match returns empty array` | Query not in text → `[]` |
| `regex special chars are escaped` | `"a.b"` matches literal `"a.b"`, not `"axb"` |
| `non-overlapping matches` | `"aa"` in `"aaaa"` → 2 matches, not 3 |
| `unicode offsets are correct` | Match positions in text containing multi-byte characters are byte-correct |

### `findMatchesLoose` (7 tests)

| Test | What it checks |
|---|---|
| `matches when editor text has a space before a comma but anchor does not` | `"DSPM , Content"` matches anchor `"DSPM, Content"` — the primary phantom-spacing case |
| `matches when the anchor has the extra space and editor text does not` | Reverse direction: anchor `"DSPM , Content"` matches editor `"DSPM, Content"` |
| `tolerates missing space after a comma` | `"A, B"` matches anchor `"A,B"` |
| `collapses multiple spaces between plain words` | Multiple spaces between words match `\\s+` |
| `still matches an exact phrase` | No regression on exact matches |
| `empty / whitespace query returns no matches` | `""` and `"   "` → `[]` |
| `does not require whitespace between plain words to be absent` | `"quickbrown"` does NOT match anchor `"quick brown"` — word gaps stay required |

### `fuzzyAnchorRegex` (3 tests)

| Test | What it checks |
|---|---|
| `makes whitespace around punctuation optional` | `"DSPM, Content"` → `DSPM\\s*,\\s*Content` |
| `collapses a leading space before punctuation into \\s*` | `"DSPM , Content"` → same regex as without the space |
| `requires a gap between plain words` | `"quick brown"` → `quick\\s+brown` (not optional) |

### `detectEmbedProvider` (5 tests)

| Test | What it checks |
|---|---|
| `youtube.com and youtu.be map to youtube` | Both `youtube.com` and `youtu.be` → `"youtube"` |
| `vimeo maps to vimeo with video type` | `https://vimeo.com/…` → `"vimeo"` |
| `x.com and twitter.com map to twitter` | Both `x.com` and `twitter.com` → `"twitter"` |
| `unknown host returns null` | `https://example.com/…` → `null` |
| `invalid URL returns null` | `"not a url"` → `null` |

### `embedClassFor` (3 tests)

| Test | What it checks |
|---|---|
| `youtube gets full Gutenberg class list with aspect ratio` | `embedClassFor("youtube", "video")` → `"wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube"` |
| `twitter gets rich type without aspect classes` | `embedClassFor("twitter", "rich")` → includes `is-type-rich is-provider-twitter` |
| `unknown provider gets bare wp-block-embed` | `embedClassFor(null, null)` → `"wp-block-embed"` |

### `toWordPressHTML` — embeds (5 tests)

| Test | What it checks |
|---|---|
| `embed figure gets Gutenberg block comment wrappers` | `<figure class="wp-block-embed …">` → wrapped with `<!-- wp:embed … -->` / `<!-- /wp:embed -->` Gutenberg block comments |
| `block comment wrapping is idempotent` | Running `toWordPressHTML` on already-wrapped embed doesn't double-wrap |
| `embed figure does not gain wp-block-image` | No `wp-block-image` class added, no alignment transform |
| `embed figure with caption gets block comment wrappers` | Embed `<figure>` containing a `<figcaption>` still gets wrapped correctly |
| `two embeds with the same URL are each wrapped exactly once` | Two identical embed figures both get their own open/close block comments — regression for the `String.replace()` first-match-only bug |

### `toWordPressHTML` — footnotes (5 tests)

| Test | What it checks |
|---|---|
| `footnote markers numbered in document order` | First `<sup data-fn>` gets `[1]`, second gets `[2]`, etc. |
| `footnote renumbering is idempotent` | Running `toWordPressHTML` twice does not change numbers |
| `sup without data-fn is not renumbered` | Plain `<sup>` not treated as footnote marker |
| `footnotes list does not get wp-block-list` | `<ol class="wp-block-footnotes">` → no `wp-block-list` added |
| `ordinary ol still gets wp-block-list` | Regular `<ol>` without `wp-block-footnotes` still receives `wp-block-list` |

### `toWordPressHTML` — footnote backrefs (3 tests)

| Test | What it checks |
|---|---|
| `marker sup gains id="ref-fn-UUID"` | Each `<sup data-fn="UUID">` gets `id="ref-fn-UUID"` added so backref anchors can target it |
| `footnote list item gains backref link` | Each `<li>` in `<ol class="wp-block-footnotes">` gets `<a href="#ref-fn-…" class="footnote-backref">↩</a>` appended |
| `backref is idempotent — not added twice on double transform` | Running `toWordPressHTML` twice does not add a second backref link |

### `toWordPressHTML` — gallery (9 tests)

| Test | What it checks |
|---|---|
| `gallery figure gets wp:gallery and wp:image comment wrappers` | `figure.wp-block-gallery` + nested `figure.wp-block-image` gets `<!-- wp:gallery {ids,columns,linkTo} -->` and per-image `<!-- wp:image {...} -->` comments |
| `gallery wrapping is idempotent` | Running `toWordPressHTML` twice produces byte-identical output — no compounding whitespace between images on repeated saves |
| `outer gallery figure does not gain wp-block-image class` | The generic image-figure transform excludes `.wp-block-gallery`, so the wrapper figure isn't misclassified |
| `gallery with linkTo=media wraps images in anchors and records linkDestination` | Images already wrapped in `<a href>` produce `"linkTo":"media"` / `"linkDestination":"media"` |
| `cropped=false omits is-cropped class and sets imageCrop:false` | Missing `is-cropped` class → explicit `"imageCrop":false` (only emitted at the non-default) |
| `sizeSlug is read from the image figure class, not hardcoded` | `size-medium` on the image figure produces `"sizeSlug":"medium"`, not a hardcoded `"large"` |
| `an image with no wp-image-N class omits the id key instead of writing null` | Images without a recognized media ID omit `"id"` entirely rather than writing `"id":null` |
| `stripping pre-existing wp:image comments does not consume the images between them` | Regression guard: a loaded gallery's `sourceHTML` can have zero characters between one image's `<!-- /wp:image -->` and the next's `<!-- wp:image -->`; the strip regex must not greedily span past the first comment and delete the images between them |
| `stripping a pre-existing wp:gallery comment works even with a CR before its closing -->` | Regression guard: the non-greedy attrs group is `[\s\S]*?`, not `.*?` — a `\r` before a comment's own `-->` must not defeat the match entirely (JS `.` excludes all line terminators, not just `\n`) |

---

## JS keyboard tests (38 tests)

File: `Scripts/test-editor-keyboard.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Tests load the real `editor.html` in jsdom, instantiate the live Tiptap editor via `window._tiptapEditor`, dispatch real `keydown` events, and assert on the resulting ProseMirror document. This is the only automated coverage of the Enter/Backspace/Shift-Enter handlers — the code paths that caused the June 2026 regression chain.

**jsdom caveat:** ProseMirror only keymap-binds Backspace at node boundaries (joinBackward/lift); mid-text character deletion is browser `beforeinput`, which jsdom does not emit — so only boundary Backspace is asserted.

### `plain paragraphs` (4 tests)

| Test | What it checks |
|---|---|
| `Enter at end of paragraph creates an empty paragraph below` | Basic paragraph splitting |
| `Enter mid-word splits the paragraph cleanly` | Mid-text split |
| `Backspace at start of 2nd paragraph merges into the first (joinBackward)` | Boundary backspace merges paragraphs |
| `Shift+Enter inserts a hard break, not a new paragraph` | Hard break insertion |

### `headings` (1 test)

| Test | What it checks |
|---|---|
| `Enter at end of a heading drops to a paragraph (not another heading)` | Heading exit behavior |

### `lists` (3 tests)

| Test | What it checks |
|---|---|
| `Enter at end of a list item creates a new item` | Normal list item creation |
| `Enter in an empty trailing item exits the list` | Empty item → lift out to paragraph |
| `Backspace at start of the sole list item lifts it to a paragraph` | Boundary backspace in lists |

### `blockquotes & cite` (4 tests)

| Test | What it checks |
|---|---|
| `Enter in a blockquote creates a paragraph inside the quote` | Normal blockquote paragraph splitting |
| `Enter on an empty paragraph inside a blockquote lifts out` | Empty paragraph → exit blockquote |
| `Enter with a selection deletes it before splitting (regression: 8a4f00f)` | Selection deleted before `tr.split`; re-derives depth after delete |
| `Enter inside a cite exits the blockquote to a new paragraph` | Cite Enter → new paragraph below blockquote |

### `footnotes` (2 tests)

| Test | What it checks |
|---|---|
| `Enter in a footnote entry inserts a soft break and keeps text (regression: cbf3e8d)` | Footnote Enter → hardBreak, not swallowed |
| `Backspace at the start of a footnote entry does not corrupt the doc (regression: daee820)` | Boundary backspace in footnotes |

### `image captions` (2 tests)

| Test | What it checks |
|---|---|
| `Enter in an image caption exits to a new paragraph below (regression: 91679d2)` | Caption Enter → paragraph after image |
| `Enter in an image caption inside a blockquote stays well-formed (no image duplication)` | Nested caption Enter doesn't duplicate image |

### `image link-to-full-size` (7 tests)

| Test | What it checks |
|---|---|
| `image wrapped in <a> parses to linkTo media with linkHref, and round-trips` | Loading a figure whose `<img>` is wrapped in `<a href>` recovers `linkTo: 'media'`/`linkHref`, and re-serializes the same `<a>` wrapper |
| `image without a link wrapper defaults to linkTo none and omits <a> from output` | Unwrapped `<img>` defaults to `linkTo: 'none'`, `linkHref: null`, no `<a>` in output |
| `linked image preserves alignment, custom class, and mediaId alongside the link` | `linkTo`/`linkHref` coexist with alignment, custom figure class, and `mediaId` through the round-trip |
| `toggling linkTo to media via setNodeMarkup produces the <a> wrapper on save` | Toolbar toggle path (`setNodeMarkup`) produces the `<a>` wrapper on save, not just the load path |
| `toggling linkTo back to none via setNodeMarkup clears linkHref too` | Regression: turning the link off also clears the stale `linkHref`, not just `linkTo` |
| `classic (non-figure) linked image is detected via the bare img[src] parse rule` | Regression: pre-Gutenberg `<a href><img></a>` markup with no `figure.wp-block-image` wrapper still parses `linkTo`/`linkHref` (previously silently dropped the link on save) |
| `an <a> wrapper with an empty href is not treated as a full-image link` | Regression: `<a href="">` around an image does not set `linkTo: 'media'` (previously showed the toggle as "on" for a link that wouldn't actually save) |

---

## JS gallery tests (19 tests)

File: `Scripts/test-editor-gallery.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Tests load the real `editor.html` in jsdom and instantiate the live Tiptap editor via `window._tiptapEditor` — the same approach as the JS keyboard tests — because `galleryBlock`'s `parseHTML`/`renderHTML` can't be exercised through the pure `editor-transforms.js` helpers alone.

### `galleryBlock` — insert and render (6 tests)

| Test | What it checks |
|---|---|
| `inserting a galleryBlock renders wp-block-gallery figure with nested image figures` | Sheet-style insert (`images`/`columns`/`cropped`/`linkTo` attrs) reconstructs the correct DOM shape |
| `non-default sizeSlug is honored by the reconstruction render path` | Inserting with `sizeSlug: 'medium'` renders `class="wp-block-image size-medium"` on each nested image figure, not the `large` default |
| `linkTo media wraps each image in an anchor to its own url` | `linkTo: 'media'` wraps each `<img>` in `<a href>` pointing at its own URL |
| `linkTo media links to fullUrl (true original), not the display-size url` | Regression: when Size is a non-full display size, `linkTo: 'media'`'s anchor must link to `image.fullUrl` (the true original), not `image.url` (the smaller displayed image) |
| `linkTo media falls back to url when fullUrl is absent` | An `images[]` entry with no `fullUrl` field still produces a working anchor, linking to `url` |
| `cropped false omits is-cropped class` | `cropped: false` omits the `is-cropped` class from the rendered figure |

### `galleryBlock` — load (parseHTML) (4 tests)

| Test | What it checks |
|---|---|
| `loading real gallery HTML recovers images, columns, cropped, linkTo` | Parsing a real `figure.wp-block-gallery` recovers all structured attrs correctly, including `sizeSlug: 'large'` |
| `loading a gallery with a non-large size class recovers that sizeSlug` | A loaded gallery whose image figures have `size-medium` recovers `attrs.sizeSlug === 'medium'`, not the hardcoded default |
| `loading a gallery with images linked to media recovers linkTo=media` | Images already wrapped in `<a>` are recognized as `linkTo: 'media'` on load |
| `captures sourceHTML verbatim, including content the structured attrs do not model` | `sourceHTML` captures the original figure's `outerHTML` (e.g. a caption) that the structured attrs don't represent |

### `galleryBlock` — verbatim re-render (sourceHTML) (2 tests)

| Test | What it checks |
|---|---|
| `a loaded gallery with a caption re-renders with the caption intact` | `sourceHTML` is re-emitted unchanged, preserving captions and other unmodeled content |
| `sheet-inserted galleries (sourceHTML null) still use the reconstruction path` | Sheet-inserted galleries (`sourceHTML: null`) always reconstruct from structured attrs, never accidentally reuse a stale `sourceHTML` |

### `galleryBlock` — code-view round-trip (2 tests)

| Test | What it checks |
|---|---|
| `serialize via toWordPressHTML then re-parse preserves a sheet-inserted gallery` | Save → reload round-trip preserves images/columns/cropped/linkTo for a sheet-inserted gallery |
| `serialize then re-parse preserves a loaded, captioned gallery verbatim` | Save → reload round-trip preserves a caption on a loaded gallery via `sourceHTML` |

### `window.insertGallery` bridge function (4 tests)

| Test | What it checks |
|---|---|
| `inserts a galleryBlock from a JSON payload` | The Swift→JS bridge function parses a JSON payload and inserts a `galleryBlock` |
| `sizeSlug from the JSON payload propagates to node attrs, defaulting to large` | A `sizeSlug` key in the JSON payload reaches `node.attrs.sizeSlug`; an omitted key defaults to `'large'` |
| `ignores an empty images array` | An empty `images` array is a no-op — never inserts a gallery with zero images |
| `inserting at the end of the doc does not synthesize a trailing paragraph` | Confirms the caret-after-an-atom problem is solved purely via gap-cursor CSS, not doc-model surgery — the gallery stays the doc's last node and no phantom `<p></p>` leaks into saved HTML |

### Gap-cursor styling (1 test)

| Test | What it checks |
|---|---|
| `editor.html overrides the default gap-cursor widget to match the app caret` | Guards the CSS override (`.ProseMirror-gapcursor:after { border-left: 1.5px solid #007aff }`) that restyles Tiptap's built-in gap-cursor widget from its default black horizontal bar to the app's blue vertical caret |

---

## Manual / functional test checklists

Run these against a real WordPress test site (or a local Docker WordPress) using an Application Password. Build with `./build.sh` and `open Quill.app` before each pass.

> Tip: use a disposable WordPress instance so destructive tests (delete, trash, publish) don't pollute a real site.

### 7.1 Authentication & onboarding

- [ ] Launch with no saved credentials → login/preferences screen appears.
- [ ] Enter a valid site URL, username, and app password → app connects and post/page lists appear.
- [ ] Enter a site URL without `https://` (e.g. `example.com`) → app either adds the scheme automatically or shows a clear error.
- [ ] Try a site URL with a trailing slash, a subdirectory install (`example.com/blog`), and a non-standard port → all connect successfully.
- [ ] Enter a wrong password → a readable error message appears (not a silent failure or crash). Quit and relaunch → the app still shows the login screen (bad credentials were never written to disk, since validation now happens before the save).
- [ ] Enter a URL for a non-WordPress site or one with the REST API disabled → a clear error appears.
- [ ] Paste an app password that contains spaces → authentication succeeds (WordPress app passwords normally have spaces).
- [ ] No macOS Keychain password prompt appears during normal use.
- [ ] Quit and relaunch → credentials are remembered and lists reload without re-entering them. A spinner appears during loading — the empty-state placeholder does NOT flash before posts arrive.
- [ ] Change the site URL in settings → lists update to the new site; any saved AI sample posts are cleared.

### 7.2 Sidebar, lists, navigation

- [ ] Posts, Pages, Local Drafts, and Media sections each load and show their items.
- [ ] Clicking a sidebar item highlights it with the app's warm accent color (not the default macOS blue).
- [ ] Type in the search field → the current section filters case-insensitively; clearing the search restores all items.
- [ ] When a section is empty (no posts, no pages, no drafts, no media), a descriptive placeholder appears. The editor empty state says "post", "page", or "draft" depending on the active section.
- [ ] Switch to the Media section → the post list, search bar, and toolbar are replaced by a thumbnail grid.
- [ ] Scroll to the bottom of the Posts or Media list → more items load automatically; loading stops when all items have been fetched.
- [ ] The dividers between sidebar/editor and editor/settings panels have no drag cursor — they are fixed boundaries, not resizable splitters.
- [ ] Click the sidebar toggle button in the editor toolbar → sidebar slides away; click again → it slides back. The toggle button stays visible when the sidebar is hidden. The editor expands to fill the space.
- [ ] Upload a PDF via the Media tab → the sidebar cell shows a document icon (not a broken image); the detail panel shows a document icon with "Preview unavailable" (not "Image unavailable"); no alt text field appears.
- [ ] Toggle the sidebar hidden then visible again repeatedly → the post list does not refetch from the server each time (no spinner flash on every toggle); it only reloads on the first load or when credentials actually change.

### 7.3 Editor — content & Gutenberg round-trip

- [ ] Open an existing remote post → content renders the same as it does in WordPress.
- [ ] When clicking a post, the editor briefly shows "Start writing..." while loading, then content appears. Content should be complete and not truncated.
- [ ] Apply each formatting option: bold, italic, strikethrough, inline code, links, headings (h1–h6), bullet lists, numbered lists, blockquote, code block, table. Each renders correctly.
- [ ] Save a post containing all formatting types → fetch the raw content via the WordPress REST API (`?context=edit`). Verify: headings have `wp-block-heading` class, lists have `wp-block-list`, tables are wrapped in `figure.wp-block-table`, images are wrapped in `figure.wp-block-image`, and the first all-header row in a table is promoted to `<thead>`.
- [ ] Open a post, save it without making any changes, then fetch the raw content → it should be identical to before (no drift).
- [ ] Multi-paragraph list items survive a save without being collapsed into a single paragraph.
- [ ] **Blockquote behavior:**
  - [ ] Toggle blockquote on → text is wrapped in a blockquote.
  - [ ] Click the cite toggle button (bookmark icon, appears in toolbar when inside a blockquote) → an empty cite line appears at the bottom (subdued, right-aligned). Click again → the cite is removed.
  - [ ] Type an author name in the cite line, save → `<cite>` persists in the saved HTML.
  - [ ] Leave the cite line blank, save → no empty `<cite>` appears in the saved HTML.
  - [ ] Press Enter inside the cite → cursor exits the blockquote into a new paragraph below.
  - [ ] Press Enter at the end of a paragraph inside a blockquote → a new paragraph is created inside the blockquote (not outside it).
  - [ ] Press Enter in an empty paragraph inside a blockquote → the empty paragraph exits the blockquote (lift out).
  - [ ] Press Backspace in an empty cite → the cite is deleted (not the entire blockquote).
  - [ ] Toggle blockquote off → the quote and its cite are removed cleanly.
- [ ] Write content with curly quotes, emoji, and non-Latin scripts → save and reload → characters are preserved exactly.
- [ ] Open or create a very long post (10k+ words) → the editor stays responsive; save completes successfully.
- [ ] Paste content from Word, Google Docs, or Safari → HTML is reasonable; no script tags or unexpected elements injected.

### 7.4 Editor — images

- [ ] Click the insert image button in the toolbar → select an image from the picker → it appears at the cursor position in the editor.
- [ ] In the image picker grid, click a specific thumbnail → it selects that exact image (not an adjacent one).
- [ ] Drag an image file from Finder onto the editor → the image uploads, appears in the editor, and a success toast is shown.
- [ ] Drag a non-image file (e.g. a `.txt` or `.pdf`) onto the editor → nothing happens (file is ignored).
- [ ] Drag multiple image files onto the editor at once → all upload and insert.
- [ ] Disconnect from the network, then try to insert or drag an image → an error message appears; the editor content is not corrupted.
- [ ] Drag a large file (10+ MB) onto the editor → the UI stays responsive during upload (no freeze). Same check using the Media tab upload button.
- [ ] Click an image in the editor → resize handles appear on the corners and edges. Drag a handle → the image resizes while maintaining its aspect ratio.
- [ ] Add a caption to an image, then click the image → resize handles should align to the image edges, not extend down to the bottom of the caption.
- [ ] Click inside an image caption and press Enter → a new paragraph is created below the image; the cursor moves to it. The image and caption remain intact.
- [ ] Click an image that was inserted from the media library → the image toolbar shows size buttons (Thumbnail, Medium, Large, Full). Click each → the image swaps to that size.
- [ ] Click Reset on an image with sizes loaded → the image returns to its original full-size dimensions. On an image without media sizes, Reset removes custom width/height constraints.
- [ ] Click a classic-editor image (no explicit width/height attributes) → the image toolbar shows the image's natural dimensions (not blank fields).
- [ ] Set image alignment to left, center, and right → text wraps correctly for each. Save and fetch the raw HTML → the figure has `wp-block-image alignleft/aligncenter/alignright`.
- [ ] With an image selected, scroll the editor → the image toolbar moves with the image. Click elsewhere to deselect → the toolbar disappears.
- [ ] Click inside the alt text or caption field in the image toolbar → the toolbar stays open (doesn't close when you click its own controls).
- [ ] Insert images of different formats (`.jpg`, `.png`, `.gif`, `.webp`, `.heic`, `.tiff`) → each uploads successfully.
- [ ] Open the insert image picker from the editor toolbar → the file dialog only shows image files; PDFs and movies are not selectable.
- [ ] Open the upload dialog from the Media tab → the file dialog accepts images, PDFs, and movies.
- [ ] In the media picker sheet, the Cancel button is visible and dismisses the sheet.
- [ ] If the media library has more than 50 items, a "Load More" button appears at the bottom of the picker grid. Click it → more images load and append to the grid.
- [ ] Click the Gallery toolbar button → the `GallerySheet` opens with a media grid; tapping images toggles a checkmark and adds them to the "Selected" list; "Insert Gallery" is disabled until at least one image is selected.
- [ ] With 2+ images selected, set columns, toggle crop, set "Link to" (None / Full Image), set Size (Thumbnail / Medium / Large / Full Size), click Insert Gallery → a read-only thumbnail-grid card appears in the editor. Toggle code view (`</>`) and confirm `<!-- wp:gallery -->`/`<!-- wp:image -->` block comments with the chosen settings, including `"sizeSlug"` matching the selected size.
- [ ] In `GallerySheet`, click Upload → pick a new image from disk → it uploads, appears in the media grid, and is automatically added to the Selected list.
- [ ] Save a post containing a sheet-inserted gallery, then make an unrelated visual edit elsewhere in the post and save again → re-fetch the raw content and confirm the gallery block comments are still present (this is the fix for the previous `_rawHTML`-only silent-drop behavior).
- [ ] Open a post containing a gallery authored outside Quill (e.g. in the WordPress block editor) → it loads as a read-only thumbnail-grid card, not exploded into individual resizable images. Clicking it does not open `GallerySheet` (insert-only for v1).
- [ ] Open a post containing a gallery with an image caption (authored outside Quill) → make an unrelated visual edit elsewhere and save → re-fetch the raw content and confirm the caption is still present (verifies the `sourceHTML` verbatim round-trip, not just the structured reconstruction path).
- [ ] Insert a gallery (or embed) at the very end of a post, then click just after it → the caret shows as a thin blue vertical bar (not a black horizontal bar). Type → a new paragraph is created at that position and text is entered normally.
- [ ] Click a single (non-gallery) image → in the image toolbar, toggle "Link to Full Image" on → save and check code view/raw HTML: the `<img>` is wrapped in `<a href>` pointing at the media's full-resolution URL. Toggle it back off → save again → the `<a>` wrapper is removed. Open a post with a pre-existing linked image (authored outside Quill) → the toggle shows as already on.
- [ ] Drag an image from Finder onto the editor (or paste one) so it has no `mediaId` → select it → confirm the "Link to Full Image" button is visible and toggling it on wraps the image's current `src` in `<a href>` on save.

### 7.5 Editor — links

- [ ] Select text, click the link button → a link popover appears anchored near the selected text. With no selection, the popover anchors to the toolbar button instead.
- [ ] Type a search query in the link popover → results from posts, pages, categories, tags, and media appear.
- [ ] As search results appear, the popover grows taller to fit them (results are not clipped or hidden).
- [ ] Select a search result → a link is inserted on the selected text. Manually typing a URL also works.
- [ ] Search for something with no matches → an empty state is shown; no crash.
- [ ] Search while offline → the popover handles the error gracefully (no crash or hang).
- [ ] Insert links with `http://` and `https://` URLs → Cmd+clicking them in the editor opens the system browser. Hold Cmd → links show an underline and pointer cursor. Release Cmd → cursor returns to normal. Insert a `mailto:` link → Cmd+clicking it opens Mail. Insert a `file:///` or `javascript:alert(1)` link via code view → Cmd+clicking it does nothing (blocked for security).
- [ ] Clicking a link without holding Cmd places the cursor inside the link text (for editing) — it does not open the link.

### 7.6 Editor — code view

**Entering and exiting**
- [ ] The `</>` button appears in the toolbar's utility group, alongside the spell-check and image-align controls.
- [ ] Click `</>` → the visual editor switches to a code textarea; all other toolbar buttons become disabled; the `</>` button shows an active/highlighted state.
- [ ] The code textarea shows nicely formatted HTML: block elements on their own lines, inline elements (`<strong>`, `<a>`, etc.) stay on the same line as their parent, list items are indented inside their list, table cells are nested under rows, and `<pre>` content is left exactly as-is. Top-level blocks are separated by blank lines.
- [ ] Click `</>` again → the editor switches back to visual mode; toolbar buttons re-enable; any HTML changes made in the textarea are reflected in the visual editor.

**Editing and saving**
- [ ] Make a change in the code textarea, exit code view → the visual editor shows the change.
- [ ] Enter code view without changing anything, exit → the visual editor content is completely unchanged.
- [ ] Enter and exit code view repeatedly without editing → the HTML formatting does not accumulate extra blank lines or whitespace with each cycle.
- [ ] With code view active, press ⌘S → the content from the textarea is saved to WordPress (not stale content from before entering code view).
- [ ] Make a change in the code textarea, press ⌘S without exiting code view first → the change is saved to WordPress.
- [ ] While in code view, click a different post in the sidebar → code view exits automatically and the new post loads in visual mode.
- [ ] In dark mode, the code textarea background and text colors match the rest of the editor (no bright white flash).
- [ ] With the image toolbar or embed menu open, enter code view → both dismiss automatically (no stale floating panels remain).

**Special characters**
- [ ] Write a paragraph containing `5 < 10`, `a & b`, and a `"quoted"` word. Enter code view → the HTML shows `&lt;`, `&amp;`, `&quot;` correctly. Switch back to visual → original text is intact. Save and reload → still intact.

**Block posts/pages** (posts created in the WordPress block editor)
- [ ] Open a block-based post that uses Gallery or Columns blocks. Enter code view without making any visual edits first → WordPress block comments (`<!-- wp:gallery -->`, etc.) are visible in the textarea.
- [ ] Open the same post, make a visual edit (e.g. fix a typo), then enter code view → block comments are gone. This is expected: once you edit visually, Quill's editor becomes the source of truth.

**Non-block pages** (pages with plain HTML, no Gutenberg blocks)
- [ ] Open a page with no block comments (e.g. a simple About page). Enter code view → the HTML is indented and readable, not compressed onto a single line.

**Round-trips**
- [ ] Make a visual edit, then open code view → the edit is visible in the HTML.
- [ ] Make a visual edit → save → close the post → reopen → content is intact.
- [ ] Make only visual edits, never open code view → save → content saves correctly.
- [ ] Edit in code view → exit → save → close the post → reopen → enter code view → the edit is present and the HTML is still formatted (not compressed).

### 7.7 Save / publish / draft / schedule

- [ ] Save a local draft → it persists locally only (no network call); toast shows "Saved locally".
- [ ] If the local draft save fails (e.g. disk full) → a red error toast appears with the failure reason.
- [ ] Publish a local draft → a remote post is created on WordPress; the local copy disappears from the Drafts list; the sidebar selection moves to the new remote item in the Posts or Pages section.
- [ ] A page draft publishes to the pages endpoint; a post draft publishes to the posts endpoint.
- [ ] Press ⌘S on a remote draft → it updates on WordPress while keeping its "draft" status.
- [ ] Press ⌘⇧P or click Publish on a remote post → the post publishes. The button label matches the action: "Publish" for drafts, "Update" for published posts, "Schedule" for future-dated posts, "Submit for Review" for pending posts, "Publish Privately" for private posts.
- [ ] Set a future date on a post → status changes to "future" and the post is scheduled. Check on the WordPress server that the scheduled time matches (particularly important for sites in non-UTC timezones).
- [ ] Close and reopen a scheduled post → the correct future date appears in the settings panel.
- [ ] Type a new category or tag name in the settings panel, then save → the category/tag is created on WordPress, its ID is attached to the post, and it appears in the category/tag list.
- [ ] If creating a new category or tag fails (e.g. no permission) → the save stops with an error; post content is not lost. Retry the save → any names that already succeeded before the failure are not resubmitted (no "term_exists" error re-blocking the save).
- [ ] Open a post while offline (or force the full-post fetch to fail) → an error toast explains the post may be missing content; attempting to save shows "Can't save — this post never finished loading" instead of silently publishing empty content over the real post.
- [ ] On a new post, leave the slug blank → it stays blank (doesn't inherit another post's slug). Edit the slug and save → the slug is sent. On an existing post, leave the slug blank → the server's current slug is preserved (not overwritten with empty).
- [ ] Set a featured image → it appears on the post. Clear the featured image → it is removed on the server.
- [ ] Toggle comment status between open and closed → the setting round-trips correctly on save.
- [ ] In the page parent picker, the current page does not appear in the list. Save with a parent selected → the parent is set on the server.

### 7.8 Conflict detection

- [ ] Open a remote post in Quill. Edit the same post from another client (or directly on the server) so its `modified` date changes. Save in Quill → a "Conflict Detected" dialog appears.
  - [ ] Click "Keep Local" (⌘↩) → Quill saves its version, overwriting the server.
  - [ ] Click "Use Server" → Quill reloads the server's content, discarding local edits.
  - [ ] Click "Cancel" → the dialog closes and editing continues; no data is lost.
- [ ] Open a post, immediately save without anyone else changing it → no conflict alert appears.
- [ ] Preview a draft post, then save → no spurious conflict alert appears.
- [ ] On a site using plain permalinks (`?p=123` URLs), click Preview → the browser opens the correct URL with `&preview=true` appended (not a malformed double `?`).
- [ ] On a site using pretty permalinks (`/my-post/` URLs), click Preview → the browser opens `…/?preview=true`.

### 7.9 Autosave / unsaved changes / navigation

- [ ] Edit a remote post, wait 30 seconds → an autosave is created. Navigate away and back → a "Unsaved changes restored" toast appears and the stashed edits are shown.
- [ ] Open a remote post that has no local changes → no "Unsaved changes restored" toast appears.
- [ ] Edit a local draft, navigate away without saving → switch back and reopen it → the edits are preserved.
- [ ] Edit a local draft, immediately click the Media section (before the 30-second autosave timer fires) → switch back to Drafts and reopen the draft → the edits are present.
- [ ] Edit a remote post, immediately click the Media section → reopen the post → "Unsaved changes restored" toast appears and the edits are shown.
- [ ] Switch directly between two posts (without going through Media) → edits from the first post don't leak into the second; no duplicate autosaves.
- [ ] Edit a remote post and navigate away → the edits are stashed locally but not pushed to WordPress.
- [ ] Successfully publish or update a post → reopen it → no "Unsaved changes restored" toast (the stash was cleared on save).
- [ ] Edit a local draft → an amber dot appears next to it in the sidebar. Remote posts do not show this dot.
- [ ] Rapidly switch between several posts → no autosave data from one post appears in another; no crashes.
- [ ] Quit the app with unsaved local-draft edits → relaunch → the edits are recovered.
- [ ] Open a remote post, make edits → a "Revert" button appears in the editor header. Click it → a "Revert to Server Version?" dialog appears.
  - [ ] Click "Revert" (⌘↩) → local edits are discarded and the server content reloads.
  - [ ] Click "Cancel" → editing continues; no data is lost.
- [ ] The Revert button does not appear for local drafts.
- [ ] The Revert button does not appear for a remote post that has not been edited.
- [ ] Trigger two toasts in quick succession (e.g. two rapid saves) → the second toast's 2-second dismiss timer is not cut short by the first toast's timer; it stays visible for its own full duration.

### 7.10 Delete / trash

- [ ] Right-click a remote post and choose Delete → a confirmation dialog appears. Confirm → the post moves to WordPress Trash (recoverable, not permanently deleted).
- [ ] Same test with a page → the page moves to Trash.
- [ ] Delete a local draft → it disappears from the sidebar and is removed from local storage.
- [ ] Delete a media item → a confirmation dialog warns that deletion is permanent. Confirm → the item is gone from both the grid and the WordPress server.
- [ ] If deletion fails (e.g. no permission, or offline) → an error alert appears; the item remains in the list.
- [ ] Click Cancel on any delete confirmation → nothing happens.

### 7.11 AI features (requires an Anthropic API key)

**Setup**
- [ ] With no API key configured: the pencil (✦) and checkmark buttons in the editor toolbar are hidden, and AI items are absent from the right-click context menu.
- [ ] Add an API key in Settings → both toolbar buttons appear and AI context menu items appear, without relaunching the app.

**Generate content**
- [ ] Click the pencil button on an empty editor → the generate dialog opens directly. On a non-empty editor → a "Replace Content?" confirmation appears first.
  - [ ] ⌘↩ confirms from the keyboard; Escape or Cancel dismisses without generating.
- [ ] Generate a post → the result includes a title and structured HTML with headings (not just plain paragraphs).
- [ ] If Claude's response is cut off by the token limit → a "Post may be cut off" dialog appears. "Get Full Version" (⌘↩) retries for a complete result; "Use What I Have" accepts the truncated version.
- [ ] Generate with web search enabled → the result is coherent and complete (not fragmented); citations don't break the output.

**Selection operations (right-click menu)**
- [ ] Select some text, right-click → Make Longer, Make Shorter, To Table, and To List appear in the context menu. Each produces a correct result when clicked.
- [ ] Deselect all text, right-click → the AI items are absent.
- [ ] The AI menu items are not hidden by macOS AutoFill or Services items that may be injected into the menu.
- [ ] Select text inside a bullet list, right-click → Make Longer/Shorter appear. The result preserves the list format.
- [ ] Click inside a table, select some cells, right-click → Make Longer/Shorter appear. The result preserves the table structure.
- [ ] Drag-select in reverse (from bottom to top) → AI menu items still appear for selections ≥ 10 characters.

**Result handling**
- [ ] AI-generated content replaces the selected text cleanly — no empty paragraphs appear before or after the inserted content. Save and check the raw HTML for stray `<p></p>` tags.
- [ ] Click Accept → the AI content is kept; click Discard → the original content is restored.
- [ ] If the AI returns tables, lists, or headings, save and fetch the raw HTML → it has proper WordPress classes (`wp-block-table`, `wp-block-list`, `wp-block-heading`, etc.).
- [ ] If Claude errors or times out → the original text is restored, an error toast appears, and the editor is not corrupted.
- [ ] Disconnect from the internet and trigger an AI operation → the error message reads as a clear "couldn't reach the Anthropic API" message, not a raw NSURLError string.
- [ ] Trigger an AI operation via the right-click menu on one selection, then — while the result bar is still showing — right-click a different selection and trigger another AI operation. Only one Accept/Discard bar should be interactive; pressing Return or Escape does not double-fire.

**AI result bar**
- [ ] The Accept/Discard bar floats above the Quill window but does not float above other apps when you switch away from Quill.
- [ ] The bar has no rectangular shadow artifact around it.
- [ ] Both buttons are clearly visible in light mode and dark mode.
- [ ] Trigger the AI result bar, then type in the sidebar search field → the bar stays visible and correctly positioned (doesn't disappear or duplicate).

**Style guide**
- [ ] In Settings, select sample posts → a style guide is generated. Re-save with the same sample posts → no new Claude call is made. Change the site URL → sample posts and style guide are cleared.

**Post evaluation**
- [ ] Click the checkmark button in the editor toolbar → a panel appears with a summary and a list of findings.
- [ ] Click a finding card → the corresponding sentence in the editor is selected and scrolled into view (the full sentence, not just a few words).
- [ ] If a style guide is saved, evaluation findings that match the author's established voice should not appear (e.g. intentionally conversational tone not flagged).
- [ ] The number of findings is reasonable (5–12 for a typical post); clicking every finding navigates to the correct sentence.
- [ ] The checkmark button shows an active/highlighted state while the evaluation panel is open.
- [ ] The checkmark button is disabled (non-clickable) while the evaluation is running.
- [ ] Click evaluate, then immediately switch to another post → the old evaluation result does not appear for the new post.

### 7.12 Settings panel & preferences

- [ ] Open the settings panel for a **post** → it shows categories, tags, slug, excerpt, and discussion. For a **page** → it shows parent page, slug, and discussion only (no categories, tags, or excerpt).
- [ ] In the category list, checked categories appear first (alphabetical), then unchecked (alphabetical). This ordering holds when filtering by search and after toggling a category on/off.
- [ ] Selected tag chips above the search box are in alphabetical order; unselected tags in the dropdown are also alphabetical.
- [ ] The amber accent color is used throughout the settings panel.
- [ ] Preferences opens from both the app menu (⌘,) and any in-app settings button. The sample post picker is populated (not empty).

### 7.13 Window / appearance

- [ ] In light mode, the sidebar, panels, and editor have the correct warm off-white tones. In dark mode, they use the correct dark tones. Title and breadcrumb bars should be white in dark mode (this is an open TODO — verify current state).
- [ ] With the app open, toggle dark mode in System Settings → the editor, toolbar, and sidebar all switch immediately without relaunching.
- [ ] The boundaries between sidebar/editor and editor/settings-panel render as subtle gradient transitions, not hard lines.
- [ ] Enter and exit full screen → the title bar color remains stable.
- [ ] The title field and top border spacing look correct (no extra gaps or overlap).
- [ ] The app icon appears in the Dock and in the About window.
- [ ] On launch, a "Loading editor…" overlay appears briefly and fades out once the editor is ready. It should never stay visible permanently.
- [ ] In dark mode, links in the editor are visible (light blue on dark background), not unreadable dark blue.
- [ ] Switch to dark mode while the app is running → open a post → editor, toolbar, and editor-wrap all start in dark colors immediately (no white flash).

### 7.14 Context menus

- [ ] Right-click in the editor → the menu shows Cut, Copy, and Paste with correct enabled/disabled states. No macOS AutoFill, Services, or other system-injected items appear.
- [ ] Right-click in the title field → only Cut, Copy, and Paste appear. No AutoFill or Services items.
- [ ] Right-click on a misspelled word in the editor → up to 8 spelling suggestions appear above Cut/Copy/Paste with a separator. Click a suggestion → it correctly replaces the misspelled word.
- [ ] Right-click a misspelled word next to an emoji (e.g. `speling 🎉`) → the suggestion replaces only the word without corrupting the emoji or surrounding text.

### 7.15 Spell check

- [ ] Click the "ABC" toolbar button → misspelled words are highlighted. The highlights clear when you start editing.
- [ ] Spell check runs without crashing on the current macOS version.

### 7.16 Stats panel

- [ ] The stats area shows word count, character count, and reading time.
- [ ] Counts update as you type.
- [ ] In code view, the counts freeze. Switch back to visual mode → they refresh.
- [ ] A short post shows "1 min" reading time; longer posts round up (e.g. 400 words → 2 min).

### 7.17 Publish status helpers

- [ ] The publish button label matches the post status: draft → "Publish", published → "Update", future → "Schedule", pending → "Submit for Review", private → "Publish Privately".
- [ ] The toast message after saving reflects what happened (e.g. "Published" vs "Updated" vs "Scheduled").
- [ ] Set a future date → the status changes to "future" and the button changes to "Schedule".
- [ ] Set visibility to Private → the status changes to "private" and the button changes to "Publish Privately".

### 7.18 Find & replace

- [ ] Press ⌘F (or click the toolbar button) → the find & replace bar appears. Press Escape or the close button → it closes.
- [ ] Type in the Find field → all matches in the editor are highlighted in yellow.
- [ ] The match counter shows "1 of N" and updates as you change the query.
- [ ] Click Next/Previous → the highlight moves between matches and wraps around at the beginning/end.
- [ ] Type a replacement, click Replace → the current match is replaced and the highlight advances to the next match.
- [ ] Click Replace All → every match is replaced in one operation.
- [ ] Toggle case-sensitive mode on → a lowercase query no longer matches uppercase text.
- [ ] In code view, the find bar is hidden and no highlights appear in the textarea.

### 7.19 Embeds

- [ ] Paste a YouTube, Vimeo, or Twitter/X URL into the editor → it displays as an embed card showing the provider name and URL.
- [ ] Save and fetch the raw HTML → the embed is a valid Gutenberg `wp-block-embed` block with correct provider classes (e.g. `is-type-video is-provider-youtube wp-block-embed-youtube`).
- [ ] Close and reopen the post → the embed card still renders correctly.
- [ ] View the post on the live WordPress site → the embed renders as the expected player/widget.
- [ ] Paste an unrecognized URL → it saves as a generic embed block without provider-specific classes.
- [ ] An embed card does not show resize handles or get treated as an image.

### 7.20 Footnotes

- [ ] Right-click and choose Insert Footnote → a superscript `[1]` appears at the cursor and a matching entry appears in the footnotes list at the bottom of the document.
- [ ] Insert a second footnote → it is numbered `[2]`. The numbers follow document order.
- [ ] Delete a footnote marker from the text → its entry is automatically removed from the footnotes list.
- [ ] Press Enter inside a footnote entry → a line break (soft break) is inserted within the entry; the text is not lost or swallowed.
- [ ] Type text in a footnote list entry → the text is preserved on save.
- [ ] Click a footnote number in the list → the cursor jumps to the corresponding marker in the text.
- [ ] Click the ↩ button at the end of a footnote entry → the cursor jumps to the corresponding marker in the text.
- [ ] Save the post → fetch the raw HTML. Footnote markers should be `<sup>` elements with `id` and `data-fn` attributes; each footnote list item should end with a `↩` back-link.
- [ ] Close and reopen the post → footnotes render correctly and are editable; the ↩ button is present in each entry.
- [ ] View the post on the live WordPress site → footnote numbers are clickable links to the footnote list; back-links jump back to the inline markers.
- [ ] The footnotes `<ol>` does not receive a `wp-block-list` class (it should keep only its `wp-block-footnotes` class).
- [ ] With the cursor inside a footnote entry, toolbar buttons for block operations (headings, blockquote, code block, lists, table, image, embed) are disabled.
- [ ] With the cursor inside a footnote, pressing keyboard shortcuts for block operations (e.g. ⌘⇧7 for ordered list, ⌘⇧8 for bullet list) does nothing.
- [ ] With the cursor inside a footnote entry, Backspace and Delete keys work normally (can delete characters and merge text).
- [ ] Drag an image from Finder onto a footnote entry → an error toast appears ("Images can't be inserted in footnotes") and the image is not inserted.
- [ ] Paste rich content (containing headings, lists, or images) into a footnote → block elements are stripped; only inline text and formatting survive.

### 7.21 Update checker

- [ ] Launch the app → if a newer version is available at `cpoteet.github.io/Quill-Releases/version.json`, a banner appears in the sidebar with the new version number.
- [ ] Click "View Release" → opens the changelog URL in the default browser.
- [ ] Click the dismiss (×) button → the banner disappears and does not reappear for the same version on subsequent launches.
- [ ] If the remote version equals or is older than the current version, no banner appears.
- [ ] With no internet connection at launch, toggle the sidebar hidden and visible again (or otherwise trigger a remount) once connectivity returns → the update check runs again and a banner appears if applicable (a failed first check should not permanently skip checking for the rest of the session).

---

## Non-functional & resilience

- **Offline / flaky network:** Every network action (save, load, upload, search) shows a user-visible error when it fails. No hangs or crashes.
- **Slow network:** While saving, the save button shows a loading state and is disabled. Clicking rapidly does not submit twice.
- **Large media library:** A media grid with 500+ items scrolls smoothly, paginates correctly, and does not consume unbounded memory.
- **File permissions:** Credential and AI settings files are stored with restricted permissions (only the current user can read them).
- **Crash recovery:** Force-quit the app mid-edit → relaunch → local drafts and autosaved edits are recovered.
- **Typing performance:** On a large document, typing remains responsive (content transforms run on a debounce, not on every keystroke).
- **Security:** Pasting or loading HTML with `<script>` tags or `onerror=` attributes does not execute any scripts. AI-generated HTML is inserted as content only.
- **Thumbnail bandwidth:** The media grid loads small thumbnail images (a few KB), not full-resolution originals. Verify with a network proxy on a grid of large images.
- **Taxonomy caching:** On the second app launch with the same site URL, no `/categories` or `/tags` network requests are made (served from a local cache). Changing the site URL triggers a fresh fetch.

---

## Regression matrix — "known gotchas" guards

Each row is a documented gotcha from `CLAUDE.md`. ✅ = automated test, 👁 = manual verify.

| # | Gotcha | Guard |
|---|---|---|
| 1 | Pages omit `categories`/`tags` | ✅ `WPPostDecodingTests.pageOmittingCategoriesAndTagsDefaultsToEmpty` |
| 2 | `WPPost.type` routing posts vs pages | ✅ `WPPostDecodingTests` + 👁 §7.7 |
| 3 | Scheduling uses `date_gmt` not `date` | ✅ `PostPayloadTests.schedulingUsesDateGmtKeyNotDate` + 👁 §7.7 |
| 4 | Media dimensions as floats | ✅ `WPMediaDecodingTests.floatDimensionsDecodeToInt` |
| 5 | `slug` omitted when empty | ✅ `PostPayloadTests.nilSlugOmitsKeyFromJSON` + 👁 §7.7 |
| 6 | Trash `force=false` vs media `force=true` | ✅ `WordPressClientTests` + 👁 §7.10 |
| 7 | Cancellation re-thrown, not wrapped | ✅ `WordPressClientTests.urlErrorCancelledRethrowsAsCancellationError` |
| 8 | `searchLinks` ignores sub-failures | ✅ `WordPressClientTests.searchLinks*` |
| 9 | Web-search response joined across blocks | ✅ `AnthropicClientTests.multipleTextBlocksAreJoinedInOrder` |
| 10 | Web-search preamble before `TITLE:` | ✅ `AIPromptBuilderTests.webSearchPreambleGluedDirectlyToTitle` |
| 11 | AI prompt must name HTML elements | ✅ `AIPromptBuilderTests.generatePostPromptNamesHTMLElements` |
| 12 | `toWordPressHTML` transforms (all rows) | ✅ JS editor tests + 👁 §7.3 |
| 12a | Empty blockquote `<cite>` stripped on save | ✅ JS `empty cite is stripped` + 👁 §7.3 |
| 13 | List `<p>` unwrap only single-child | ✅ JS `multi-child <li> is left untouched` |
| 14 | Table thead promotion / figure wrap | ✅ JS table tests |
| 15 | Style-guide regeneration rules | 👁 §7.11 |
| 16 | Curly quotes in Swift strings | ✅ `DraftStoreTests.unicodeAndEmojiRoundTrip` + JS `unicode and emoji in text are preserved` + 👁 §7.3 |
| 17 | Autosave restore toast not spurious | 👁 §7.9 |
| 18 | Conflict baseline refresh (no false positive) | 👁 §7.8 |
| 19 | Selection-anchored link popover + sizing | 👁 §7.5 |
| 20 | `AIResultPanel` child-window / shadow / button style | 👁 §7.11 |
| 21 | AI insert at block boundaries (no empty `<p>`) | 👁 §7.11 |
| 22 | Media grid `Color.clear` layout | 👁 §7.2 |
| 23 | Context-menu AutoFill leakage | 👁 §7.14 |
| 24 | Sidebar toggle hides panel and keeps button visible | 👁 §7.2 |
| 24 | macOS 26 spell-check KVC crash | 👁 §7.15 |
| 25 | Ephemeral session (no keychain prompts) | 👁 §7.1 |
| 26 | Sidebar not `List`; layout not `NavigationSplitView` | 👁 §7.2 |
| 27 | `JSONFileStore` writes chmod 600 + atomic | ✅ `JSONFileStoreTests.savedFileHasChmod600` |
| 28 | `AppSupportDirectory` override isolation | ✅ `CredentialsStoreTests.appSupportOverrideKeepsFilesInTempDir` |
| 29 | AI selection ops via right-click, gated on `hasTextSelection` | 👁 §7.11 + 👁 §7.14 |
| 30 | Accepted AI result is Gutenberg-transformed | 👁 §7.11 |
| 31 | `appState.posts` list has empty content (`_fields` filter) | ✅ `WordPressClientTests.fetchAllPostsRequestIncludesFieldsFilter` + `fetchPostRequestOmitsFieldsFilter` + `WPPostDecodingTests.missingContentAndExcerptDefaultToEmpty` |
| 32 | `thumbnailURL` used in grids, not full-res `sourceURL` | ✅ `WPMediaDecodingTests.thumbnailURL*` + 👁 §7.2 |
| 33 | External link navigation restricted to http/https/mailto | ✅ `EditorCoordinatorTests` (all 7) + 👁 §7.5 |
| 34 | `uploadMedia` streams from file, no RAM buffering | ✅ `WordPressClientTests.uploadMediaStreamsFromFileNotHttpBody` + 👁 §7.4 |
| 35 | Code view entity escaping (< & > " in text/attrs) | ✅ `formatHTML — entity escaping` (5 JS tests) + 👁 §7.6 |
| 36 | Block comments preserved by `formatHTML` (nodeType 8) | ✅ `formatHTML — HTML comments` (5 JS tests) + 👁 §7.6 |
| 37 | Stats freeze in code view; refresh on exit | ✅ `countStats` (8 JS tests) + 👁 §7.16 |
| 38 | Find & replace decorations don't re-fire `update` | ✅ `findMatches` (7 JS tests) + 👁 §7.18 |
| 39 | Embed figure passes through, not treated as image | ✅ JS embed tests + 👁 §7.19 |
| 40 | Footnote markers renumbered by `toWordPressHTML` | ✅ JS footnote tests + 👁 §7.20 |
| 41 | Footnotes list excluded from `wp-block-list` | ✅ JS `footnotes list does not get wp-block-list` |
| 42 | `FootnotesList`/`FootnoteItem`/`FootnoteMarker` parse priority | 👁 §7.20 (load existing post with footnotes) |
| 43 | `FootnoteSync` deletes list entry when marker removed | 👁 §7.20 |
| 44 | Footnote backref: `sup` gets `id="ref-fn-…"`, list item gets `<a class="footnote-backref">` | ✅ `toWordPressHTML — footnote backrefs` (3 JS tests) + 👁 §7.20 |
| 45 | Non-image media shows file icon in sidebar cell and "Preview unavailable" in detail view; alt text hidden | 👁 §7.2 |
| 46 | Evaluation `ANCHOR:` field parsed to `finding.anchor`; omission → `nil` | ✅ `EvaluationParserTests.anchorFieldIsParsedIntoFinding` + `.anchorFieldIsNilWhenOmitted` |
| 47 | Classic (pre-Gutenberg) content gets wpautop treatment | ✅ `WPPostDecodingTests.classicContent*` (10 tests) |
| 48 | HTML entities in post/media titles decoded for display | ✅ `WPPostDecodingTests.decodes*` + `.noEntitiesPassthrough` (5 tests) |
| 47 | Style guide injected into evaluation prompt when non-nil/non-empty | ✅ `EvaluatePostPromptTests.promptIncludesStyleGuideWhenProvided` + `.promptOmitsStyleGuideBlockWhenNil` |
| 48 | `stripHTML` decodes typographic entities (smart quotes, em/en dash, ellipsis) | ✅ `EvaluatePostPromptTests.promptDecodesSmartQuoteEntities` + `.promptDecodesTypographicDashAndEllipsis` |
| 49 | Empty state flash before first load (`hasLoadedList`/`hasLoadedMedia`) | ✅ `AppStateLoadingTests` (2 tests) + 👁 §7.1 |
| 49 | Evaluation task cancelled on post switch — stale result cannot appear for new post | 👁 §7.11 (switch posts mid-evaluation) |
| 50 | Confirmation sheets (Revert / Conflict / Replace / Truncation) have ⌘↩ on primary action | 👁 §7.8 + §7.9 + §7.11 |
| 51 | HR → `wp-block-separator has-alpha-channel-opacity` | ✅ JS `hr gains wp-block-separator class` + `hr class is idempotent` |
| 52 | Tiptap table artifacts stripped (style, colgroup, default colspan/rowspan, p-in-cell) | ✅ JS table cleanup tests (3 tests) |
| 53 | AI Make Longer/Shorter uses list/table-specific prompts when context detected | ✅ `AIPromptBuilderTests.makeLongerWithListContextUsesListInstruction` + 3 siblings + 👁 §7.11 |
| 54 | AI selection detection uses ProseMirror state (handles reversed/table selections) | 👁 §7.11 (select in table, right-click) |
| 55 | AI result panel clamps to webview bounds, fallback for invalid rects | 👁 §7.11 |
| 56 | Footnote content restricted to inline-only (no images, block elements, keyboard shortcuts) | 👁 §7.20 |
| 57 | Image drops rejected in footnotes with error toast | 👁 §7.20 |
| 58 | Paste in footnotes strips block elements to inline text | 👁 §7.20 |
| 59 | Update checker version comparison handles all semver cases | ✅ `UpdateCheckerTests` (7 tests) |
| 60 | Draft save failure shows error toast | 👁 §7.7 |
| 61 | `syncContentToSwift` fires after AI-generated content set | 👁 §7.11 (generate post, verify autosave captures content) |
| 62 | Backspace/Delete passthrough inside footnotes (`_fnPassthrough`) | 👁 §7.20 (delete chars in footnote entry) |
| 63 | Image caption Enter exits to paragraph below (imageCaptionExit plugin) | 👁 §7.4 (Enter in caption) |
| 64 | Blockquote Enter: splits paragraphs inside, lifts empty paragraph out | 👁 §7.3 (Enter behavior in blockquote) |
| 65 | Cite toggle button adds/removes cite node in blockquote | 👁 §7.3 (cite toggle) |
| 66 | Footnote back-arrow is `contentEditable: false` (not selectable/editable) | 👁 §7.20 (↩ not part of editable text) |
| 67 | Excerpt field does not adopt auto-generated `rendered` excerpt from WordPress | ✅ `WPPostDecodingTests.excerptText*` (4 tests) |
| 68 | `stripHTML` phantom space before punctuation after inline tags | ✅ `AIPromptBuilderTests.promptDoesNotInjectSpaceBeforePunctuationAfterInlineTags` + `.promptStripsSpaceBeforeClosingPunctuation` |
| 69 | Anchor matching tolerates whitespace differences around punctuation | ✅ `findMatchesLoose` (7 JS tests) + `fuzzyAnchorRegex` (3 JS tests) |
| 70 | Footnote Enter inserts soft break (not swallowed) | ✅ `test-editor-keyboard.js` footnote Enter test + 👁 §7.20 |
| 71 | Blockquote Enter with selection deletes selection before split | ✅ `test-editor-keyboard.js` blockquote selection test + 👁 §7.3 |
| 72 | Image toolbar scroll handler cleaned up before reattaching | 👁 §7.4 (select multiple images in sequence) |
| 73 | Image toolbar clamped below main toolbar-wrap | 👁 §7.4 (scroll image near top of viewport) |
| 74 | Cmd+click opens links (scheme-restricted via `isAllowedExternalURL`) | ✅ `EditorCoordinatorTests` + 👁 §7.5 |
| 75 | `WordPressClient` query params escape literal `+` to `%2B` | ✅ `WordPressClientTests.searchQueryPlusCharacterIsPercentEscaped` |
| 76 | AI-generated `<cite>` wrapper stripped but inner citation text kept, even across a nested inline tag | ✅ `AIPromptBuilderTests.citeTagWrapperStrippedButTextKept` + `.citeTagWithNestedInlineTagStillStripped` + `.emptyCiteTagRemovedEntirely` |
| 77 | `AnthropicClient` transport errors wrapped as `AnthropicError.networkError` with friendly offline message | ✅ `AnthropicClientTests.networkFailureWrapsAsAnthropicNetworkError` + `.networkErrorShowsFriendlyMessageWhenUnderlyingDescriptionMentionsOffline` + `.networkErrorPassesThroughUnrecognizedMessage` |
| 78 | `AnthropicClient` decodes responses with `stop_reason` omitted (Optional) | ✅ `AnthropicClientTests.missingStopReasonFieldDoesNotThrowAndIsNotTruncated` |
| 79 | MIME type lookups consolidated into `MimeType.forFile`/`forExtension` (no per-call-site drift) | ✅ `MimeTypeTests` (12 tests) |
| 80 | `SidebarView.loadAllSections`/`UpdateChecker.check` don't rerun on sidebar remount when credentials unchanged | 👁 §7.2 (toggle sidebar visibility, confirm no refetch) |
| 81 | `PostEditorView` refuses to save when the full-post load failed (`contentLoadFailed`) | 👁 §7.7 (simulate load failure, attempt save) |
| 82 | Taxonomy creation retry doesn't resubmit already-created pending names | 👁 §7.7 (create post with 2+ new tags, force one to fail, retry save) |
| 83 | `AIResultPanel` event monitor not double-registered across repeated `show()` calls | 👁 §7.11 (trigger AI op twice via right-click without dismissing) |
| 84 | Toast dismiss timer restarts on every `presentToast()` call via a bumped `toastToken`, even when two consecutive toasts share identical text (keying `.task(id:)` on the message string alone couldn't detect that case) | 👁 §7.9 (drop 2+ images at once, confirm each "Image inserted" toast shows for a full 2s) |
| 85 | `PostEditorView.loadItem()` bails out of its catch block on a stale/cancelled load instead of writing `contentLoadFailed`/`saveError` for whichever post is now displayed | 👁 §7.7 (switch away from a post before its full-content fetch fails) |
| 86 | `saveError` is reset at the start of every `loadItem()` call so a stale error banner from a previous failed load doesn't persist over a subsequently-opened post or draft | 👁 §7.7 (fail a post load, then open a different post/draft that loads fine) |
| 87 | `UpdateChecker.check()` throws on transport/decode failure so `hasCheckedForUpdate` only latches on success, matching `lastLoadedCredentials`'s retry-on-failure semantics | 👁 §7.21 (simulate a network failure on first check, confirm a later remount retries) |
| 88 | `APIError`/`AnthropicError` share one `NetworkErrorHeuristics.isConnectivityFailure` substring check instead of two independently-maintained copies | ✅ `AnthropicClientTests.networkErrorShowsFriendlyMessageWhenUnderlyingDescriptionMentionsOffline` + `.networkErrorPassesThroughUnrecognizedMessage` |
| 89 | Existing galleries loaded from a post survive as an atomic `galleryBlock` node (not the `_rawHTML` verbatim safety net) — an unrelated visual edit elsewhere no longer silently drops the gallery on save | ✅ `WPPostDecodingTests.blockGalleryContentSurvivesEditorHTML` + JS `toWordPressHTML — gallery` (9 tests) + `galleryBlock` load/round-trip tests (8 tests) + 👁 §7.4 |
| 90 | `galleryBlock.parseHTML` never returns `false`/degrades to standalone images for a gallery it can partially handle (e.g. captions) — only for zero-image-figure input | ✅ `galleryBlock` — verbatim re-render tests (2 tests, caption preserved via `sourceHTML`) |
| 91 | `toWordPressHTML`'s upfront strip of pre-existing `wp:embed`/`wp:gallery`/`wp:image` comments uses a non-greedy attrs match (`[\s\S]*?-->`) so it can't span past the first comment's close and delete image figures between two adjacent comments with no newline separator (a loaded gallery's `sourceHTML` has no such guarantee, unlike this function's own freshly-wrapped output), and stays immune to a stray `\r` before a comment's own `-->` (JS `.` excludes all line terminators, not just `\n`, so a `.*?` group — unlike `[\s\S]*?` — would fail to match at all in that case) | ✅ `toWordPressHTML — gallery.'stripping pre-existing wp:image comments does not consume the images between them'` + `.'stripping a pre-existing wp:gallery comment works even with a CR before its closing -->'` |
| 92 | Tiptap's default gap-cursor widget (black horizontal bar) is restyled via CSS to the app's blue vertical caret wherever the caret sits next to an atomic `galleryBlock`/`embedBlock` node — fixed at the CSS layer, not by inserting/stripping a synthetic trailing paragraph in the doc model | ✅ `gap-cursor styling` (1 test) + `window.insertGallery bridge function.'inserting at the end of the doc does not synthesize a trailing paragraph'` + 👁 §7.4 |
| 93 | Gallery `linkTo: 'media'` links to the image's `fullUrl` (true full-resolution original), not its display-size `url` — a non-full Size selection no longer silently links thumbnails to themselves instead of the original file | ✅ `galleryBlock — insert and render.'linkTo media links to fullUrl (true original), not the display-size url'` + `.'linkTo media falls back to url when fullUrl is absent'` + 👁 §7.4 |
| 94 | `WPMedia.sizedURL(for:)` falls back to `sourceURL` when the matched size entry's `source_url` decoded to an empty string (not just when the entry is absent) — matches the existing `thumbnailURL` guard for the same WordPress API quirk | ✅ `WPMediaDecodingTests.sizedURLFallsBackToSourceURLWhenMatchedSizeHasBlankURL` |
| 95 | `GallerySheet`'s Upload button adds the newly-uploaded image directly to the gallery's `selected` list, not just the media grid — matches the evident purpose of an inline upload button inside a gallery-building flow | 👁 §7.4 (click Upload, confirm the new image is already checkmarked/listed in Selected without an extra click) |
| 96 | Single (non-gallery) image's "Link to Full Image" toggle: `ResizableImage.linkTo`/`linkHref` attrs parse from a pre-existing `<a>` wrapper on load (figure-wrapped **and** bare `img[src]`/classic-content markup), require a non-empty `href` to count as linked, round-trip through `toWordPressHTML` on save, and coexist with alignment/custom class/`mediaId` | ✅ `test-editor-keyboard.js` `image link-to-full-size` (7 tests) + 👁 §7.4 |
| 97 | Image toolbar's "Link to Full Image" button is always available (not hidden for images with no `mediaId` or whose media sizes lack a `"full"` entry) — toggling on falls back to the image's current `src` when no media-library size data is known, so an already-linked externally-sourced image is never stuck with an unreachable toggle; toggling off also clears the stale `linkHref` | 👁 §7.4 (select a drag-dropped/external image with no media ID, confirm the Link to Full Image button is visible and toggles correctly) |
| 98 | `EditorCoordinator.mediaSizesDict(for:)` synthesizes a `"full"` size entry from `media.sourceURL` when WordPress's `media_details.sizes` omits one (a common API shape) — mirrors the existing `WPMedia.sizedURL(for:)` fallback for the same quirk, so the Full-size preset button and Link to Full Image toggle aren't silently disabled for images that have other sizes but no explicit `"full"` entry | ✅ `EditorCoordinatorTests.mediaSizesDictAddsFullFallbackWhenSizesOmitsIt` + `.mediaSizesDictPreservesExistingFullEntry` + `.mediaSizesDictFallsBackToSourceURLWhenNoSizesAtAll` + `.mediaSizesDictReturnsNilWhenSourceURLIsEmpty` |

---

## What's not yet automated

The automatable Swift and JS layers are covered. The remaining gaps require a live WordPress site or SwiftUI UI test infrastructure and cannot be run headlessly:

- **onDisappear flush (§7.9):** The `onDisappear` closure fires in the SwiftUI view lifecycle, which can't be triggered from Swift Testing. Manual steps cover local-draft-to-Media and remote-post-to-Media scenarios.
- **Preview URL on plain-permalink sites (§7.8):** `previewURL` logic is fully unit-tested; the manual step verifies the resulting URL actually loads in the browser on a real site.
- **Insert-image picker file filter (§7.4):** `NSOpenPanel.allowedContentTypes` is an AppKit call; the panel itself can only be verified by running the app.
- **UI flows, SwiftUI/AppKit rendering, WKWebView bridge interactions, conflict detection, autosave restoration, AI result panel visual correctness:** Documented in §7, run before each release.
