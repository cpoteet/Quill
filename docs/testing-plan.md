# Quill — Test Suite Reference

_Last updated: 2026-06-01 — 192 Swift tests + 37 JS editor tests, all passing._

This document is the authoritative reference for Quill's automated test suite and manual testing checklists. It covers how to run every test, what each test covers, and which manual checks to run before a release.

---

## Running the tests

### Full suite (recommended after every code change)

```bash
./test.sh
```

`test.sh` runs both test layers in sequence and prints a pass/fail summary:

1. **Swift tests** — `swift test` (all 164 tests across 13 suites)
2. **JS editor tests** — `node --test Scripts/test-editor.js` (40 tests via Node's built-in runner + jsdom)

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

## Swift test suite (164 tests)

Framework: `swift-testing`. Target: `Tests/QuillTests/`. Support files: `Tests/QuillTests/Support/`.

### Suite summary

| Suite | File | Tests | What it covers |
|---|---|---|---|
| `WPPostDecodingTests` | `WPPostDecodingTests.swift` | 10 | `WPPost` JSON decoding, optional-field defaults |
| `WPMediaDecodingTests` | `WPMediaDecodingTests.swift` | 7 | `WPMedia`/`MediaDetails`/`MediaSize` float-dimensions gotcha |
| `PostPayloadTests` | `PostPayloadTests.swift` | 11 | `PostPayload` encoding, scheduling key names, nil omission |
| `CredentialsTests` | `CredentialsTests.swift` | 4 | `Credentials.basicAuthHeader` base64 encoding |
| `WordPressClientTests` | `WordPressClientTests.swift` | 37 | URL construction, HTTP error mapping, `searchLinks`, auth headers |
| `JSONFileStoreTests` | `JSONFileStoreTests.swift` | 8 | Round-trip, chmod 600, atomic write, nil-on-absent |
| `KeychainStoreTests` | `KeychainStoreTests.swift` | 10 | Credentials persistence, `AppSupportDirectory`, `AISettingsStore` |
| `DraftStoreTests` | `DraftStoreTests.swift` | 13 | Local draft CRUD, ordering, unicode, non-existent ID safety |
| `AutosaveStoreTests` | `AutosaveStoreTests.swift` | 8 | Autosave CRUD, one-per-post, `serverModified`, `savedAt` ordering |
| `TaxonomyCacheTests` | `TaxonomyCacheTests.swift` | 12 | Category/tag cache, TTL boundary, replace semantics, collision guard |
| `AppDatabaseTests` | `AppDatabaseTests.swift` | 2 | Migration idempotency, old-schema `type` column backfill |
| `AIPromptBuilderTests` | `AIPromptBuilderTests.swift` | 24 | `parseGenerateResponse` edge cases, system prompt, all prompt builders |
| `AnthropicClientTests` | `AnthropicClientTests.swift` | 18 | Request headers, web search, multi-block joining, error handling |
| `PostItemTests` | `AppStateTests.swift` | 10 | `PostItem.id`, `.title`, `.statusBadge` computed properties |
| `SidebarSectionTests` | `AppStateTests.swift` | 8 | `SidebarSection.icon` and `.shortTitle` for all cases |
| `AppStateFilteredItemsTests` | `AppStateTests.swift` | 10 | `AppState.filteredItems` per section, search filtering |

---

### 1. Model decoding — `WPPostDecodingTests` (10 tests)

File: `Tests/QuillTests/WPPostDecodingTests.swift`

Guards the `WPPost` decoding path, which contains `decodeIfPresent` defaults that have caused production bugs.

| Test | What it checks |
|---|---|
| `fullPostDecodesAllFields` | All standard fields decode from a complete JSON fixture |
| `pageOmittingCategoriesAndTagsDefaultsToEmpty` | Pages endpoint omits `categories`/`tags` → both default to `[]` without throwing |
| `missingTypeDefaultsToPost` | `type` absent → `"post"` |
| `missingFeaturedMediaDefaultsToZero` | `featured_media` absent → `0` |
| `missingDateGmtDefaultsToEmptyString` | `date_gmt` absent → `""` |
| `missingParentDefaultsToZero` | `parent` absent → `0` |
| `missingCommentStatusDefaultsToOpen` | `comment_status` absent → `"open"` |
| `contentRawPreferredOverRendered` | `content.raw` decoded when present; `rendered` also decoded |
| `missingRequiredFieldThrows` | Omitting `id` → decoding throws (required field guard) |
| `futureStatusDecodes` | `status: "future"` decodes without error |

---

### 2. Model decoding — `WPMediaDecodingTests` (7 tests)

File: `Tests/QuillTests/WPMediaDecodingTests.swift`

Guards the float-dimensions gotcha: WordPress returns `width`/`height` as JSON floats (`2560.0`) which Swift's `Int` decoder rejects without the try-Int-then-Double fallback.

| Test | What it checks |
|---|---|
| `integerDimensionsDecode` | `"width": 2560` → `Int` |
| `floatDimensionsDecodeToInt` | `"width": 2560.0` → `Int` via the fallback path (regression guard) |
| `missingMediaDetailsIsNil` | `media_details` absent → `nil`, no throw |
| `missingTitleDefaultsToEmpty` | `title` absent → empty `RenderedString` |
| `sizesMapDecodes` | `sizes` dict with named sizes → `[String: MediaSize]` |
| `sizesDimensionsAsFloatsDecode` | Float `width`/`height` inside `sizes` entries also decode |
| `malformedSizesDoesNotCrash` | `sizes: []` (wrong type) → `try?` swallows it, whole `WPMedia` still decodes |

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

### 5. Networking — `WordPressClientTests` (37 tests)

File: `Tests/QuillTests/WordPressClientTests.swift`
Support: `Tests/QuillTests/Support/MockURLProtocol.swift`

`@Suite(.serialized)` — runs sequentially because `MockURLProtocol.requestHandler` is a shared static. Uses `URLSessionConfiguration.ephemeral` with `MockURLProtocol` as the protocol class.

#### URL & request construction (14 tests)

| Test | What it checks |
|---|---|
| `fetchPostsDecodesList` | `fetchPosts` decodes a list of posts |
| `fetchPostsIncludesRequiredQueryParams` | `per_page`, `page`, `context=edit`, `status=…` all present |
| `fetchPagesHitsPagesEndpoint` | `/wp-json/wp/v2/pages`, not `/posts` |
| `createPostUsesPostMethodWithJsonContentType` | `POST /posts`, `Content-Type: application/json` |
| `updatePostUsesPutMethodOnPostsId` | `PUT /posts/{id}` |
| `createPageUsesPostMethodOnPagesEndpoint` | `POST /pages` |
| `updatePageUsesPutMethodOnPagesId` | `PUT /pages/{id}` |
| `authorizationHeaderIncludedInRequests` | `Authorization: Basic …` on all requests |
| `uploadMediaSetsContentTypeFromMimeType` | `Content-Type` matches passed mime type |
| `uploadMediaSetsContentDispositionWithFilename` | `Content-Disposition` includes `filename="…"` |
| `uploadMediaSpacesInFilenameArePercentEncoded` | Spaces in filenames percent-encoded in `filename*` part |
| `deleteMediaSendsDeleteWithForceTrueQuery` | `DELETE /media/{id}?force=true` (permanent — vs trash's `force=false`) |
| `createAutosaveSendsToPostAutosavesEndpoint` | `POST /posts/{id}/autosaves` |
| `createPageAutosaveSendsToPageAutosavesEndpoint` | `POST /pages/{id}/autosaves` |

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

#### `searchLinks` (7 tests)

| Test | What it checks |
|---|---|
| `searchLinksReturnsMergedResults` | All three sub-requests succeed → merged list |
| `searchLinksIgnoresSubrequestFailures` | Media/term failure → others still returned |
| `searchLinksAllSubrequestsFailReturnsEmptyArray` | All fail → `[]`, no throw |
| `searchLinksPostsFailWhileTermsSucceed` | Posts sub-request fails → terms/media still returned |
| `searchLinksPageSubtypeMapsToPageType` | `subtype == "page"` → `.page` result type |
| `searchLinksTagSubtypeMapsToTagType` | `subtype == "tag"` → `.tag` result type |
| `searchLinksUnknownTermSubtypeFallsToCategory` | Unknown term subtype → `.category` |

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

### 7. Storage — `KeychainStoreTests` (10 tests)

File: `Tests/QuillTests/KeychainStoreTests.swift`

`@Suite(.serialized)` — uses `AppSupportDirectory.override` (a global) so only one test at a time writes to the temp dir. Override is set in `init` and cleared in `deinit`.

#### `KeychainStore` / credentials (3 tests)

| Test | What it checks |
|---|---|
| `saveAndLoad` | Credentials round-trip through `KeychainStore` |
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

### 12. AI — `AIPromptBuilderTests` (24 tests)

File: `Tests/QuillTests/AIPromptBuilderTests.swift`

Pure function tests — no network, no async. `parseGenerateResponse` has been patched twice for real production bugs; these tests pin every edge case.

#### `parseGenerateResponse` (11 tests)

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

#### `systemPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `systemPromptWithoutStyleGuide` | `nil` guide → no style block |
| `systemPromptWithEmptyStyleGuideExcludesStyleBlock` | Empty string guide → same as nil |
| `systemPromptWithStyleGuideIncludesIt` | Non-empty guide appended to prompt |

#### `generatePostPrompt` & `operationPrompt` (6 tests)

| Test | What it checks |
|---|---|
| `generatePostPromptNamesHTMLElements` | Prompt contains `<h2>`, `<h3>`, `<p>`, `<ul>`, `<li>` (prevents headings-only-p regression) |
| `generatePostPromptIncludesUserPrompt` | User's prompt string embedded |
| `operationPromptIncludesSelectedHTML` | Selected HTML embedded after "Content to transform:" |
| `makeLongerInstructionPresent` | "longer" in `makeLonger` operation prompt |
| `makeShorterInstructionPresent` | "shorter" in `makeShorter` operation prompt |
| `convertToTableMentionsTableTags` | Table-related tags in `convertToTable` prompt |
| `convertToListMentionsListTags` | List-related tags in `convertToList` prompt |

#### `styleGuideGenerationPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `styleGuidePromptNumbersSamples` | `--- Sample 1 ---` / `--- Sample 2 ---` numbering |
| `styleGuidePromptWithEmptySamples` | 0 samples → no crash, empty content |
| `styleGuidePromptWordLimit` | 150-word limit mentioned in prompt |

---

### 13. AI — `AnthropicClientTests` (18 tests)

File: `Tests/QuillTests/AnthropicClientTests.swift`
Support: `Tests/QuillTests/Support/AnthropicMockURLProtocol.swift`

`@Suite(.serialized)` — uses its own `AnthropicMockURLProtocol` subclass with a separate `static var requestHandler` to avoid races with `WordPressClientTests`' `MockURLProtocol`. Body reconstruction: URLSession clears `httpBody` in URLProtocol; `AnthropicMockURLProtocol.startLoading()` reads the body from `httpBodyStream`.

#### Request headers (3 tests)

| Test | What it checks |
|---|---|
| `requestHasApiKeyHeader` | `x-api-key` header set |
| `requestHasVersionHeader` | `anthropic-version: 2023-06-01` |
| `requestHasContentTypeHeader` | `content-type: application/json` |

#### Beta headers & web search (4 tests)

| Test | What it checks |
|---|---|
| `betaHeaderWithoutWebSearchContainsCachingOnly` | `anthropic-beta` contains `prompt-caching-2024-07-31` only |
| `betaHeaderWithWebSearchIncludesWebSearchBeta` | `web-search-2025-03-05` added when web search on |
| `toolsAbsentWhenWebSearchOff` | `tools` key absent from body |
| `toolsPresentWhenWebSearchOn` | `tools` array contains `web_search_20250305` |

#### Prompt caching (1 test)

| Test | What it checks |
|---|---|
| `systemBlockHasCacheControlEphemeral` | System block has `cache_control: {"type":"ephemeral"}` |

#### Response handling (7 tests)

| Test | What it checks |
|---|---|
| `singleTextBlockReturnsText` | Single `type:"text"` block → its text |
| `multipleTextBlocksAreJoinedInOrder` | Multiple text blocks → joined in order (web-search fragmentation gotcha) |
| `nonTextBlocksExcludedFromJoin` | `server_tool_use` and `web_search_tool_result` blocks excluded |
| `allNonTextBlocksThrowsNoTextContent` | All non-text blocks → `AnthropicError.noTextContent` |
| `truncatedTrueWhenStopReasonIsMaxTokens` | `stop_reason: "max_tokens"` → `truncated: true` |
| `truncatedFalseWhenStopReasonIsEndTurn` | `stop_reason: "end_turn"` → `truncated: false` |
| `nonOkStatusThrowsHttpError` | Non-200 → `AnthropicError.httpError(code, body)` |

#### Error handling (3 tests)

| Test | What it checks |
|---|---|
| `httpErrorPreservesBodyString` | Error body string preserved |
| `malformedJsonThrows` | Garbage JSON → decoding throws |
| `networkFailureThrows` | `URLError` from mock → error surfaced |

---

## JS editor tests (37 tests)

File: `Scripts/test-editor.js`
Transforms file: `Sources/QuillKit/Resources/editor-transforms.js`

Tests run under Node's built-in test runner with jsdom for DOM support. They test the `toWordPressHTML` and `extractAlignment` functions extracted from `editor.html` into `editor-transforms.js`.

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

### `toWordPressHTML` — lists (3 tests)

| Test | What it checks |
|---|---|
| `ul gains wp-block-list` | `<ul>` → `wp-block-list` |
| `ol gains wp-block-list` | `<ol>` → `wp-block-list` |
| `task list does NOT gain wp-block-list` | `data-type="taskList"` → no class added |

### `toWordPressHTML` — list item `<p>` unwrapping (3 tests)

| Test | What it checks |
|---|---|
| `single-child <p> inside <li> is unwrapped` | `<li><p>text</p></li>` → `<li>text</li>` |
| `multi-child <li> is left untouched` | Two `<p>` in one `<li>` → unchanged |
| `task item div>p is unwrapped` | Task item inner `<p>` stripped to `<div>text</div>` |

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

### `toWordPressHTML` — images (7 tests)

| Test | What it checks |
|---|---|
| `data-media-id produces wp-image-{id} class on img` | `data-media-id="42"` → `class="wp-image-42"` |
| `img.alignleft is wrapped in figure.wp-block-image.alignleft` | Alignment class causes figure wrap |
| `img.alignright is wrapped in figure.wp-block-image.alignright` | Right alignment |
| `img.aligncenter is wrapped in figure.wp-block-image.aligncenter` | Center alignment |
| `align class is removed from img after wrapping in figure` | `alignleft` removed from `<img>` once in `<figure>` |
| `image with both alignment and media-id gets figure wrapper and wp-image class` | Both transforms applied together |
| `image with no alignment and no media-id is untouched` | Plain `<img>` → no figure wrap |

### `toWordPressHTML` — tables (5 tests)

| Test | What it checks |
|---|---|
| `table is wrapped in figure.wp-block-table` | `<table>` → `<figure class="wp-block-table">` |
| `all-th first row is promoted from tbody to thead` | All-`<th>` row moves to `<thead>` |
| `mixed th/td first row is NOT promoted to thead` | Mixed `<th>`/`<td>` → no promotion |
| `table already having thead is not modified` | Pre-existing `<thead>` → untouched |
| `table already inside wp-block-table is not double-wrapped` | Idempotency: one `wp-block-table` after two passes |

### `toWordPressHTML` — idempotency & edge cases (3 tests)

| Test | What it checks |
|---|---|
| `full document is idempotent across all transform types` | `toWordPressHTML(toWordPressHTML(x)) == toWordPressHTML(x)` for all element types |
| `empty paragraph is stable` | `<p></p>` → `<p></p>` |
| `unicode and emoji in text are preserved` | café, 🎉, curly quotes survive |

---

## Manual / functional test checklists

These cover SwiftUI/AppKit behavior, WKWebView interaction, and end-to-end flows that aren't economically unit-testable. Run against a **real WordPress test site** (or a local `wp-env`/Docker WordPress) using an Application Password. Build with `./build.sh` and `open Quill.app` before each pass.

> Recommendation: keep a disposable WordPress instance so destructive tests (delete, trash, publish) don't pollute a real site.

### 7.1 Authentication & onboarding

- [ ] First launch with no credentials → preferences/login prompt shown.
- [ ] Valid site URL + username + app password → connects, lists load.
- [ ] **Edge:** site URL without scheme (`example.com`) — does it normalize or
      fail clearly?
- [ ] **Edge:** site URL with trailing slash, with subdirectory install
      (`example.com/blog`), with non-standard port.
- [ ] **Edge:** wrong password → `401` surfaced as a readable error, not a
      silent failure.
- [ ] **Edge:** site that isn't WordPress / REST API disabled → clear error.
- [ ] App password with spaces pasted verbatim → auth succeeds (ties to §1.5).
- [ ] No keychain prompt appears during normal network use (ephemeral-session
      gotcha).
- [ ] Credentials persist across relaunch; changing the site URL updates the
      lists and (per gotcha) clears AI sample post IDs.

### 7.2 Sidebar, lists, navigation

- [ ] Posts / Pages / Local Drafts / Media sections each load and render.
- [ ] Selection highlight uses the custom (non-blue) style — confirms the
      `ScrollView+LazyVStack` (not `List`) gotcha holds.
- [ ] Search filters the current section case-insensitively; clearing restores.
- [ ] **Empty states:** empty Posts, empty Pages, empty Drafts, empty Media each
      show the right placeholder; editor empty state says "post"/"page"/"draft"
      per active section.
- [ ] Switching to Media hides the post list/search/toolbar and shows the
      thumbnail grid (the `else` branch gotcha).
- [ ] Pagination in Posts and Media loads more on scroll; `hasMore` stops at the
      end.
- [ ] No `NavigationSplitView`/`HSplitView` chrome (no drag cursor on the
      divider) — visual confirm of the layout gotcha.

### 7.3 Editor — content & Gutenberg round-trip

- [ ] Load an existing remote post → content renders identically to WordPress.
- [ ] Type formatting: bold, italic, strike, inline code, links, headings (h1–
      h6), bullet/ordered/task lists, blockquote, code block, table.
- [ ] Save → fetch `content.raw` via REST (`?context=edit`) → matches the
      Gutenberg expected output table in `CLAUDE.md` (heading classes, list
      classes, figure-wrapped tables/images, thead promotion).
- [ ] **Round-trip stability:** load → save without editing → diff is empty (no
      drift). Then load again → still identical.
- [ ] Multi-paragraph list items survive the save unchanged (don't get
      collapsed).
- [ ] Task list checkboxes round-trip.
- [ ] **Blockquote attribution (`<cite>`):**
  - [ ] Toggling blockquote **on** auto-appends an empty cite line (subdued,
        right-aligned).
  - [ ] Typing in the cite line then saving → `<cite>` persists inside the
        blockquote and renders as a `<cite>` on WordPress.
  - [ ] Leaving the cite **blank** → the empty `<cite>` is **not** saved (no empty
        cite litters the published HTML).
  - [ ] **Enter** inside the cite exits the blockquote into a new paragraph after
        it (doesn't add a newline inside the cite).
  - [ ] **Backspace** in an empty cite deletes the cite node (doesn't delete the
        whole quote).
  - [ ] Toggling blockquote **off** removes the quote and its cite cleanly.
- [ ] Curly quotes / emoji / non-Latin scripts survive save→reload byte-exact.
- [ ] Very long post (10k+ words) — editor stays responsive; save succeeds.
- [ ] Paste from Word/Google Docs/Safari → reasonable HTML, no script injection.

### 7.4 Editor — images

- [ ] Insert image via media picker at caret → appears at correct position.
- [ ] **Hit-testing:** clicking a thumbnail in the picker grid selects the
      intended item.
- [ ] Drag image file from Finder onto editor → uploads, inserts, toast shown.
- [ ] **Edge:** drag a non-image file → ignored (the `isFileURL`/mime guard).
- [ ] **Edge:** drag multiple images at once → all upload and insert.
- [ ] **Edge:** upload failure (offline) → error surfaced, editor not corrupted.
- [ ] Resize handles appear on select; drag resizes; aspect ratio respected.
- [ ] Named WordPress sizes (thumbnail/medium/large/full) offered when the image
      has a `mediaId` and the media item is loaded; hidden otherwise
      (`setMediaSizes(id, null)` path).
- [ ] Image alignment left/center/right → wraps text correctly and saves as
      `figure.wp-block-image alignXXX`.
- [ ] Image toolbar repositions on scroll and hides on deselect (the
      `_scrollHandler` cleanup + 80ms deselect delay gotchas).
- [ ] Clicking a toolbar input doesn't dismiss the toolbar (80ms delay).
- [ ] Mime detection: insert `.jpg/.png/.gif/.webp/.heic/.tiff` → correct
      content type sent.

### 7.5 Editor — links

- [ ] Link button opens the popover anchored to the **selection rect** (not the
      toolbar button) when text is selected; anchored to the button when nothing
      selected.
- [ ] Typing a query searches posts/pages/categories/tags/media; results render
      (the `ObservableObject` re-render gotcha).
- [ ] Popover **grows** as results appear without clipping (the
      `.preferredContentSize` sizing gotcha).
- [ ] Selecting a result inserts the link; manual URL entry works.
- [ ] **Edge:** no results → empty state, no crash.
- [ ] **Edge:** search while offline → handled gracefully.

### 7.6 Editor — code view

- [ ] `</>` button appears at the far right of the toolbar.
- [ ] Clicking `</>` switches to the code textarea; all other toolbar buttons are
      disabled while in code view; the `</>` button shows the active (blue) state.
- [ ] HTML in the textarea is pretty-printed: block elements on their own lines,
      inline elements (`<strong>`, `<a>`, etc.) stay on the same line as their
      parent, `<li>` items indented inside `<ul>`/`<ol>`, table rows/cells nested,
      `<pre>` content left verbatim. Top-level blocks separated by a blank line.
- [ ] Clicking `</>` again switches back to visual mode; all toolbar buttons
      re-enable; edited HTML round-trips correctly into Tiptap.
- [ ] **Edit in code view, switch back:** make a change in the textarea (e.g. add
      a word), switch to visual — the edit is reflected in the editor.
- [ ] **Save from code view:** with code view active, use ⌘S — the saved content
      matches what was in the textarea (not stale Tiptap state).
- [ ] **Load new post while in code view:** select a different post — code view
      exits automatically and the new post loads in visual mode.
- [ ] **Dark mode:** code textarea background and text color match the editor
      background (no light flash or mis-colored panel).

### 7.7 Save / publish / draft / schedule

- [ ] **Local draft, Save Draft** → persists locally only, **no** network call
      (verify via proxy/network log); toast "Saved locally".
- [ ] **Local draft, Publish** → creates remote post, **local copy disappears
      immediately** from the Drafts list, selection moves to the new remote item,
      section switches to Posts/Pages.
- [ ] Page draft publishes to `/pages`, post draft to `/posts`.
- [ ] **Remote post, ⌘S** → updates WordPress (status `draft` stays draft).
- [ ] **Remote post, ⌘⇧P / Publish** → publishes; button label reflects state
      (`Publish` / `Update` / `Publish Draft` / `Schedule`).
- [ ] **Scheduling:** set a future date → status `future`, post scheduled;
      verify on the server the scheduled time matches (UTC `date_gmt`, **not**
      site-local `date` — the scheduling gotcha). Test a timezone-offset site.
- [ ] Reopening a scheduled post shows the correct future date in the panel
      (the `parseWPDate` round-trip, incl. the no-timezone-suffix fallback).
- [ ] Inline new category/tag names → created on save, IDs attached, appear in
      `appState.categories/tags` and the panel (the deferred-creation gotcha).
- [ ] **Edge:** taxonomy creation fails → save aborts with an error, content not
      lost.
- [ ] Slug: blank slug on a new item stays blank (doesn't inherit previous
      item's slug); editing slug then save sends it; blank slug on update
      **omits** `slug` so the server value is preserved.
- [ ] Featured image set/clear; `featured_media: 0` clears it.
- [ ] Comment status open/closed round-trips.
- [ ] Page parent picker excludes the page itself; saving sets `parent`.

### 7.8 Conflict detection

- [ ] Open a remote post in Quill. Edit it on the server (or via another client)
      so `modified` changes. Save in Quill → **Conflict Detected** alert.
  - [ ] "Keep Local" → force-saves, overwrites server.
  - [ ] "Use Server" → reloads server content, discards local edits.
  - [ ] "Cancel" → keeps editing, no data lost.
- [ ] **False-conflict guard:** open a post, immediately save without server
      changes → **no** conflict alert.
- [ ] **Preview-induced baseline refresh:** preview a draft post, then save →
      **no** spurious conflict.

### 7.9 Autosave / unsaved-changes / navigation

- [ ] Edit a remote post, wait 30s → autosave stash written; navigate away and
      back → "Unsaved changes restored" toast and stashed content shown.
- [ ] **No spurious restore toast** when opening a server post that has no real
      local divergence.
- [ ] Navigate away from a dirty local draft → flushed to SQLite; reopening shows
      the latest content.
- [ ] Navigate away from a dirty remote post → stashed; not pushed to WordPress.
- [ ] After a successful publish/update, the autosave stash for that post is
      **deleted** (so the next open doesn't falsely restore).
- [ ] Dirty indicator (amber dot) shows for local drafts when `isDirty`, hidden
      for remote.
- [ ] Rapid navigation between items → no autosave from item A lands on item B
      (the `expectedItemID` guard); no crash; cancelled load tasks don't throw.
- [ ] Quitting the app with unsaved local-draft edits → recovered on next launch.

### 7.10 Delete / trash

- [ ] Trash a remote post → confirmation alert, then `force=false` (recoverable
      — appears in WordPress Trash, not gone).
- [ ] Trash a page → `/pages/{id}` trashed.
- [ ] Delete a local draft → removed from list and SQLite.
- [ ] Delete media → confirmation alert (permanent, `force=true`); after confirm
      it's gone from the grid and server.
- [ ] **Edge:** delete failure (permissions/offline) → `deleteError` alert; item
      stays.
- [ ] Cancel on any delete confirmation → nothing happens.

### 7.11 AI features (require an Anthropic API key configured)

- [ ] With no API key: ✦ toolbar button is **hidden** and the AI items are
      **absent** from the editor right-click menu (`aiEnabled == false`).
- [ ] Add a key in Settings → feature enables **without relaunch**.
- [ ] **Generate post:** ✦ on an empty editor opens the sheet directly; on a
      non-empty editor shows the "Replace Content?" alert first.
- [ ] Generate produces a title + structured HTML **with headings** (not just
      `<p>` — the prompt-structure gotcha).
- [ ] Generate with web search on → response reassembled correctly across
      fragmented blocks (the joining gotcha); citations don't break the
      TITLE/CONTENT parse.
- [ ] **Selection ops (right-click menu):** select text → right-click → Make
      Longer / Make Shorter / To Table / To List each appear (only when
      `aiEnabled && hasTextSelection`) and each works.
  - [ ] `hasTextSelection` updates correctly: the AI items appear only when there
        is a non-empty selection; collapse the selection → items gone on next
        right-click.
  - [ ] The AI menu items survive the AutoFill/Services re-filter (their selector
        strings are in `WebViewMenuFilter.allowed`).
- [ ] AI result inserts at **block boundaries** — no empty `<p>` fragments
      before/after, no blank paragraphs from inter-block whitespace. Verify the
      saved HTML has no stray empty paragraphs.
- [ ] Accept → content committed and `contentChanged` fires; Discard → original
      restored.
- [ ] **Accepted AI result is Gutenberg-transformed** — if the AI returns a
      table/list/heading, the saved HTML has `wp-block-*` classes and figure
      wrappers. Verify via `content.raw`.
- [ ] **Edge:** Claude error/timeout → original text restored, "couldn't
      complete" toast, editor not corrupted.
- [ ] The AI result bar (`AIResultPanel`) stays above Quill but **not** above
      other apps when you switch away (child-window gotcha); no rectangular
      shadow artifact (`hasShadow=false` gotcha); buttons visible in light mode
      (`.plain` style gotcha).
- [ ] Style guide: select sample posts in Settings → guide generated once;
      re-saving with unchanged samples makes **no** Claude call; changing the
      site URL clears samples and guide.

### 7.12 Settings panel & preferences

- [ ] Post settings panel for **posts** shows categories, tags, slug, excerpt,
      discussion; for **pages** shows parent + slug + discussion only (no
      categories/tags/excerpt) — the `isPage` gotcha.
- [ ] Amber accent applied throughout settings.
- [ ] Preferences opens from both the menu and the in-app sheet; `PreferencesView`
      works in the separate `Settings` scene **without EnvironmentObject** — i.e.
      sample post picker is populated.

### 7.13 Window / appearance / chrome

- [ ] Light and dark mode: sidebar (`wpSidebarBg`), panels (`wpPanelBg`),
      title/breadcrumb bars render with correct tokens; **title/breadcrumb bars
      white in dark mode** (open TODO — verify current state).
- [ ] Enter/exit full screen → title bar color stable (fixed — confirm).
- [ ] Title field + top border spacing correct (fixed — confirm).
- [ ] App icon/logo present in dock and about.
- [ ] Editor "Loading editor…" overlay shows then fades on `editorReady`; never
      sticks if the bundle loads.

### 7.14 Context menus (AppKit specifics)

- [ ] Right-click in the **editor (WKWebView)** → Cut/Copy/Paste present and
      correctly enabled/disabled; **no AutoFill/Services leakage** (the
      `willOpenMenu` + `NSMenuDelegate` re-filter gotcha).
- [ ] Right-click in the **title field** → only Cut/Copy/Paste; no AutoFill (the
      `RestrictedTextView` gotcha).
- [ ] Right-click a misspelled word → spelling suggestions appear.

### 7.15 Spell check

- [ ] "ABC" toolbar button highlights misspellings via decorations; highlights
      clear on first edit.
- [ ] No `NSUndefinedKeyException` crash on macOS 26 (the
      `continuousSpellCheckingEnabled` KVC gotcha) — launch and run spell check
      on the current OS.

---

## Non-functional & resilience

- **Offline / flaky network:** every network action degrades gracefully with a user-visible error, never a hang or crash.
- **Slow network:** saves show the saving state and disable buttons (`isSaving`); no double-submit on rapid clicks.
- **Large media library:** Media grid with 500+ items — scrolling stays smooth, pagination works, memory bounded.
- **File permissions:** `credentials.json` and `ai_settings.json` are chmod 600 (guarded by `JSONFileStoreTests.savedFileHasChmod600`).
- **Crash recovery:** force-quit mid-edit → local draft / autosave stash recovered on relaunch.
- **Performance:** `toWordPressHTML` runs on a 500ms debounce on every edit — on a large document it should not block typing.
- **Security:** pasted/loaded HTML with `<script>` or `onerror=` attributes is not executed; AI-returned HTML is inserted as content, not evaluated.

---

## Regression matrix — "known gotchas" guards

Each row is a documented gotcha from `CLAUDE.md`. ✅ = automated test, 👁 = manual verify.

| # | Gotcha | Guard |
|---|---|---|
| 1 | Pages omit `categories`/`tags` | ✅ `WPPostDecodingTests.pageOmittingCategoriesAndTagsDefaultsToEmpty` |
| 2 | `WPPost.type` routing posts vs pages | ✅ `WPPostDecodingTests` + 👁 §7.6 |
| 3 | Scheduling uses `date_gmt` not `date` | ✅ `PostPayloadTests.schedulingUsesDateGmtKeyNotDate` + 👁 §7.6 |
| 4 | Media dimensions as floats | ✅ `WPMediaDecodingTests.floatDimensionsDecodeToInt` |
| 5 | `slug` omitted when empty | ✅ `PostPayloadTests.nilSlugOmitsKeyFromJSON` + 👁 §7.6 |
| 6 | Trash `force=false` vs media `force=true` | ✅ `WordPressClientTests` + 👁 §7.9 |
| 7 | Cancellation re-thrown, not wrapped | ✅ `WordPressClientTests.urlErrorCancelledRethrowsAsCancellationError` |
| 8 | `searchLinks` ignores sub-failures | ✅ `WordPressClientTests.searchLinks*` |
| 9 | Web-search response joined across blocks | ✅ `AnthropicClientTests.multipleTextBlocksAreJoinedInOrder` |
| 10 | Web-search preamble before `TITLE:` | ✅ `AIPromptBuilderTests.webSearchPreambleGluedDirectlyToTitle` |
| 11 | AI prompt must name HTML elements | ✅ `AIPromptBuilderTests.generatePostPromptNamesHTMLElements` |
| 12 | `toWordPressHTML` transforms (all rows) | ✅ JS editor tests + 👁 §7.3 |
| 12a | Empty blockquote `<cite>` stripped on save | ✅ JS `empty cite is stripped` + 👁 §7.3 |
| 13 | List `<p>` unwrap only single-child | ✅ JS `multi-child <li> is left untouched` |
| 14 | Table thead promotion / figure wrap | ✅ JS table tests |
| 15 | Style-guide regeneration rules | 👁 §7.10 |
| 16 | Curly quotes in Swift strings | ✅ `DraftStoreTests.unicodeAndEmojiRoundTrip` + JS `unicode and emoji in text are preserved` |
| 17 | Autosave restore toast not spurious | 👁 §7.8 |
| 18 | Conflict baseline refresh (no false positive) | 👁 §7.7 |
| 19 | Selection-anchored link popover + sizing | 👁 §7.5 |
| 20 | `AIResultPanel` child-window / shadow / button style | 👁 §7.10 |
| 21 | AI insert at block boundaries (no empty `<p>`) | 👁 §7.10 |
| 22 | Media grid `Color.clear` layout | 👁 §7.2 |
| 23 | Context-menu AutoFill leakage | 👁 §7.13 |
| 24 | macOS 26 spell-check KVC crash | 👁 §7.14 |
| 25 | Ephemeral session (no keychain prompts) | 👁 §7.1 |
| 26 | Sidebar not `List`; layout not `NavigationSplitView` | 👁 §7.2 |
| 27 | `JSONFileStore` writes chmod 600 + atomic | ✅ `JSONFileStoreTests.savedFileHasChmod600` |
| 28 | `AppSupportDirectory` override isolation | ✅ `KeychainStoreTests.appSupportOverrideKeepsFilesInTempDir` |
| 29 | AI selection ops via right-click, gated on `hasTextSelection` | 👁 §7.10/§7.13 |
| 30 | Accepted AI result is Gutenberg-transformed | 👁 §7.10 |

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

### 16. View-model — `AppStateFilteredItemsTests` (10 tests)

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

## What's not yet automated

All automatable Swift and JS layers are now covered. The only remaining gap is the **manual/functional checklists** (§7), which require a live WordPress site and cannot be run headlessly.

Specifically: UI flows, SwiftUI/AppKit rendering behavior, WKWebView bridge interactions, conflict detection, autosave restoration, and AI result panel visual correctness. These are documented in §7 and should be run before each release.
